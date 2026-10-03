extends GdUnitTestSuite
## The target conditions when the rule's target is not there (ARCHITECTURE §9.4): TargetInReach and
## TargetInSight, which read the target player through Channels.target_of, and InSight, which reads
## the target item through Items.target_of. Each stands alone on its rule here (the base mode puts
## TargetDowned or ItemOnGround before them, which refuse first), so its own guard decides: a
## target that does not exist is out of reach or out of sight, never in it. The refusal goes to the
## sender alone and the rule's effect does not run.
## Parked in tests/unit/channel/ only because #274 owned tests/unit/life/ and tests/unit/items/
## when #271 added it: it belongs there, beside the conditions' own suites.

const P1 := 1
const P2 := 2
const NOBODY := 99
const NO_ITEM := 999
const RAN := "ran"


func test_target_in_reach_refuses_a_target_who_is_not_there() -> void:
	var reach := TargetInReach.new()
	reach.reach_m = FixtureCombatModes.RAISE_REACH_M
	var game := _raising_with(reach)
	FixtureCombatModes.raise(game, P1, NOBODY)
	_assert_refused(game, TargetInReach.OUT_OF_REACH)


func test_target_in_sight_refuses_a_target_who_is_not_there() -> void:
	var game := _raising_with(TargetInSight.new())
	FixtureCombatModes.raise(game, P1, NOBODY)
	_assert_refused(game, TargetInSight.BLOCKED)


func test_the_same_rules_pass_for_a_target_who_is_there() -> void:
	var reach := TargetInReach.new()
	reach.reach_m = FixtureCombatModes.RAISE_REACH_M
	for condition: Condition in [reach, TargetInSight.new()]:
		var game := _raising_with(condition)
		FixtureCombatModes.raise(game, P1, P2)
		assert_array(FixtureModes.rejections(game, P1)).is_empty()
		assert_array(FixtureModes.notes(game)).contains([RAN])


func test_in_sight_refuses_an_item_that_is_not_there() -> void:
	var mode := FixtureItemModes.basic()
	var effects: Array[RuleEffect] = [FixtureNote.of(RAN)]
	var conditions: Array[Condition] = [InSight.new()]
	_replace_rule(mode, Intents.PICK_UP, conditions, effects)
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureModes.send(game, Intents.PICK_UP, P1, {"item": NO_ITEM})
	_assert_refused(game, InSight.BLOCKED)
	# The same rule passes for an item that lies in sight.
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P1, tool)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([InSight.BLOCKED])
	assert_array(FixtureModes.notes(game)).contains([RAN])


## FixtureCombatModes.raising() whose Raise has `condition` alone and notes RAN to everyone; P1
## and P2 stand 1 m apart in plain sight.
func _raising_with(condition: Condition) -> Match:
	var mode := FixtureCombatModes.raising()
	var effects: Array[RuleEffect] = [FixtureNote.of(RAN)]
	var conditions: Array[Condition] = [condition]
	_replace_rule(mode, Intents.RAISE, conditions, effects)
	var game := FixtureCombatModes.in_round(mode, [P1, P2])
	assert_array(Array(game.refusals)).is_empty()
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	return game


## Replaces the mode's action on `trigger` (which must be there) with one of `conditions` and
## `effects`.
func _replace_rule(
	mode: GameMode, trigger: StringName, conditions: Array[Condition], effects: Array[RuleEffect]
) -> void:
	var replaced := 0
	for i in mode.actions.size():
		if mode.actions[i].trigger == trigger:
			mode.actions[i] = FixtureModes.rule(trigger, conditions, effects)
			replaced += 1
	assert_int(replaced).is_equal(1)


func _assert_refused(game: Match, reason: StringName) -> void:
	assert_array(FixtureModes.rejections(game, P1)).is_equal([reason])
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_array(FixtureModes.notes(game)).not_contains([RAN])
	assert_array(Array(game.diagnostics)).is_empty()
