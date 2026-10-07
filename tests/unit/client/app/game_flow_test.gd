extends GdUnitTestSuite
## The game's flow (client/app/game_flow.gd, ARCHITECTURE §4.7): the screen and the level for each
## state of the session and each phase of the base mode, read from the client's own mode.

const MODE := "res://content/modes/base_mode.tres"

const S := GameFlow.Screen
const L := PhaseSpec.Level


func test_no_session_is_the_menu_and_no_welcome_is_connecting() -> void:
	var model := ClientModel.new(load(MODE) as GameMode)
	assert_int(GameFlow.screen(GameFlow.Session.NONE, null)).is_equal(S.MENU)
	assert_int(GameFlow.level(GameFlow.Session.NONE, model)).is_equal(L.NONE)
	assert_int(GameFlow.screen(GameFlow.Session.CONNECTING, model)).is_equal(S.CONNECTING)
	assert_int(GameFlow.level(GameFlow.Session.CONNECTING, model)).is_equal(L.NONE)


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


func test_a_match_that_ended_shows_the_end_screen() -> void:
	var model := ClientModel.new(load(MODE) as GameMode)
	var welcome := WelcomeEvent.new(2, Vector3.ZERO, 1)
	welcome.phase = &"round"
	model.fold(&"Welcome", welcome.to_dict())
	assert_int(GameFlow.screen(GameFlow.Session.WELCOMED, model)).is_equal(S.ROUND)
	model.fold(&"MatchEnded", {"side": &"crew"})
	assert_int(GameFlow.screen(GameFlow.Session.WELCOMED, model)).is_equal(S.END)


func test_the_player_stands_still_outside_the_lobby_and_the_round() -> void:
	for screen: S in [S.MENU, S.CONNECTING, S.LOADING, S.END]:
		assert_bool(GameFlow.frozen(screen)).is_true()
	for screen: S in [S.LOBBY, S.ROUND]:
		assert_bool(GameFlow.frozen(screen)).is_false()


func test_the_lobby_and_the_round_capture_the_mouse_loading_keeps_it_the_rest_free_it() -> void:
	# #169: the lobby is walked like the round; its Ready and settings are in the Esc menu.
	# #517: Loading freed it, so the round started with the cursor showing until a click.
	for screen: S in [S.MENU, S.CONNECTING, S.END]:
		assert_int(GameFlow.pointer_on(screen)).is_equal(GameFlow.Pointer.FREE)
	for screen: S in [S.LOBBY, S.ROUND]:
		assert_int(GameFlow.pointer_on(screen)).is_equal(GameFlow.Pointer.CAPTURE)
	assert_int(GameFlow.pointer_on(S.LOADING)).is_equal(GameFlow.Pointer.KEEP)


func test_seconds_left_round_up_and_never_go_below_zero() -> void:
	assert_int(GameFlow.seconds_left(-1, 10)).is_equal(-1)
	assert_int(GameFlow.seconds_left(100, -1)).is_equal(-1)
	assert_int(GameFlow.seconds_left(100, 0)).is_equal(5)
	assert_int(GameFlow.seconds_left(100, 99)).is_equal(1)
	assert_int(GameFlow.seconds_left(100, 100)).is_equal(0)
	assert_int(GameFlow.seconds_left(100, 140)).is_equal(0)
