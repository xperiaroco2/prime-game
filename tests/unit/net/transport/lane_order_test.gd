extends GdUnitTestSuite
## LaneOrder: the 4-byte header that keeps LATEST in order with RELIABLE on backends whose channels
## do not (the M6 design §2.2, E49). A sender and a receiver LaneOrder stand for the two ends of one
## connection; _poll() reads like a backend: the LATEST channel first, then the RELIABLE one, then
## the stall check.

const PEER := 2
const CLAIM := 12  # a LATEST kind, a MoveClaim
const OTHER := 13  # a second LATEST kind
const PICKUP := 11  # a RELIABLE kind
const TICK_MS := 50  # LATEST at 20 Hz

var _sender: LaneOrder
var _receiver: LaneOrder
## What the receiver handed on, in order: "R<n>" for a reliable frame, "L<n>" for a LATEST one.
var _log: PackedStringArray


func before_test() -> void:
	_sender = LaneOrder.new()
	_receiver = LaneOrder.new()
	_log = PackedStringArray()


func test_header_is_reliable_count_then_latest_seq_little_endian() -> void:
	var frame := NetFrame.encode(CLAIM, PackedByteArray([9]))
	assert_array(Array(_sender.stamp_latest(PEER, frame))).is_equal([0, 0, 0, 0, CLAIM, 1, 0, 9])
	for _i in 300:
		_sender.count_reliable_sent(PEER)
	assert_array(Array(_sender.stamp_latest(PEER, frame).slice(0, 4))).is_equal([44, 1, 1, 0])


func test_counts_are_per_peer() -> void:
	_sender.count_reliable_sent(3)
	assert_array(Array(_sender.stamp_latest(PEER, _claim(1)).slice(0, 4))).is_equal([0, 0, 0, 0])
	assert_array(Array(_sender.stamp_latest(3, _claim(1)).slice(0, 4))).is_equal([1, 0, 0, 0])


func test_in_order_packets_are_delivered_in_order() -> void:
	var l1 := _latest(1)
	var r1 := _reliable(1)
	var l2 := _latest(2)
	_poll(0, [l1], [])
	_poll(50, [], [r1])
	_poll(100, [l2], [])
	assert_array(Array(_log)).is_equal(["L1", "R1", "L2"])


func test_latest_sent_after_a_reliable_in_flight_waits_for_it() -> void:
	var r1 := _reliable(1)
	var l2 := _latest(2)
	var read := _receiver.read_latest(PEER, l2, 0)
	assert_int(read.verdict).is_equal(LaneOrder.Verdict.HELD)
	assert_int(_receiver.held_count(PEER)).is_equal(1)
	_poll(0, [], [r1])
	assert_array(Array(_log)).is_equal(["R1", "L2"])
	assert_int(_receiver.held_count(PEER)).is_equal(0)


func test_same_poll_reorder_keeps_the_send_order() -> void:
	# Sent: a claim, the PickUp, a claim. Both claims arrive in the poll the PickUp does.
	var l1 := _latest(1)
	var r1 := _reliable(1)
	var l2 := _latest(2)
	_poll(0, [l2, l1], [r1])
	assert_array(Array(_log)).is_equal(["L1", "R1", "L2"])


func test_latest_sent_before_a_delivered_reliable_is_never_delivered() -> void:
	# The stale claim: sent before the PickUp, late past it. Delivering it would make the host
	# check the next intent against a claim older than the PickUp's.
	var stale := _latest(1)
	var r1 := _reliable(1)
	_poll(0, [], [r1])
	_poll(50, [stale], [])
	assert_array(Array(_log)).is_equal(["R1"])
	assert_int(_receiver.read_latest(PEER, stale, 100).verdict).is_equal(LaneOrder.Verdict.DROPPED)


func test_lost_latest_packets_cost_nothing_else() -> void:
	var l1 := _latest(1)
	_latest(2)  # lost
	var l3 := _latest(3)
	_poll(0, [l1], [])
	_poll(100, [l3], [])
	assert_array(Array(_log)).is_equal(["L1", "L3"])


func test_an_older_latest_packet_after_a_newer_one_is_dropped() -> void:
	var l1 := _latest(1)
	var l2 := _latest(2)
	_poll(0, [l2], [])
	_poll(50, [l1], [])
	assert_array(Array(_log)).is_equal(["L2"])


func test_duplicates_are_delivered_once() -> void:
	var l1 := _latest(1)
	_poll(0, [l1, l1], [])
	var r1 := _reliable(1)
	var l2 := _latest(2)
	_poll(50, [l2, l2], [])
	assert_int(_receiver.held_count(PEER)).is_equal(1)
	_poll(100, [l2], [r1])
	assert_array(Array(_log)).is_equal(["L1", "R1", "L2"])


