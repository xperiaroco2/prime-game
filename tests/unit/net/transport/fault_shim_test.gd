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
