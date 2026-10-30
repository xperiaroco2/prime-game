extends GdUnitTestSuite
## ModeCheck on the seated pose (ARCHITECTURE §9.1, §7.1.19; the engineer's answer 1a on PR #1382,
## #1383): a TakePose runs only in a player's action, after an AtMarker that is not negated, so no
## mode lets a player sit anywhere; an AtMarker has a tag and its numbers within their bounds. Each
## found on FixtureMoves.posing(FixtureModes.basic()) with one thing wrong.


func test_the_posing_fixture_passes() -> void:
	_expect_none(FixtureMoves.posing(FixtureModes.basic()))


func test_a_pose_rule_without_at_marker_is_refused() -> void:
	var mode := FixtureMoves.posing(FixtureModes.basic())
	_pose_rule(mode).conditions = []
	_expect(mode, "rule Pose seats the actor, which requires the condition AtMarker")


func test_a_negated_at_marker_does_not_count() -> void:
	var mode := FixtureMoves.posing(FixtureModes.basic())
	(_pose_rule(mode).conditions[0] as AtMarker).negate = true
	_expect(mode, "rule Pose seats the actor, which requires the condition AtMarker")


func test_another_location_condition_does_not_count() -> void:
	# AtStation and InReach need a target, which Pose names none of: only AtMarker places it.
	var mode := FixtureMoves.posing(FixtureModes.basic())
	var reach := InReach.new()
	reach.reach_m = 2.0
	_pose_rule(mode).conditions = [reach]
	_expect(mode, "requires the condition AtMarker")


func test_a_pose_in_a_reaction_is_refused() -> void:
	var mode := FixtureMoves.posing(FixtureModes.basic())
	mode.reactions = [
		FixtureModes.rule(Facts.ITEM_RESTED, [FixtureMoves.seat_condition()], [TakePose.new()])
	]
	_expect(mode, "mode.reactions: rule item_rested seats a player")


func test_an_at_marker_needs_a_tag_and_numbers_in_bounds() -> void:
	var cases: Array[Array] = [
		[&"tag", &"", "AtMarker has no tag"],
		[&"radius_m", 0.0, "AtMarker radius_m"],
		[&"radius_m", 10.5, "AtMarker radius_m"],
		[&"height_m", 0.05, "AtMarker height_m"],
		[&"height_m", 11.0, "AtMarker height_m"],
	]
	for case: Array in cases:
		var mode := FixtureMoves.posing(FixtureModes.basic())
		_pose_rule(mode).conditions[0].set(case[0] as StringName, case[1])
		_expect(mode, case[2] as String)


func test_an_at_marker_tag_is_an_id() -> void:
	var mode := FixtureMoves.posing(FixtureModes.basic())
	(_pose_rule(mode).conditions[0] as AtMarker).tag = &"Chair Seat"
	_expect(mode, "Chair Seat")


func _pose_rule(mode: GameMode) -> Rule:
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.POSE:
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
