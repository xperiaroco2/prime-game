extends GdUnitTestSuite
## The Generator's progress events (the Generator ADR's GE7 to GE9; ZE4's window; ARCHITECTURE
## §4.2): the charge goes out as ZoneProgress for the generator's station, at most one start or stop
## per WINDOW_TICKS window; a held one goes out at the window's end with that tick's state, even
## when the charge has stopped, and a round ending inside the window drops it; a start or stop of a
## command is counted through the tick before (its tick's gain is still to come), so a client's
## extrapolation (ticks + now - tick) matches the host; the done event goes out in its own tick,
## before the task's TaskState; SwitchChanged and ButtonPressed come before the progress event of
## the same command. Driven on FixtureGeneratorModes (two active switches; fixture values only).

const P1 := 1
const P2 := 2
const NEEDED := FixtureGeneratorModes.NEEDED
const WINDOW := Generator.WINDOW_TICKS


func test_a_start_goes_out_counted_through_the_tick_before() -> void:
	var game := _round()
	FixtureGeneratorModes.switch_all_on(game, P1)
	var at := game.ticked_through() + 1
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	var progress := FixtureGeneratorModes.progress(game, P2)
	assert_array(progress).has_size(2)
	assert_dict(progress[1]).is_equal(FixtureGeneratorModes.sent(_button(game), 0, true, at - 1))


func test_a_clients_extrapolation_matches_the_host() -> void:
	var game := _round()
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	var start: Dictionary = FixtureGeneratorModes.progress(game, P2)[1]
	for k: int in [1, 4, 9]:
		FixtureModes.run_ticks(game, k)
		var now := game.ticked_through()
		var guessed: int = start["ticks"] + now - (start["tick"] as int)
		assert_int(guessed).is_equal(FixtureGeneratorModes.state_of(game).ticks)


func test_a_stop_inside_the_window_goes_out_at_its_end_though_the_charge_stopped() -> void:
	var game := _round()
	FixtureGeneratorModes.switch_all_on(game, P1)
	var start := game.ticked_through() + 1
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	FixtureModes.run_ticks(game, 2)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 2)
	assert_bool(FixtureGeneratorModes.state_of(game).running).is_false()
	assert_array(FixtureGeneratorModes.progress(game, P2)).has_size(2)
	FixtureModes.run_ticks(game, WINDOW - 2)
	assert_array(FixtureGeneratorModes.progress(game, P2)).has_size(2)
	FixtureModes.run_ticks(game, 1)
	var progress := FixtureGeneratorModes.progress(game, P2)
	assert_array(progress).has_size(3)
	assert_dict(progress[2]).is_equal(
		FixtureGeneratorModes.sent(_button(game), 2, false, start + WINDOW - 1)
	)
	FixtureModes.run_ticks(game, 10)
	assert_array(FixtureGeneratorModes.progress(game, P2)).has_size(3)


func test_a_stop_after_the_window_goes_out_at_once_after_its_switch_changed() -> void:
	var game := _round()
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	FixtureModes.run_ticks(game, WINDOW)
	var mark := game.view_of(P2).events.size()
	var at := game.ticked_through() + 1
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.switch_of(game, 0), 2)
	var names: Array[StringName] = []
	for event: MatchEvent in game.view_of(P2).events.slice(mark):
		names.append(event.event_name())
	assert_array(names).is_equal([&"SwitchChanged", &"ZoneProgress"])
	assert_dict(FixtureGeneratorModes.progress(game, P2)[2]).is_equal(
		FixtureGeneratorModes.sent(_button(game), WINDOW, false, at - 1)
	)


func test_the_button_comes_before_its_progress_event() -> void:
	var game := _round()
	FixtureGeneratorModes.switch_all_on(game, P1)
	var mark := game.view_of(P2).events.size()
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	var names: Array[StringName] = []
	for event: MatchEvent in game.view_of(P2).events.slice(mark):
		names.append(event.event_name())
	assert_array(names).is_equal([&"ButtonPressed", &"ZoneProgress"])


func test_done_goes_out_in_its_tick_before_the_tasks_state() -> void:
	var game := _round()
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	FixtureModes.run_ticks(game, NEEDED - 1)
	var mark := game.view_of(P2).events.size()
	FixtureModes.run_ticks(game, 1)
	var names: Array[StringName] = []
	for event: MatchEvent in game.view_of(P2).events.slice(mark):
		if event.event_name() in [&"ZoneProgress", &"TaskState", &"TaskProgress"]:
			names.append(event.event_name())
	assert_str(names[0]).is_equal("ZoneProgress")
	assert_bool(names.has(&"TaskState")).is_true()
	assert_bool(names.has(&"TaskProgress")).is_true()
	assert_int(names.count(&"ZoneProgress")).is_equal(1)
	var progress := FixtureGeneratorModes.progress(game, P2)
	assert_dict(progress[progress.size() - 1]).is_equal(
		FixtureGeneratorModes.sent(_button(game), NEEDED, false, game.ticked_through())
	)


func test_a_round_ending_inside_the_window_drops_the_held_event() -> void:
	var game := FixtureGeneratorModes.in_round(FixtureGeneratorModes.winning(2), [P1, P2])
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 1)
	FixtureModes.run_ticks(game, 1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game), 2)
	assert_bool(FixtureGeneratorModes.state_of(game).pending).is_true()
	game.state.clock_ticks_left = 1
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.run_ticks(game, 20)
	assert_array(FixtureGeneratorModes.progress(game, P2)).has_size(2)


func _round() -> Match:
	return FixtureGeneratorModes.in_round(FixtureGeneratorModes.basic(2), [P1, P2])


func _button(game: Match) -> int:
	return FixtureGeneratorModes.button_of(game)