func test_counts_and_seqs_wrap() -> void:
	for _i in 65535:
		_sender.count_reliable_sent(PEER)
		_receiver.read_reliable(PEER, 0)
	for _i in 65534:
		_sender.stamp_latest(PEER, _claim(0))
	var l1 := _latest(1)  # reliable_sent 65535, seq 65534
	var l2 := _latest(2)  # seq 65535
	var r1 := _reliable(1)  # the count wraps to 0
	var l3 := _latest(3)  # reliable_sent 0, seq 0
	assert_array(Array(l3.slice(0, 4))).is_equal([0, 0, 0, 0])
	_poll(0, [l1], [])
	_poll(50, [l3], [r1])
	_poll(100, [l2], [])  # sent before r1: behind across the wrap
	assert_array(Array(_log)).is_equal(["L1", "R1", "L3"])
	assert_int(_receiver.read_latest(PEER, l1, 150).verdict).is_equal(LaneOrder.Verdict.DROPPED)


func test_backlog_over_the_cap_keeps_the_peer_and_delivers_the_newest_after_its_reliable() -> void:
	# A thawed sender: 50 claims, the PickUp, 12 more claims, all read in one poll, LATEST first.
	var sent_before: Array[PackedByteArray] = []
	for n in range(1, 51):
		sent_before.append(_latest(n))
	var r1 := _reliable(1)
	var sent_after: Array[PackedByteArray] = []
	for n in range(51, 63):
		sent_after.append(_latest(n))
	var latest := sent_before + sent_after
	var stalled := _poll(0, latest, [r1])
	assert_int(stalled.size()).is_equal(0)
	assert_int(_receiver.take_superseded()).is_equal(4)
	assert_int(_receiver.take_superseded()).is_equal(0)
	var expected: Array[String] = []
	for n in range(1, 51):
		expected.append("L%d" % n)
	expected.append("R1")
	for n in range(55, 63):
		expected.append("L%d" % n)
	assert_array(Array(_log)).is_equal(expected)
	assert_int(_receiver.held_count(PEER)).is_equal(0)


func test_full_hold_drops_the_oldest_of_the_arriving_kind() -> void:
	var r1 := _reliable(1)
	var held: Array[PackedByteArray] = [_latest(1, OTHER)]
	for n in range(2, 10):
		held.append(_latest(n))
	_poll(0, held, [])
	assert_int(_receiver.held_count(PEER)).is_equal(LaneOrder.HOLD_CAP)
	assert_int(_receiver.take_superseded()).is_equal(1)
	_poll(50, [], [r1])
	assert_array(Array(_log)).is_equal(["R1", "O1", "L3", "L4", "L5", "L6", "L7", "L8", "L9"])


func test_a_reliable_packet_three_seconds_late_keeps_the_peer() -> void:
	var r1 := _reliable(1)
	var now := 0
	var n := 1
	while now <= 3000:
		assert_int(_poll(now, [_latest(n)], []).size()).is_equal(0)
		now += TICK_MS
		n += 1
	_poll(now, [_latest(n)], [r1])
	assert_int(_receiver.held_count(PEER)).is_equal(0)
	assert_str(_log[0]).is_equal("R1")
	assert_str(_log[_log.size() - 1]).is_equal("L%d" % n)
	assert_int(_receiver.stalled_peers(now + LaneOrder.STALL_MS).size()).is_equal(0)


func test_a_count_that_disagrees_for_twenty_seconds_disconnects() -> void:
	# The sender counted a reliable packet that never arrives; LATEST keeps flowing at 20 Hz and
	# the full hold keeps dropping its oldest, which never restarts the clock.
	_reliable(1)
	var now := 0
	var n := 1
	while now <= LaneOrder.STALL_MS:
		assert_int(_poll(now, [_latest(n)], []).size()).is_equal(0)
		now += TICK_MS
		n += 1
	assert_array(Array(_poll(now, [_latest(n)], []))).is_equal([PEER])
	assert_array(Array(_log)).is_empty()


