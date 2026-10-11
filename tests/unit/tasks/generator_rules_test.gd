extends GdUnitTestSuite
## The Generator's rules (the Generator ADR's rules 2.2 to 2.6 and every edge case of its part 4;
## GE13 (a); ARCHITECTURE §9.5): a switch toggles, and one going off stops a running charge; the
## button stops a running charge, starts one when every active switch is on, and otherwise changes
## nothing; the charge gains a tick a Round tick and at its time is done, every subtask at once;
## nothing else stops or resets it. Driven by commands on a seeded match of FixtureGeneratorModes
## (the generator at (0, 0, 20), switch markers at x = 4, 8, 12 and 16; fixture values only).

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const NEEDED := FixtureGeneratorModes.NEEDED
const UNPLACED := 99


func test_a_switch_toggles_and_everyone_hears_it() -> void:
	var game := _round(2, [P1, P2])
	var switch := FixtureGeneratorModes.switch_of(game, 0)
	FixtureGeneratorModes.use(game, P1, switch)
	assert_array(FixtureGeneratorModes.state_of(game).on).is_equal([true, false])
	FixtureGeneratorModes.use(game, P1, switch, 1)
	assert_array(FixtureGeneratorModes.state_of(game).on).is_equal([false, false])
	for peer: int in [P1, P2]:
		assert_array(_dicts(game, peer, &"SwitchChanged")).is_equal(
			[{"station": switch, "on": true}, {"station": switch, "on": false}]
		)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_button_with_a_switch_off_changes_nothing_but_is_heard() -> void:
	var game := _round(2, [P1, P2])
	var button := FixtureGeneratorModes.button_of(game)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.switch_of(game, 0))
	FixtureGeneratorModes.use(game, P1, button, 1)
	FixtureModes.run_ticks(game, 10)
	assert_array(_dicts(game, P2, &"ButtonPressed")).is_equal([{"station": button}])
	assert_bool(FixtureGeneratorModes.state_of(game).running).is_false()
	assert_int(FixtureGeneratorModes.state_of(game).ticks).is_equal(0)
	assert_array(FixtureGeneratorModes.progress(game, P2)).has_size(1)


func test_the_charge_runs_to_its_time_and_the_task_is_done_only_then() -> void:
	var game := _round(2, [P1, P2])
	var task := FixtureGeneratorModes.task_of(game)
	_start(game, P1)
	FixtureModes.run_ticks(game, NEEDED - 1)
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_int(task_state.ticks).is_equal(NEEDED - 1)
	assert_bool(task_state.running).is_true()
	assert_int(task.state.done_count()).is_equal(0)
	assert_bool(Tasks.all_done(game.state)).is_false()
	assert_array(_dicts(game, P2, &"TaskState")).has_size(1)
	FixtureModes.run_ticks(game, 1)
	assert_int(task_state.ticks).is_equal(NEEDED)
	assert_bool(task_state.running).is_false()
	assert_bool(task.state.is_done()).is_true()
	assert_bool(Tasks.all_done(game.state)).is_true()
	for id: int in game.state.stations:
		assert_bool(game.state.stations[id].done).is_true()
	var states := _dicts(game, P2, &"TaskState")
	assert_dict(states[states.size() - 1]).is_equal(
		{"task": task.id, "type": &"generator", "done": 2, "total": 2}
	)
	var progress := FixtureGeneratorModes.progress(game, P2)
	assert_dict(progress[progress.size() - 1]).is_equal(
		FixtureGeneratorModes.sent(task_state.generator, NEEDED, false, game.ticked_through())
	)
	FixtureModes.run_ticks(game, 10)
	assert_array(FixtureGeneratorModes.progress(game, P2)).is_equal(progress)
	assert_array(Array(game.diagnostics)).is_empty()


