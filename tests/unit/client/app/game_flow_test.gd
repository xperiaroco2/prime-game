extends GdUnitTestSuite
## The game's flow (client/app/game_flow.gd, ARCHITECTURE §4.7): the screen and the level for each
## state of the session and each phase of the base mode, read from the client's own mode.

const MODE := "res://content/modes/base_mode.tres"
const TUTORIAL := "res://content/modes/tutorial_mode.tres"

const S := GameFlow.Screen
const L := PhaseSpec.Level


func test_no_session_is_the_menu_and_no_welcome_is_connecting() -> void:
	var model := ClientModel.new(load(MODE) as GameMode)
	assert_int(GameFlow.screen(GameFlow.Session.NONE, null)).is_equal(S.MENU)
	assert_int(GameFlow.level(GameFlow.Session.NONE, model)).is_equal(L.NONE)
	assert_int(GameFlow.screen(GameFlow.Session.CONNECTING, model)).is_equal(S.CONNECTING)
	assert_int(GameFlow.level(GameFlow.Session.CONNECTING, model)).is_equal(L.NONE)
	# #494: a failed session shows its failure until Back, with no level.
	assert_int(GameFlow.screen(GameFlow.Session.FAILED, null)).is_equal(S.FAILURE)
	assert_int(GameFlow.level(GameFlow.Session.FAILED, model)).is_equal(L.NONE)


func test_each_phase_of_the_base_mode_has_its_screen_and_level() -> void:
	var model := ClientModel.new(load(MODE) as GameMode)
	var welcome := WelcomeEvent.new(2, Vector3.ZERO, 1)
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	var welcomed := GameFlow.Session.WELCOMED
	# [phase, screen, level]
	var flow: Array[Array] = [
		[&"lobby", S.LOBBY, L.LOBBY],
		[&"countdown", S.LOBBY, L.LOBBY],
		[&"loading", S.LOADING, L.MAP],
		[&"pregame", S.PREGAME, L.MAP],
		[&"round", S.ROUND, L.MAP],
		[&"end", S.END, L.MAP],
		[&"lobby", S.LOBBY, L.LOBBY],
	]
	for step: Array in flow:
		model.fold(&"PhaseChanged", {"phase": step[0], "end_tick": -1})
		var label := str(step[0])
		assert_int(GameFlow.screen(welcomed, model)).override_failure_message(label).is_equal(
			step[1] as int
		)
		assert_int(GameFlow.level(welcomed, model)).override_failure_message(label).is_equal(
			step[2] as int
		)


func test_the_tutorial_waits_on_the_loading_screen_until_its_lessons() -> void:
	# #601: gather has no level (E72), so it shows Loading, frozen, the mouse kept, never the round.
	var model := ClientModel.new(load(TUTORIAL) as GameMode)
	var welcome := WelcomeEvent.new(1, Vector3.ZERO, 1)
	welcome.phase = &"gather"
	model.fold(&"Welcome", welcome.to_dict())
	var welcomed := GameFlow.Session.WELCOMED
	# [phase, screen, level]
	var flow: Array[Array] = [
		[&"gather", S.LOADING, L.NONE],
		[&"loading", S.LOADING, L.MAP],
		[&"lessons", S.ROUND, L.MAP],
		[&"raise_stage", S.ROUND, L.MAP],
		[&"death_stage", S.ROUND, L.MAP],
	]
	for step: Array in flow:
		if step[0] != &"gather":
			model.fold(&"PhaseChanged", {"phase": step[0], "end_tick": -1})
		var label := str(step[0])
		assert_int(GameFlow.screen(welcomed, model)).override_failure_message(label).is_equal(
			step[1] as int
		)
		assert_int(GameFlow.level(welcomed, model)).override_failure_message(label).is_equal(
			step[2] as int
		)
	assert_bool(GameFlow.frozen(S.LOADING)).is_true()
	assert_int(GameFlow.pointer_on(S.LOADING)).is_equal(GameFlow.Pointer.KEEP)


func test_a_match_that_ended_shows_the_end_screen() -> void:
	var model := ClientModel.new(load(MODE) as GameMode)
	var welcome := WelcomeEvent.new(2, Vector3.ZERO, 1)
	welcome.phase = &"round"
	model.fold(&"Welcome", welcome.to_dict())
	assert_int(GameFlow.screen(GameFlow.Session.WELCOMED, model)).is_equal(S.ROUND)
	model.fold(&"MatchEnded", {"side": &"crew"})
	assert_int(GameFlow.screen(GameFlow.Session.WELCOMED, model)).is_equal(S.END)