func test_each_release_restarts_the_clock() -> void:
	# r1 is 15 s late; r2, sent 200 ms before r1 arrives, is 19 s late. Released packets of r1
	# restart the clock, so the hold that waits for r2 is 19 s old, never 34 s.
	var r1 := _reliable(1)
	var r2 := PackedByteArray()
	var now := 0
	var n := 1
	while now <= 34000:
		if now == 14800:
			r2 = _reliable(2)
		var arrived: Array[PackedByteArray] = []
		if now == 15000:
			arrived.append(r1)
		assert_int(_poll(now, [_latest(n)], arrived).size()).is_equal(0)
		now += TICK_MS
		n += 1
	assert_int(_receiver.held_count(PEER)).is_greater(0)
	assert_array(Array(_receiver.stalled_peers(15000 + LaneOrder.STALL_MS + 1))).is_equal([PEER])
	_poll(now, [], [r2])
	assert_int(_receiver.held_count(PEER)).is_equal(0)
	assert_int(_receiver.stalled_peers(now + LaneOrder.STALL_MS * 2).size()).is_equal(0)


func test_a_latest_packet_shorter_than_the_header_is_rejected() -> void:
	for size in LaneOrder.HEADER_BYTES:
		var bytes := PackedByteArray()
		bytes.resize(size)
		var read := _receiver.read_latest(PEER, bytes, 0)
		assert_int(read.verdict).is_equal(LaneOrder.Verdict.REJECTED)
		assert_int(read.reject).is_equal(NetRejects.Reason.ORDER_HEADER_SHORT)
		assert_int(read.frame.size()).is_equal(0)
	_poll(0, [_latest(1)], [])
	assert_array(Array(_log)).is_equal(["L1"])


func test_the_header_alone_hands_on_an_empty_frame_for_the_decoder_to_reject() -> void:
	var read := _receiver.read_latest(PEER, PackedByteArray([0, 0, 0, 0]), 0)
	assert_int(read.verdict).is_equal(LaneOrder.Verdict.DELIVERED)
	assert_int(read.frame.size()).is_equal(0)


func test_held_packets_are_discarded_when_the_peer_goes() -> void:
	var r1 := _reliable(1)
	_poll(0, [_latest(1), _latest(2)], [])
	assert_int(_receiver.held_count(PEER)).is_equal(2)
	_receiver.forget(PEER)
	assert_int(_receiver.held_count(PEER)).is_equal(0)
	assert_int(_receiver.stalled_peers(LaneOrder.STALL_MS * 2).size()).is_equal(0)
	_poll(50, [], [r1])
	assert_array(Array(_log)).is_equal(["R1"])


func test_clear_forgets_every_peer() -> void:
	_reliable(1)
	_poll(0, [_latest(1)], [])
	_receiver.clear()
	assert_int(_receiver.held_count(PEER)).is_equal(0)
	assert_int(_receiver.stalled_peers(LaneOrder.STALL_MS * 2).size()).is_equal(0)


func test_one_peer_holding_does_not_hold_another() -> void:
	_reliable(1)
	_poll(0, [_latest(1)], [])
	var other := _sender.stamp_latest(3, _claim(7))
	var read := _receiver.read_latest(3, other, 0)
	assert_int(read.verdict).is_equal(LaneOrder.Verdict.DELIVERED)
	assert_array(Array(_receiver.stalled_peers(LaneOrder.STALL_MS + 1))).is_equal([PEER])


func _claim(n: int, kind := CLAIM) -> PackedByteArray:
	return NetFrame.encode(kind, PackedByteArray([n]))


## The next LATEST packet the sender writes to PEER.
func _latest(n: int, kind := CLAIM) -> PackedByteArray:
	return _sender.stamp_latest(PEER, _claim(n, kind))


## The next RELIABLE packet the sender writes to PEER (no header).
func _reliable(n: int) -> PackedByteArray:
	_sender.count_reliable_sent(PEER)
	return NetFrame.encode(PICKUP, PackedByteArray([n]))


## One backend poll at now_ms: LATEST first, then RELIABLE, then the stalled peers.
func _poll(
	now_ms: int, latest: Array[PackedByteArray], reliable: Array[PackedByteArray]
) -> PackedInt32Array:
	for bytes in latest:
		var read := _receiver.read_latest(PEER, bytes, now_ms)
		if read.verdict == LaneOrder.Verdict.DELIVERED:
			_log.append(_named(read.frame))
	for bytes in reliable:
		var released := _receiver.read_reliable(PEER, now_ms)
		_log.append(_named(bytes))
		for frame in released:
			_log.append(_named(frame))
	return _receiver.stalled_peers(now_ms)


static func _named(frame: PackedByteArray) -> String:
	var prefix := {CLAIM: "L", OTHER: "O", PICKUP: "R"}[frame.decode_u8(0)] as String
	return "%s%d" % [prefix, frame.decode_u8(NetFrame.HEADER_BYTES)]
