extends GdUnitTestSuite
## The lobby's name (ARCHITECTURE §3.5, §4.1, #214): the host sets it in the Lobby with
## ChangeSettings's optional `lobby_name`, LobbyName cleans it (20 characters, no invisible
## characters, blank edges trimmed), all or nothing with the rest of the change; every player sees
## it in SettingsChanged, a joiner in its Welcome; "" is the default; the session keeps it.

const P1 := 1
const P2 := 2
const P3 := 3


func test_by_default_the_name_is_empty_everywhere() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	assert_str(game.state.lobby_name).is_empty()
	var welcome := game.view_of(P1).events_named(&"Welcome")[0] as WelcomeEvent
	assert_str(welcome.to_dict()["lobby_name"]).is_empty()
	assert_str(_last_change(game, P1).to_dict()["lobby_name"]).is_empty()


func test_the_host_names_the_lobby_and_everyone_sees_it() -> void:
	var game := _lobby_of_three()
	FixtureBaseMode.ready(game, P2)
	_rename(game, P1, "Dima's den")
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_str(game.state.lobby_name).is_equal("Dima's den")
	for peer: int in [P1, P2, P3]:
		var changed := _last_change(game, peer)
		assert_str(changed.lobby_name).is_equal("Dima's den")
		assert_str(changed.to_dict()["lobby_name"]).is_equal("Dima's den")
	# A rename keeps the settings and un-readies nobody.
	assert_dict(game.state.settings).is_equal({&"knives": 2, &"circles": 1})
	assert_bool(game.state.player(P2).ready).is_true()
	# An empty name is the default again.
	_rename(game, P1, "")
	assert_str(game.state.lobby_name).is_empty()
	assert_str(_last_change(game, P3).lobby_name).is_empty()


func test_the_host_cleans_the_name_and_never_refuses_it_for_its_content() -> void:
	var game := _lobby_of_three()
	_rename(game, P1, "  " + "x".repeat(30) + "  ")
	assert_str(game.state.lobby_name).is_equal("x".repeat(20))
	_rename(game, P1, "D" + String.chr(0x200B) + "en\n" + String.chr(0x202E))
	assert_str(game.state.lobby_name).is_equal("Den")
	_rename(game, P1, String.chr(0xA0) + "\t")
	assert_str(game.state.lobby_name).is_empty()
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_str(_last_change(game, P2).lobby_name).is_empty()


## Only core/ callers can send one (the wire's `name` is text); a null is an absent field.
func test_a_name_that_is_not_text_is_refused() -> void:
	var game := _lobby_of_three()
	_rename(game, P1, "Den")
	for odd: Variant in [7, 1.5, ["Den"]]:
		FixtureModes.send(
			game, Intents.CHANGE_SETTINGS, P1, {"settings": {"knives": 3}, "lobby_name": odd}
		)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"bad_args", &"bad_args", &"bad_args"]
	)
	assert_str(game.state.lobby_name).is_equal("Den")
	assert_int(game.state.settings[&"knives"]).is_equal(2)


func test_a_bad_setting_beside_a_name_applies_neither() -> void:
	var game := _lobby_of_three()
	var events := game.emitted().size()
	var args := {"settings": {"knives": 99}, "lobby_name": "Den"}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, args)
	FixtureModes.send(
		game,
		Intents.CHANGE_SETTINGS,
		P1,
		{"settings": {}, "map": "fixture://elsewhere", "lobby_name": "Den"}
	)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_bounds", &"unknown_map"])
	assert_str(game.state.lobby_name).is_empty()
	assert_int(game.state.settings[&"knives"]).is_equal(2)
	# Two Rejected and no SettingsChanged.
	assert_int(game.emitted().size()).is_equal(events + 2)


## The last check, the settings as a row's actions see them (DealTasks refuses banning every task
## type), runs after the name is cleaned: the name still waits for it.
func test_settings_a_row_refuses_beside_a_name_apply_neither() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	var every := ["second", "first"]
	var args := {"settings": {"banned_task_types": every}, "lobby_name": "Den"}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, args)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_bounds"])
	assert_str(game.state.lobby_name).is_empty()
	assert_str(FixtureBanModes.last_change(game, P1).lobby_name).is_empty()


func test_a_name_and_a_setting_change_together() -> void:
	var game := _lobby_of_three()
	var args := {"settings": {"knives": 3}, "lobby_name": "Den"}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, args)
	assert_str(game.state.lobby_name).is_equal("Den")
	assert_int(game.state.settings[&"knives"]).is_equal(3)
	var changed := _last_change(game, P2)
	assert_str(changed.lobby_name).is_equal("Den")
	assert_int(changed.settings[&"knives"]).is_equal(3)


func test_only_the_host_names_the_lobby() -> void:
	var game := _lobby_of_three()
	_rename(game, P1, "Den")
	_rename(game, P2, "Hacked")
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_str(game.state.lobby_name).is_equal("Den")


func test_the_countdown_refuses_a_rename() -> void:
	var game := FixtureBaseMode.in_countdown([P1, P2])
	_rename(game, P1, "Den")
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_str(game.state.lobby_name).is_empty()


func test_a_joiner_gets_the_name_in_its_welcome() -> void:
	var game := _lobby_of_three()
	_rename(game, P1, "Den")
	FixtureBaseMode.join(game, 4)
	var welcome := game.view_of(4).events_named(&"Welcome")[0] as WelcomeEvent
	assert_str(welcome.lobby_name).is_equal("Den")
	assert_str(welcome.to_dict()["lobby_name"]).is_equal("Den")


func test_the_session_keeps_the_name_from_match_to_match() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	_rename(game, P1, "Den")
	FixtureBaseMode.ready(game, P1)
	FixtureBaseMode.ready(game, P2)
	FixtureModes.run_ticks(game, 101)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.state.lobby_name).is_equal("Den")
	FixtureBaseMode.join(game, P3)
	var welcome := game.view_of(P3).events_named(&"Welcome")[0] as WelcomeEvent
	assert_str(welcome.lobby_name).is_equal("Den")


func _lobby_of_three() -> Match:
	var game := FixtureBaseMode.started()
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.join(game, peer)
	return game


func _rename(game: Match, peer: int, lobby: Variant) -> void:
	var args := {"settings": {}, "lobby_name": lobby}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, peer, args)


func _last_change(game: Match, peer: int) -> SettingsChangedEvent:
	return game.view_of(peer).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