func test_two_presses_in_one_tick_start_then_stop_and_a_later_press_stops_it() -> void:
	var game := _round(2, [P1, P2])
	var button := FixtureGeneratorModes.button_of(game)
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, button, 1)
	FixtureGeneratorModes.use(game, P2, button, 1)
	FixtureModes.run_ticks(game, 3)
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_bool(task_state.running).is_false()
	assert_int(task_state.ticks).is_equal(0)
	assert_array(_dicts(game, P1, &"ButtonPressed")).has_size(2)
	FixtureGeneratorModes.use(game, P1, button, 2)
	FixtureModes.run_ticks(game, 3)
	FixtureGeneratorModes.use(game, P2, button, 2)
	FixtureModes.run_ticks(game, 5)
	assert_bool(task_state.running).is_false()
	assert_int(task_state.ticks).is_equal(3)


func test_a_switch_turned_off_stops_the_charge_and_turned_on_again_does_not_start_it() -> void:
	var game := _round(2, [P1, P2])
	_start(game, P1)
	FixtureModes.run_ticks(game, 4)
	var switch := FixtureGeneratorModes.switch_of(game, 1)
	FixtureGeneratorModes.use(game, P2, switch)
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_bool(task_state.running).is_false()
	FixtureModes.run_ticks(game, 5)
	assert_int(task_state.ticks).is_equal(4)
	FixtureGeneratorModes.use(game, P2, switch, 1)
	FixtureModes.run_ticks(game, 5)
	assert_bool(task_state.running).is_false()
	assert_int(task_state.ticks).is_equal(4)


func test_a_switch_off_before_the_button_in_one_tick_keeps_the_charge_from_starting() -> void:
	var game := _round(2, [P1, P2])
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P2, FixtureGeneratorModes.switch_of(game, 0))
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	FixtureModes.run_ticks(game, 5)
	assert_bool(FixtureGeneratorModes.state_of(game).running).is_false()
	assert_int(FixtureGeneratorModes.state_of(game).ticks).is_equal(0)


func test_the_button_before_a_switch_off_in_one_tick_starts_and_the_switch_stops_it() -> void:
	var game := _round(2, [P1, P2])
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	assert_bool(FixtureGeneratorModes.state_of(game).running).is_true()
	FixtureGeneratorModes.use(game, P2, FixtureGeneratorModes.switch_of(game, 0))
	FixtureModes.run_ticks(game, 5)
	assert_bool(FixtureGeneratorModes.state_of(game).running).is_false()
	assert_int(FixtureGeneratorModes.state_of(game).ticks).is_equal(0)


func test_a_switch_off_in_the_tick_the_charge_would_complete_stops_it_one_short() -> void:
	var game := _round(2, [P1, P2])
	_start(game, P1)
	FixtureModes.run_ticks(game, NEEDED - 1)
	FixtureGeneratorModes.use(game, P2, FixtureGeneratorModes.switch_of(game, 0))
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureGeneratorModes.state_of(game).ticks).is_equal(NEEDED - 1)
	assert_bool(FixtureGeneratorModes.task_of(game).state.is_done()).is_false()


func test_the_charge_done_in_the_clocks_last_tick_wins_for_the_crew() -> void:
	var game := FixtureGeneratorModes.in_round(FixtureGeneratorModes.winning(2), [P1, P2])
	_start(game, P1)
	FixtureModes.run_ticks(game, NEEDED - 1)
	game.state.clock_ticks_left = 1
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.clock_ended).is_true()
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureWinModes.ended(game, P2)).is_equal([&"crew"])


func test_round_end_while_charging_stops_it_and_keeps_its_ticks() -> void:
	var game := FixtureGeneratorModes.in_round(FixtureGeneratorModes.winning(2), [P1, P2])
	_start(game, P1)
	FixtureModes.run_ticks(game, 5)
	game.state.clock_ticks_left = 1
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureWinModes.ended(game, P2)).is_equal([&"dissidents"])
	var sent := FixtureGeneratorModes.progress(game, P1).size()
	FixtureModes.run_ticks(game, 30)
	assert_int(FixtureGeneratorModes.state_of(game).ticks).is_equal(6)
	assert_int(FixtureGeneratorModes.progress(game, P1).size()).is_equal(sent)