func test_the_player_stands_still_outside_the_lobby_and_the_round() -> void:
	for screen: S in [S.MENU, S.CONNECTING, S.LOADING, S.PREGAME, S.END, S.FAILURE]:
		assert_bool(GameFlow.frozen(screen)).is_true()
	for screen: S in [S.LOBBY, S.ROUND]:
		assert_bool(GameFlow.frozen(screen)).is_false()


func test_the_lobby_and_the_round_capture_the_mouse_loading_keeps_it_the_rest_free_it() -> void:
	# #169: the lobby is walked like the round; its Ready and settings are in the Esc menu.
	# #517: Loading freed it, so the round started with the cursor showing until a click; the
	# pregame (#213), also between the lobby and the round, keeps it too.
	for screen: S in [S.MENU, S.CONNECTING, S.END, S.FAILURE]:
		assert_int(GameFlow.pointer_on(screen)).is_equal(GameFlow.Pointer.FREE)
	for screen: S in [S.LOBBY, S.ROUND]:
		assert_int(GameFlow.pointer_on(screen)).is_equal(GameFlow.Pointer.CAPTURE)
	for screen: S in [S.LOADING, S.PREGAME]:
		assert_int(GameFlow.pointer_on(screen)).is_equal(GameFlow.Pointer.KEEP)


func test_the_pregame_screen_follows_the_phase_class_not_the_id() -> void:
	# The screen comes from the own copy's PhaseSpec (its class), never from a phase's name.
	var mode := (load(MODE) as GameMode).duplicate(true) as GameMode
	mode.find_phase(&"pregame").id = &"intro"
	var model := ClientModel.new(mode)
	var welcome := WelcomeEvent.new(2, Vector3.ZERO, 1)
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	model.fold(&"PhaseChanged", {"phase": &"intro", "end_tick": -1})
	assert_int(GameFlow.screen(GameFlow.Session.WELCOMED, model)).is_equal(S.PREGAME)


func test_seconds_left_round_up_and_never_go_below_zero() -> void:
	assert_int(GameFlow.seconds_left(-1, 10)).is_equal(-1)
	assert_int(GameFlow.seconds_left(100, -1)).is_equal(-1)
	assert_int(GameFlow.seconds_left(100, 0)).is_equal(5)
	assert_int(GameFlow.seconds_left(100, 99)).is_equal(1)
	assert_int(GameFlow.seconds_left(100, 100)).is_equal(0)
	assert_int(GameFlow.seconds_left(100, 140)).is_equal(0)


func test_in_round_holds_only_while_the_round_plays() -> void:
	assert_bool(GameFlow.in_round(null)).is_false()
	var model := ClientModel.new(load(MODE) as GameMode)
	var welcome := WelcomeEvent.new(2, Vector3.ZERO, 1)
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	assert_bool(GameFlow.in_round(model)).is_false()
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": 5000})
	assert_bool(GameFlow.in_round(model)).is_true()
	# A win ends the round at once, while the clock's end_tick still lies ahead.
	model.fold(&"MatchEnded", {"side": &"crew"})
	assert_bool(GameFlow.in_round(model)).is_false()


func test_the_clock_stops_when_every_task_is_done() -> void:
	# The round lingers on a stopped clock once the win is decided at the engine's last stage
	# (GDD §3, #1502): the clock holds at the tick of the bar's last ZoneProgress.
	var model := ClientModel.new(load(MODE) as GameMode)
	model.stations[5] = ClientModel.Station.new()
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": 2000})
	model.fold(&"TaskProgress", {"done": 0, "total": 1})
	model.fold(&"ZoneProgress", _bar(5, 300, 600, 400))
	assert_int(GameFlow.clock_left(model, 400)).is_equal(80)
	model.fold(&"ZoneProgress", _bar(5, 600, 600, 600))
	assert_int(GameFlow.clock_left(model, 620)).is_equal(69)
	model.fold(&"TaskProgress", {"done": 1, "total": 1})
	assert_int(GameFlow.clock_left(model, 620)).is_equal(70)
	assert_int(GameFlow.clock_left(model, 680)).is_equal(70)
	# Before the stop the clock is as it was.
	assert_int(GameFlow.clock_left(model, 500)).is_equal(75)
	# The next phase's own countdown runs.
	model.fold(&"PhaseChanged", {"phase": &"end", "end_tick": 740})
	model.fold(&"TaskProgress", {"done": 0, "total": 0})
	assert_int(GameFlow.clock_left(model, 680)).is_equal(3)


func test_no_tasks_never_stop_the_clock() -> void:
	var model := ClientModel.new(load(MODE) as GameMode)
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": 2000})
	model.fold(&"TaskProgress", {"done": 0, "total": 0})
	assert_int(GameFlow.clock_left(model, 1000)).is_equal(50)


func _bar(station: int, ticks: int, needed: int, at: int) -> Dictionary:
	return {"station": station, "ticks": ticks, "needed": needed, "counting": false, "tick": at}
