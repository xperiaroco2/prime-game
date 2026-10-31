extends GdUnitTestSuite
## WheelPoseCode (#1485; ARCHITECTURE §7.1.23): the whole pose as one byte, 0 for none, the leg
## stance's index + 1 in the low nibble and the arm gesture's + 1 in the high one; a half or
## out-of-range pair is none, and every whole pair round-trips.


func test_none_and_half_pairs_are_zero() -> void:
	assert_int(WheelPoseCode.encode(-1, -1)).is_equal(WheelPoseCode.NONE)
	assert_int(WheelPoseCode.encode(0, -1)).is_equal(WheelPoseCode.NONE)
	assert_int(WheelPoseCode.encode(-1, 0)).is_equal(WheelPoseCode.NONE)
	assert_int(WheelPoseCode.encode(WheelPoseCode.MAX_COUNT, 0)).is_equal(WheelPoseCode.NONE)
	assert_int(WheelPoseCode.encode(0, WheelPoseCode.MAX_COUNT)).is_equal(WheelPoseCode.NONE)
	assert_int(WheelPoseCode.legs_of(WheelPoseCode.NONE)).is_equal(-1)
	assert_int(WheelPoseCode.arms_of(WheelPoseCode.NONE)).is_equal(-1)


func test_the_nibbles() -> void:
	assert_int(WheelPoseCode.encode(0, 0)).is_equal(0x11)
	assert_int(WheelPoseCode.encode(5, 7)).is_equal(0x86)
	assert_int(WheelPoseCode.encode(14, 14)).is_equal(0xFF)


func test_every_whole_pair_round_trips_in_one_byte() -> void:
	for legs in WheelPoseCode.MAX_COUNT:
		for arms in WheelPoseCode.MAX_COUNT:
			var code := WheelPoseCode.encode(legs, arms)
			assert_int(code).is_between(1, 255)
			assert_bool(WheelPoseCode.is_pose(code)).is_true()
			assert_int(WheelPoseCode.legs_of(code)).is_equal(legs)
			assert_int(WheelPoseCode.arms_of(code)).is_equal(arms)


func test_a_byte_with_one_empty_nibble_is_no_pose() -> void:
	for code: int in [0x01, 0x0F, 0x10, 0xF0, 256, -1]:
		assert_bool(WheelPoseCode.is_pose(code)).is_false()
		assert_bool(WheelPoseCode.is_valid(code)).is_false()
		assert_int(WheelPoseCode.legs_of(code)).is_equal(-1)
	assert_bool(WheelPoseCode.is_valid(WheelPoseCode.NONE)).is_true()