func test_a_knockdown_a_death_or_a_leave_changes_nothing() -> void:
	var mode := FixtureGeneratorModes.basic(2)
	FixtureGeneratorModes.type_of(mode).seconds = 600.0
	var game := FixtureGeneratorModes.in_round(mode, [P1, P2, P3])
	FixtureGeneratorModes.use(game, P3, FixtureGeneratorModes.switch_of(game, 0))
	FixtureGeneratorModes.use(game, P2, FixtureGeneratorModes.switch_of(game, 1))
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game))
	var from := game.ticked_through()
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureWinModes.kill(game, P2, P3)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.DEAD)
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_array(task_state.on).is_equal([true, true])
	assert_bool(task_state.running).is_true()
	assert_int(task_state.ticks).is_equal(game.ticked_through() - from)
	FixtureModes.run_ticks(game, 10)
	assert_int(task_state.ticks).is_equal(game.ticked_through() - from)


func test_a_downed_player_is_not_accepted() -> void:
	var game := _round(2, [P1, P2])
	game.state.player(P1).life = PlayerState.Life.DOWNED
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.switch_of(game, 0))
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_array(_dicts(game, P2, &"SwitchChanged")).is_empty()


func test_a_raisers_press_applies_and_stops_the_raise() -> void:
	var game := _round(2, [P1, P2, P3])
	var switch := FixtureGeneratorModes.switch_of(game, 0)
	var at := game.state.stations[switch].position
	FixtureCombatModes.arm(game, P1, at + Vector3(1, 0, -1))
	FixtureItemModes.stand(game, P2, at + Vector3(1, 0, 0))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureItemModes.stand(game, P3, at)
	FixtureCombatModes.raise(game, P3, P2)
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	FixtureStationModes.interact(game, P3, switch, 1)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(FixtureCombatModes.received(game, P1, &"RaiseStopped")).has_size(1)
	assert_array(_dicts(game, P1, &"SwitchChanged")).is_equal([{"station": switch, "on": true}])


func test_a_knife_holder_toggles_the_switch_and_strikes_nobody() -> void:
	var game := _round(2, [P1, P2])
	var switch := FixtureGeneratorModes.switch_of(game, 0)
	var at := game.state.stations[switch].position
	FixtureCombatModes.arm(game, P1, at + FixtureGeneratorModes.SHORT)
	FixtureItemModes.stand(game, P2, at + Vector3(0, 0, 0.4))
	FixtureStationModes.interact(game, P1, switch)
	assert_array(_dicts(game, P2, &"SwitchChanged")).is_equal([{"station": switch, "on": true}])
	assert_float(FixtureCombatModes.health(game, P2)).is_equal(100.0)


func test_a_package_carrier_is_two_handed() -> void:
	var game := _round(2, [P1, P2])
	var switch := FixtureGeneratorModes.switch_of(game, 0)
	var at := game.state.stations[switch].position + FixtureGeneratorModes.SHORT
	FixtureItemModes.stand(game, P1, at)
	FixtureItemModes.pick_up(game, P1, FixtureItemModes.lay(game, &"package", at))
	assert_int(game.state.player(P1).held_item).is_not_equal(-1)
	FixtureStationModes.interact(game, P1, switch, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"two_handed"])
	assert_array(_dicts(game, P2, &"SwitchChanged")).is_empty()


func test_a_player_behind_a_wall_within_the_radius_is_blocked() -> void:
	var world := FlatWorldQuery.new()
	var game := FixtureGeneratorModes.in_round(
		FixtureGeneratorModes.basic(2), [P1, P2], {}, {}, 7, {}, world
	)
	var button := FixtureGeneratorModes.button_of(game)
	var at := game.state.stations[button].position
	world.add_wall(AABB(at + Vector3(-1, 0, -0.3), Vector3(2, 3, 0.1)))
	FixtureGeneratorModes.use(game, P1, button)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"blocked"])
	assert_array(_dicts(game, P2, &"ButtonPressed")).is_empty()


