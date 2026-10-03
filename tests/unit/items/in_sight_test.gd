extends GdUnitTestSuite
## InSight when the rule's target item is not there (ARCHITECTURE §9.4): it reads the item through
## Items.target_of. It stands alone on its rule here (the base mode puts ItemOnGround before it,
## which refuses first), so its own guard decides: an item that does not exist is out of sight,
## never in it. The refusal goes to the sender alone and the rule's effect does not run. The
## target players' conditions: tests/unit/life/absent_target_test.gd.

const P1 := 1
const P2 := 2
const NO_ITEM := 999
const RAN := "ran"


func test_in_sight_refuses_an_item_that_is_not_there() -> void:
	var mode := FixtureItemModes.basic()
	var effects: Array[RuleEffect] = [FixtureNote.of(RAN)]
	var conditions: Array[Condition] = [InSight.new()]
	_replace_rule(mode, Intents.PICK_UP, conditions, effects)
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureModes.send(game, Intents.PICK_UP, P1, {"item": NO_ITEM})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([InSight.BLOCKED])
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_array(FixtureModes.notes(game)).not_contains([RAN])
	assert_array(Array(game.diagnostics)).is_empty()
	# The same rule passes for an item that lies in sight.
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P1, tool)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([InSight.BLOCKED])
	assert_array(FixtureModes.notes(game)).contains([RAN])


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
