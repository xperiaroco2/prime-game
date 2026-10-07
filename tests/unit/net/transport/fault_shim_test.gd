extends GdUnitTestSuite
## WebRtcTransport's test-only fault shim (FaultShim, the M6 design §5): its late LATEST packets
## (M6-6), seeded, so a run replays.


func test_a_latest_packet_is_late_at_the_rate_by_the_delay_and_the_seed_replays_it() -> void:
	var shim := WebRtcTransport.FaultShim.new(371)
	shim.latest_late = 0.2
	shim.latest_delay_ms = 120
	var again := WebRtcTransport.FaultShim.new(371)
	again.latest_late = 0.2
	again.latest_delay_ms = 120
	var late := 0
	for i in 1000:
		var delay := shim.latest_delay()
		assert_int(again.latest_delay()).is_equal(delay)
		assert_bool(delay == 0 or delay == 120).is_true()
		if delay > 0:
			late += 1
	assert_int(late).is_between(150, 250)


func test_no_delay_by_default() -> void:
	var shim := WebRtcTransport.FaultShim.new(371)
	shim.latest_delay_ms = 120
	for i in 100:
		assert_int(shim.latest_delay()).is_equal(0)


## WebRtcTransport with what LaneOrder would be handed (_take_latest) recorded, no channel.
class Recording:
	extends WebRtcTransport

	var taken: Array[int] = []

	func _init() -> void:
		super(NetKindTable.new())

	func _take_latest(_conn: Conn, bytes: PackedByteArray, _now: int) -> void:
		taken.append(bytes[0])


func test_a_late_latest_packet_holds_back_the_ones_read_after_it_in_order() -> void:
	var transport := Recording.new()
	var shim := WebRtcTransport.FaultShim.new(371)
	shim.latest_late = 0.3
	shim.latest_delay_ms = 120
	transport.use_faults(shim)
	var conn := WebRtcTransport.Conn.new()
	var held_back := 0
	# Packet n is read in the poll at 10 n ms (the poll before at 10 n - 10).
	for n in 60:
		var now := n * 10
		transport._release_late_latest(conn, now)
		transport._shim_latest(conn, PackedByteArray([n]), now, now - 10)
		if not conn.late_latest.is_empty() and conn.late_latest[0][0] != n:
			held_back += 1
	transport._release_late_latest(conn, 10_000)
	var expected: Array[int] = []
	for n in 60:
		expected.append(n)
	assert_array(transport.taken).is_equal(expected)
	assert_int(held_back).override_failure_message("no packet waited behind a late one").is_greater(
		0
	)


func test_a_late_latest_packet_comes_at_its_due_time_from_the_poll_before() -> void:
	var transport := Recording.new()
	var shim := WebRtcTransport.FaultShim.new(371)
	shim.latest_late = 1.0
	shim.latest_delay_ms = 120
	transport.use_faults(shim)
	var conn := WebRtcTransport.Conn.new()
	transport._shim_latest(conn, PackedByteArray([7]), 100, 90)
	transport._release_late_latest(conn, 209)
	assert_array(transport.taken).is_empty()
	transport._release_late_latest(conn, 210)
	assert_array(transport.taken).is_equal([7])
