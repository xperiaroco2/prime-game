extends GdUnitTestSuite
## Items that vanish when left lying (ARCHITECTURE §9.3, §9.4.5; the cooking ADR, CD6 (c), CE3,
## §7): VanishTicks removes an item of a kind with `vanish_seconds` exactly that long after it last
## came to rest (Items.lay: a spawn, a put-down, a leave's drop), with ItemVanished to everyone; a
## pick-up and a put-down start it over; a carried or locked item, or a kind without
## `vanish_seconds`, never; only in a phase that lists VanishTicks. Driven by FixtureVanishModes
## (a crumb of 60 s, 1200 ticks: a test's number).

const P1 := 1
const P2 := 2
const CRUMB_TICKS := FixtureVanishModes.CRUMB_TICKS


func test_an_item_lying_its_time_vanishes_at_that_tick_and_not_one_before() -> void:
	var game := FixtureItemModes.in_round(FixtureVanishModes.basic(), [P1, P2])
	var crumb := _only(game, &"crumb")
	var rested := crumb.rest_tick
	assert_int(rested).is_greater_equal(0)
	FixtureModes.run_ticks(game, rested + CRUMB_TICKS - 1 - game.ticked_through())
	assert_bool(game.state.items.has(crumb.id)).is_true()
	assert_array(FixtureVanishModes.vanished(game)).is_empty()
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.items.has(crumb.id)).is_false()
	assert_array(FixtureVanishModes.vanished(game)).is_equal([[rested + CRUMB_TICKS, crumb.id]])
	# Public: everyone is told, and the event names no player.
	for peer: int in [P1, P2]:
		var seen := game.view_of(peer).events_named(&"ItemVanished")
		assert_array(seen).has_size(1)
		assert_dict((seen[0] as ItemVanishedEvent).to_dict()).is_equal({"item": crumb.id})
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_pick_up_and_a_put_down_start_it_over() -> void:
	var game := FixtureItemModes.in_round(FixtureVanishModes.basic(), [P1, P2])
	var crumb := _only(game, &"crumb")
	FixtureModes.run_ticks(game, crumb.rest_tick + CRUMB_TICKS - 10 - game.ticked_through())
	FixtureItemModes.pick_up(game, P1, crumb)
	assert_int(crumb.where).is_equal(ItemState.Where.HAND)
	assert_int(crumb.rest_tick).is_equal(-1)
	# Carried past its time, and far past it: a carried item does not lie.
	FixtureModes.run_ticks(game, CRUMB_TICKS + 100)
	assert_bool(game.state.items.has(crumb.id)).is_true()
	FixtureItemModes.put_down(game, P1, Vector3(0, 0, -1))
	assert_int(crumb.where).is_equal(ItemState.Where.GROUND)
	var laid := crumb.rest_tick
	assert_int(laid).is_equal(game.ticked_through() + 1)
	FixtureModes.run_ticks(game, laid + CRUMB_TICKS - 1 - game.ticked_through())
	assert_bool(game.state.items.has(crumb.id)).is_true()
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureVanishModes.vanished(game)).is_equal([[laid + CRUMB_TICKS, crumb.id]])


func test_a_leave_s_drop_lies_from_the_leave() -> void:
	var mode := FixtureVanishModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.LEAVE)]))
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	var crumb := _only(game, &"crumb")
	FixtureItemModes.pick_up(game, P1, crumb)
	FixtureModes.run_ticks(game, 500)
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(crumb.where).is_equal(ItemState.Where.GROUND)
	var dropped := crumb.rest_tick
	assert_int(dropped).is_equal(game.ticked_through() + 1)
	FixtureModes.run_ticks(game, dropped + CRUMB_TICKS - game.ticked_through())
	assert_array(FixtureVanishModes.vanished(game)).is_equal([[dropped + CRUMB_TICKS, crumb.id]])


func test_a_locked_item_and_a_kind_without_vanish_seconds_never_vanish() -> void:
	var mode := FixtureVanishModes.basic(2)
	FixtureVanishModes.spawn_at_start(mode, &"package", FixtureVanishModes.SPOTS[2])
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	var crumbs := _all(game, &"crumb")
	var package := _only(game, &"package")
	assert_int(package.rest_tick).is_greater_equal(0)
	# Locked where it lies, as a delivered package (Items.lock): it no longer lies.
	Items.lock(crumbs[1])
	assert_int(crumbs[1].rest_tick).is_equal(-1)
	FixtureModes.run_ticks(game, CRUMB_TICKS * 3)
	assert_array(FixtureVanishModes.vanished(game)).is_equal(
		[[crumbs[0].rest_tick + CRUMB_TICKS, crumbs[0].id]]
	)
	assert_bool(game.state.items.has(crumbs[1].id)).is_true()
	assert_bool(game.state.items.has(package.id)).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_only_a_phase_that_lists_vanish_ticks_removes_one() -> void:
	var mode := FixtureVanishModes.basic()
	FixtureVanishModes.unlist(mode, &"round")
	mode.find_phase(&"end").tick_systems.append(VanishTicks.new())
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	var crumb := _only(game, &"crumb")
	FixtureModes.run_ticks(game, CRUMB_TICKS * 2)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.items.has(crumb.id)).is_true()
	# The round ends (the crew's win); End lists VanishTicks: the crumb, long due, goes at once.
	game.state.set_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	var ended_at := game.ticked_through()
	FixtureModes.run_ticks(game, 1)
	var gone := FixtureVanishModes.vanished(game)
	assert_array(gone).has_size(1)
	assert_int(gone[0][1] as int).is_equal(crumb.id)
	assert_int(gone[0][0] as int).is_between(ended_at, ended_at + 1)


func test_a_vanishing_kind_lying_without_a_rest_tick_is_a_rule_error() -> void:
	var game := FixtureItemModes.in_round(FixtureVanishModes.basic(0), [P1, P2])
	# Straight into the state, past Items.spawn: no rest tick.
	var stray := FixtureItemModes.lay(game, &"crumb", FixtureVanishModes.SPOTS[0])
	FixtureModes.run_ticks(game, 3)
	assert_bool(game.state.items.has(stray.id)).is_true()
	assert_str("\n".join(game.diagnostics)).contains("lies with no rest tick")
	# Logged once, not on every tick it lies there: the clock starts at the first.
	assert_int(stray.rest_tick).is_greater_equal(0)
	var logged := 0
	for line: String in game.diagnostics:
		if line.contains("lies with no rest tick"):
			logged += 1
	assert_int(logged).is_equal(1)


func test_a_thrown_item_lies_from_its_landing() -> void:
	var mode := FixtureThrowModes.with_throw(FixtureVanishModes.basic())
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	var crumb := _only(game, &"crumb")
	FixtureItemModes.pick_up(game, P1, crumb)
	FixtureThrowModes.throw(game, P1, Vector3(0, 1, -1))
	assert_int(crumb.rest_tick).is_equal(-1)
	FixtureModes.run_ticks(game, 70)
	assert_int(crumb.where).is_equal(ItemState.Where.GROUND)
	var landed := -1
	for emitted: EmittedEvent in game.emitted():
		if emitted.event is ItemPlacedEvent:
			landed = emitted.tick
	assert_int(crumb.rest_tick).is_equal(landed)


func _all(game: Match, kind_id: StringName) -> Array[ItemState]:
	var found: Array[ItemState] = []
	for id: int in game.state.items:
		if game.state.items[id].kind.id == kind_id:
			found.append(game.state.items[id])
	return found


func _only(game: Match, kind_id: StringName) -> ItemState:
	var found := _all(game, kind_id)
	assert_int(found.size()).is_equal(1)
	return found[0]