func test_an_unknown_station_or_a_fixed_switch_is_nothing_to_do_with_no_event() -> void:
	var game := _round(2, [P1, P2])
	var fixed := _fixed_spot(game)
	FixtureItemModes.stand(game, P1, fixed + FixtureGeneratorModes.SHORT)
	FixtureStationModes.interact(game, P1, UNPLACED)
	FixtureStationModes.interact(game, P1, game.state.stations.size() + 1, 1)
	FixtureStationModes.interact(game, P1, -1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"nothing_to_do", &"nothing_to_do", &"nothing_to_do"]
	)
	for name: StringName in [&"SwitchChanged", &"ButtonPressed"]:
		assert_array(_dicts(game, P2, name)).is_empty()
	assert_array(FixtureGeneratorModes.state_of(game).on).is_equal([false, false])


func test_every_use_after_the_charge_is_done_is_unavailable() -> void:
	var game := _round(2, [P1, P2])
	_start(game, P1)
	FixtureModes.run_ticks(game, NEEDED)
	assert_bool(FixtureGeneratorModes.state_of(game).done).is_true()
	var pressed := _dicts(game, P2, &"ButtonPressed").size()
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 5)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.switch_of(game, 0), 6)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable", &"unavailable"])
	assert_array(_dicts(game, P2, &"ButtonPressed")).has_size(pressed)
	assert_array(_dicts(game, P2, &"SwitchChanged")).has_size(2)
	assert_array(FixtureGeneratorModes.state_of(game).on).is_equal([true, true])


func test_100_presses_in_100_ticks_give_at_most_21_progress_events() -> void:
	# A client that sends no claim twin gets every press accepted (the reliable-intent bucket, not
	# Match, bounds it); the window bounds the progress events.
	var mode := FixtureGeneratorModes.basic(2)
	FixtureGeneratorModes.type_of(mode).seconds = 600.0
	var game := FixtureGeneratorModes.in_round(mode, [P1, P2])
	FixtureGeneratorModes.switch_all_on(game, P1)
	var before := FixtureGeneratorModes.progress(game, P2).size()
	var button := FixtureGeneratorModes.button_of(game)
	for i in 100:
		FixtureGeneratorModes.use(game, P1, button, i)
		FixtureModes.run_ticks(game, 1)
	assert_array(_dicts(game, P2, &"ButtonPressed")).has_size(100)
	var sent := FixtureGeneratorModes.progress(game, P2).size() - before
	assert_int(sent).is_greater(0)
	assert_int(sent).is_less_equal(21)


## A round of the generator fixture mode with `active` switches, `peers` joined.
func _round(active: int, peers: Array[int]) -> Match:
	return FixtureGeneratorModes.in_round(FixtureGeneratorModes.basic(active), peers)


## `peer` turns every switch on and presses the button: the charge runs from the next tick.
func _start(game: Match, peer: int) -> void:
	FixtureGeneratorModes.switch_all_on(game, peer)
	FixtureGeneratorModes.use(game, peer, FixtureGeneratorModes.button_of(game), 1)
	assert_bool(FixtureGeneratorModes.state_of(game).running).is_true()


## The `name` events `peer` received, as plain data, in order.
func _dicts(game: Match, peer: int, name: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(name):
		found.append(event.to_dict())
	return found


## A switch marker the deal left without a station: a fixed switch.
func _fixed_spot(game: Match) -> Vector3:
	var placed: Array[Vector3] = []
	for id: int in game.state.stations:
		placed.append(game.state.stations[id].position)
	for spot: Vector3 in FixtureGeneratorModes.SWITCH_SPOTS:
		if not placed.has(spot):
			return spot
	return Vector3.INF
