extends GdUnitTestSuite
## ModeCheck on the pose wheel (ARCHITECTURE §9.1, §7.1.23; #1485): a TakeWheelPose runs only in a
## player's action, after a WheelPoseInRange that is not negated, in a mode that names its
## WheelPoses; the WheelPoses hold 1 to 15 unique wire ids per list. Each found on
## FixtureMoves.wheeling(FixtureModes.basic()) with one thing wrong.


func test_the_wheeling_fixture_passes() -> void:
	_expect_none(FixtureMoves.wheeling(FixtureModes.basic()))


func test_a_wheel_pose_rule_without_the_range_is_refused() -> void:
	var mode := FixtureMoves.wheeling(FixtureModes.basic())
	_wheel_rule(mode).conditions.remove_at(0)
	_expect(
		mode, "rule WheelPose wheel-poses the actor, which requires the condition WheelPoseInRange"
	)


func test_a_negated_range_does_not_count() -> void:
	var mode := FixtureMoves.wheeling(FixtureModes.basic())
	(_wheel_rule(mode).conditions[0] as WheelPoseInRange).negate = true
	_expect(mode, "requires the condition WheelPoseInRange")


func test_a_wheel_pose_in_a_reaction_is_refused() -> void:
	var mode := FixtureMoves.wheeling(FixtureModes.basic())
	mode.reactions = [
		FixtureModes.rule(Facts.ITEM_RESTED, [WheelPoseInRange.new()], [TakeWheelPose.new()])
	]
	_expect(mode, "mode.reactions: rule item_rested wheel-poses a player")


func test_a_mode_without_wheel_poses_is_refused() -> void:
	var mode := FixtureMoves.wheeling(FixtureModes.basic())
	mode.wheel_poses = null
	_expect(mode, "rule WheelPose takes a wheel pose, but the mode has no wheel_poses")


func test_the_lists_hold_1_to_15_unique_ids() -> void:
	var cases: Array[Array] = [
		[&"legs", PackedStringArray(), "legs holds 0 ids, outside 1 to 15"],
		[&"arms", _ids(16), "arms holds 16 ids, outside 1 to 15"],
		[&"legs", PackedStringArray(["squat", "squat"]), "legs id squat is listed twice"],
		[&"arms", PackedStringArray(["Flex"]), 'arms id "Flex" is not'],
	]
	for case: Array in cases:
		var mode := FixtureMoves.wheeling(FixtureModes.basic())
		mode.wheel_poses.set(case[0] as StringName, case[1])
		_expect(mode, case[2] as String)
	var full := FixtureMoves.wheeling(FixtureModes.basic())
	full.wheel_poses.legs = _ids(15)
	full.wheel_poses.arms = _ids(15)
	_expect_none(full)


func test_has_pick_takes_one_of_each() -> void:
	var poses := WheelPoses.new()
	poses.legs = _ids(2)
	poses.arms = _ids(3)
	assert_bool(poses.has_pick(1, 2)).is_true()
	assert_bool(poses.has_pick(0, 0)).is_true()
	assert_bool(poses.has_pick(2, 0)).is_false()
	assert_bool(poses.has_pick(0, 3)).is_false()
	assert_bool(poses.has_pick(-1, 0)).is_false()
	assert_bool(poses.has_pick(0, -1)).is_false()


static func _ids(count: int) -> PackedStringArray:
	var ids := PackedStringArray()
	for index in count:
		ids.append("pose_%d" % index)
	return ids


func _wheel_rule(mode: GameMode) -> Rule:
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.WHEEL_POSE:
			return rule
	return null


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
