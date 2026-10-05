extends GdUnitTestSuite
## WebRtcTransport's test-only fault shim (FaultShim, the M6 design §5): its late LATEST packets
## (M6-6), seeded, so a run replays.


func test_latest_packets_are_late_by_up_to_the_delay_and_the_seed_replays_them() -> void:
	var shim := WebRtcTransport.FaultShim.new(371)
	shim.latest_delay_ms = 200
	var again := WebRtcTransport.FaultShim.new(371)
	again.latest_delay_ms = 200
	var late := 0
	for i in 1000:
		var delay := shim.latest_delay()
		assert_int(delay).is_between(0, 200)
		assert_int(again.latest_delay()).is_equal(delay)
		if delay > 100:
			late += 1
	# Later than RELIABLE's 50 ms plus a 20 Hz interval often enough to reorder across channels.
	assert_int(late).is_greater(300)


func test_no_delay_by_default() -> void:
	var shim := WebRtcTransport.FaultShim.new(371)
	for i in 100:
		assert_int(shim.latest_delay()).is_equal(0)
