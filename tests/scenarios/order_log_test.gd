extends GdUnitTestSuite
## The leak test's order check over WebRTC (OrderLog, the M6 design §5, M6-6): what one side
## delivered from a peer is what that peer sent, in order, with LATEST messages left out at most.
## `tools/run.sh bots <scenario> --instances N --transport webrtc` runs it on real transports.

const R := true
const L := false


func test_the_order_as_sent_passes_with_latest_messages_left_out() -> void:
	var sent_log := _sent([[1, R], [2, L], [3, L], [4, R], [5, L]])
	var got := _fingerprints([1, 3, 4, 5])
	assert_array(_problems(sent_log, got, true)).is_empty()
	assert_array(_problems(sent_log, _fingerprints([]), true)).is_empty()
	# Messages still on their way at the end are no problem.
	assert_array(_problems(sent_log, _fingerprints([1, 2]), true)).is_empty()


func test_a_latest_message_delivered_after_a_later_reliable_one_fails() -> void:
	# LaneOrder's "behind" rule: a LATEST message sent before a reliable one already delivered.
	var sent_log := _sent([[1, L], [2, R], [3, L]])
	var found := _problems(sent_log, _fingerprints([2, 1, 3]), true)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("message 0 was delivered after message 1")


func test_a_reliable_message_skipped_or_reordered_fails() -> void:
	var sent_log := _sent([[1, R], [2, R], [3, L]])
	assert_str(_problems(sent_log, _fingerprints([1, 3]), true)[0]).contains(
		"RELIABLE message 1 was not delivered"
	)
	assert_array(_problems(sent_log, _fingerprints([2, 1]), true)).is_not_empty()


func test_a_message_never_sent_to_it_fails_when_the_list_is_complete() -> void:
	# A swapped id-to-connection map: one peer's messages delivered to another.
	var sent_log := _sent([[1, R], [2, L]])
	assert_str(_problems(sent_log, _fingerprints([1, 99]), true)[0]).contains("never sent to it")
	# A remote bot's file ends before its last sends: what follows the first one missing is past it.
	assert_array(_problems(sent_log, _fingerprints([1, 99, 98]), false)).is_empty()
	# But a message the file holds cannot come after one sent past its end, and no RELIABLE
	# message the file holds may be missing then.
	assert_str(_problems(sent_log, _fingerprints([1, 99, 2]), false)[0]).contains(
		"message 1 was delivered after one sent after the list's end"
	)
	var reliable_last := _sent([[1, L], [2, R]])
	assert_str(_problems(reliable_last, _fingerprints([1, 99]), false)[0]).contains(
		"RELIABLE message 1 was not delivered before one sent after the list"
	)


func test_check_client_walks_both_ways_and_sees_a_recording_that_broke() -> void:
	var host := OrderLog.new()
	var client := OrderLog.new()
	_exchange(host, client, 7)
	assert_array(host.check_client("bot 2", 7, client.of(NetTransport.HOST_ID))).is_empty()
	var from_file := OrderLog.from_data(client.to_data(NetTransport.HOST_ID))
	assert_array(host.check_client("bot 2", 7, from_file)).is_empty()
	var empty := OrderLog.from_data({})
	var found := host.check_client("bot 2", 7, empty)
	assert_str(found[0]).contains("none recorded as delivered")
	var silent := OrderLog.from_data({"delivered": from_file.delivered})
	assert_str(host.check_client("bot 2", 7, silent)[0]).contains("none recorded as sent")
	assert_str(host.summary("bot 2", 7, from_file)).is_equal(
		"bot 2: host to it 2 sent, 2 delivered; it to host 1 sent, 1 delivered"
	)


func test_a_fingerprint_tells_kinds_and_payloads_apart() -> void:
	var payload := PackedByteArray([1, 2, 3])
	var other := PackedByteArray([1, 2, 4])
	assert_int(OrderLog.fingerprint(5, payload)).is_equal(OrderLog.fingerprint(5, payload))
	assert_int(OrderLog.fingerprint(5, payload)).is_not_equal(OrderLog.fingerprint(6, payload))
	assert_int(OrderLog.fingerprint(5, payload)).is_not_equal(OrderLog.fingerprint(5, other))


## The host sends two messages to `peer`, which sends one back; both sides record them.
func _exchange(host: OrderLog, client: OrderLog, peer: int) -> void:
	var welcome := PackedByteArray([7])
	var snapshot := PackedByteArray([8])
	var hello := PackedByteArray([9])
	host.record_sent(peer, 33, welcome, R)
	host.record_sent(peer, 64, snapshot, L)
	client.record_delivered(NetTransport.HOST_ID, 33, welcome)
	client.record_delivered(NetTransport.HOST_ID, 64, snapshot)
	client.record_sent(NetTransport.HOST_ID, 1, hello, R)
	host.record_delivered(peer, 1, hello)


## An OrderLog whose peer 2 was sent the messages [id, reliable], each a one-byte payload `id`.
func _sent(messages: Array) -> OrderLog:
	var sent_log := OrderLog.new()
	for pair: Array in messages:
		sent_log.record_sent(2, 40, PackedByteArray([pair[0] as int]), pair[1] as bool)
	return sent_log


func _fingerprints(ids: Array) -> PackedInt64Array:
	var found := PackedInt64Array()
	for id: int in ids:
		found.append(OrderLog.fingerprint(40, PackedByteArray([id])))
	return found


func _problems(sent_log: OrderLog, got: PackedInt64Array, complete: bool) -> PackedStringArray:
	var lists := sent_log.of(2)
	return OrderLog.problems("host to bot 2", lists.sent, lists.reliable, got, complete)
