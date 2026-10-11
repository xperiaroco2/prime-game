extends GdUnitTestSuite
## The replay of reused item ids (ARCHITECTURE §3.3, §9.4.5; the cooking ADR, CE3, §7, C10): a
## short match whose id counter starts near the wire's limit (FixtureSkipItemIds) frees ids out of
## id order (items of three kinds that vanish after 3, 2 and 1 s), reuses them (three new items at
## one Use), and has those three vanish in one tick, in ascending id, although the item table holds
## them in the order they were reused; Match.replay of its command log emits the same events to the
## same recipients, with nothing in its diagnostics. So an order taken from the item table instead
## of the queue or the ascending ids fails here. The numbers are a test's, not a decision.

const P1 := 1
const P2 := 2
const LIMIT := MatchState.MAX_ITEM_ID
const SPOTS := FixtureVanishModes.SPOTS


func test_reused_ids_vanish_in_ascending_order_and_replay() -> void:
	var game := FixtureItemModes.in_round(_mode(), [P1, P2])
	assert_str(game.phase_id()).is_equal("round")
	assert_array(game.state.items.keys()).is_equal([LIMIT - 2, LIMIT - 1, LIMIT])
	var rested := game.state.items[LIMIT].rest_tick
	FixtureModes.run_ticks(game, rested + Ticks.from_seconds(3) - game.ticked_through())
	# Freed out of id order: the 1 s kind first, the 3 s kind last.
	assert_array(_ids(FixtureVanishModes.vanished(game))).is_equal([LIMIT, LIMIT - 1, LIMIT - 2])
	assert_bool(game.state.items.is_empty()).is_true()
	FixtureModes.send(game, Intents.USE, P1)
	# Each reuse takes the id freed longest ago.
	assert_array(game.state.items.keys()).is_equal([LIMIT, LIMIT - 1, LIMIT - 2])
	var used := game.ticked_through() + 1
	FixtureModes.run_ticks(game, used + Ticks.from_seconds(3) - game.ticked_through())
	var gone := FixtureVanishModes.vanished(game)
	var at := used + Ticks.from_seconds(3)
	var expected := [[at, LIMIT - 2], [at, LIMIT - 1], [at, LIMIT]]
	assert_array(gone.slice(3)).is_equal(expected)
	assert_array(Array(game.diagnostics)).is_empty()
	var replayed := Match.replay(game.command_log, _mode())
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))


## FixtureVanishModes.basic(0) with kinds that vanish after 3, 2 and 1 s, one of each spawned when
## the round starts at the ids LIMIT - 2 to LIMIT, and a Use of the mode that spawns three of the
## 3 s kind.
func _mode() -> GameMode:
	var mode := FixtureVanishModes.basic(0)
	var kinds: Array[StringName] = [&"slow", &"mid", &"fast"]
	for i in kinds.size():
		mode.item_kinds.append(FixtureVanishModes.vanishing(kinds[i], 3 - i))
	var skip := FixtureSkipItemIds.new()
	skip.next = LIMIT - 2
	mode.find_transition(&"lobby", &"all_ready").actions.append(skip)
	for i in kinds.size():
		FixtureVanishModes.spawn_at_start(mode, kinds[i], SPOTS[i])
	var spawns: Array[RuleEffect] = []
	for at: Vector3 in SPOTS:
		spawns.append(FixtureVanishModes.spawn(mode, &"slow", at))
	mode.actions.append(FixtureModes.rule(Intents.USE, [], spawns))
	return mode


func _ids(vanished: Array[Array]) -> Array[int]:
	var found: Array[int] = []
	for each: Array in vanished:
		found.append(each[1] as int)
	return found
