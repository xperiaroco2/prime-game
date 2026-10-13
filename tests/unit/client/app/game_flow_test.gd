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


func test_the_crouch_plays_on_a_listed_map_and_never_in_the_lobby() -> void:
	# The crouch ADR's KE10, read as Match.crouch_plays: the base mode lists the House alone.
	var mode := load(MODE) as GameMode
	var house := "res://levels/house/house.tscn"
	var greybox := "res://levels/greybox/greybox.tscn"
	var model := ClientModel.new(mode)
	var welcome := WelcomeEvent.new(2, Vector3.ZERO, 1)
	welcome.phase = &"lobby"
	welcome.map = house
	model.fold(&"Welcome", welcome.to_dict())
	var welcomed := GameFlow.Session.WELCOMED
	# In the lobby the model's map is the next match's pick: no crouch, the House picked or not.
	for phase: StringName in [&"lobby", &"countdown"]:
		model.fold(&"PhaseChanged", {"phase": phase, "end_tick": -1})
		assert_bool(GameFlow.crouch_plays(welcomed, model, mode)).is_false()
	for phase: StringName in [&"loading", &"pregame", &"round", &"end"]:
		model.fold(&"PhaseChanged", {"phase": phase, "end_tick": -1})
		var plays := GameFlow.crouch_plays(welcomed, model, mode)
		assert_bool(plays).override_failure_message(str(phase)).is_true()
	# A map the list leaves out: no crouch in its round.
	model.map = greybox
	assert_bool(GameFlow.crouch_plays(welcomed, model, mode)).is_false()
	# An empty list is every map; no session, no mode, no PlayerRules: none.
	var every := mode.duplicate() as GameMode
	every.player_rules = FixtureModes.player_rules()
	assert_bool(every.player_rules.crouch_maps.is_empty()).is_true()
	assert_bool(GameFlow.crouch_plays(welcomed, model, every)).is_true()
	assert_bool(GameFlow.crouch_plays(GameFlow.Session.NONE, null, every)).is_false()
	assert_bool(GameFlow.crouch_plays(GameFlow.Session.CONNECTING, model, every)).is_false()
	assert_bool(GameFlow.crouch_plays(welcomed, model, null)).is_false()
	every.player_rules = null
	assert_bool(GameFlow.crouch_plays(welcomed, model, every)).is_false()


func test_seconds_left_round_up_and_never_go_below_zero() -> void:
	assert_int(GameFlow.seconds_left(-1, 10)).is_equal(-1)
	assert_int(GameFlow.seconds_left(100, -1)).is_equal(-1)
	assert_int(GameFlow.seconds_left(100, 0)).is_equal(5)
	assert_int(GameFlow.seconds_left(100, 99)).is_equal(1)
	assert_int(GameFlow.seconds_left(100, 100)).is_equal(0)
	assert_int(GameFlow.seconds_left(100, 140)).is_equal(0)
