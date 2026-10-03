extends GdUnitTestSuite
## RelayMeter (ARCHITECTURE §4.5 "The host's counters", M5-4): the session totals of the upload are
## plain 64-bit ints, so a long hosted session's bytes never wrap at 2^31 as a Vector2i's would.


func test_the_upload_totals_add_past_two_to_the_thirty_first() -> void:
	var meter := RelayMeter.new()
	var window := Vector2i(1 << 30, 1000)
	for i in 3:
		meter.add_voice_upload(window)
		meter.add_snapshot_upload(window)
		meter.add_other_upload(window)
	var counted := meter.to_dict(VoiceRelay.new(), 0, 0)
	for part: String in ["voice", "snapshot", "other"]:
		assert_int(counted[StringName(part + "_up_bytes")]).is_equal(3 << 30)
		assert_int(counted[StringName(part + "_up_datagrams")]).is_equal(3000)


func test_each_part_of_the_upload_counts_apart() -> void:
	var meter := RelayMeter.new()
	meter.add_voice_upload(Vector2i(100, 2))
	meter.add_snapshot_upload(Vector2i(30, 1))
	meter.add_other_upload(Vector2i(7, 1))
	meter.add_voice_upload(Vector2i(50, 1))
	var counted := meter.to_dict(VoiceRelay.new(), 0, 2500)
	assert_int(counted[&"voice_up_bytes"]).is_equal(150)
	assert_int(counted[&"voice_up_datagrams"]).is_equal(3)
	assert_int(counted[&"snapshot_up_bytes"]).is_equal(30)
	assert_int(counted[&"other_up_bytes"]).is_equal(7)
	assert_int(counted[&"session_ms"]).is_equal(2)
