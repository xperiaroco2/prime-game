extends GdUnitTestSuite
## A throw replays from its command log (ARCHITECTURE §3.3, §7.1.16; the throwing ADR, TE7; left
## from PR #686's review, #646): the pick-up, the Throw and every tick of the flight, whose sweeps
## and floor answers the log holds, give the same events and the same rest when replayed. Driven
## by FixtureThrowModes.basic() (a test's numbers, not a decision) with a package spawned by the
## row into the round, next to P1's round spot (FixtureModes.layouts: P1 at (10, 0, 5)).

const P1 := 1
const P2 := 2
const SPAWN := Vector3(11, 0, 5)


func test_a_throw_replays_from_its_command_log() -> void:
	var game := FixtureItemModes.in_round(_mode(), [P1, P2])
	assert_str(game.phase_id()).is_equal("round")
	var package := _only_item(game)
	FixtureItemModes.pick_up(game, P1, package)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	FixtureThrowModes.throw(game, P1, Vector3(0, 1, -1))
	assert_int(package.where).is_equal(ItemState.Where.FLYING)
	FixtureModes.run_ticks(game, 70)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_array(Array(game.diagnostics)).is_empty()
	var replayed := Match.replay(game.command_log, _mode())
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))
	var again := _only_item(replayed)
	assert_int(again.where).is_equal(ItemState.Where.GROUND)
	assert_vector(again.position).is_equal(package.position)


## FixtureThrowModes.basic() with a package spawned at SPAWN when the round starts.
func _mode() -> GameMode:
	var mode := FixtureThrowModes.basic()
	var spawn := FixtureSpawnItem.new()
	spawn.kind = mode.find_item_kind(&"package")
	spawn.at = SPAWN
	mode.find_transition(&"lobby", &"all_ready").actions.append(spawn)
	return mode


func _only_item(game: Match) -> ItemState:
	assert_int(game.state.items.size()).is_equal(1)
	for id: int in game.state.items:
		return game.state.items[id]
	return null
