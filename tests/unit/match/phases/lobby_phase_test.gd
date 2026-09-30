extends GdUnitTestSuite
## Lobby (ARCHITECTURE §3.2, §4.1, §9.4): AllowJoins on entry, SetReady, the host's ChangeSettings
## with its bounds and maps, and `all_ready` when everyone is ready and the settings fit the map
## (FitCheck), with SettingsChanged showing why not.

const P1 := 1
const P2 := 2
const P3 := 3


func test_entering_the_lobby_allows_joins() -> void:
	var game := FixtureBaseMode.started()
	assert_array(FixtureBaseMode.directives(game)).is_equal(["AllowJoins"])
	var allow := game.emitted()[1]
	assert_bool(allow.is_directive).is_true()
	assert_array(Array(allow.recipients)).is_empty()


func test_set_ready_changes_the_flag_and_tells_everyone() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureBaseMode.ready(game, P2)
	assert_bool(game.state.player(P2).ready).is_true()
	assert_str(game.phase_id()).is_equal("lobby")
	for peer: int in [P1, P2]:
		var changed := game.view_of(peer).events_named(&"ReadyChanged")[0] as ReadyChangedEvent
		assert_int(changed.peer).is_equal(P2)
		assert_bool(changed.ready).is_true()
	FixtureBaseMode.ready(game, P2, false)
	assert_bool(game.state.player(P2).ready).is_false()
	assert_int(game.view_of(P1).events_named(&"ReadyChanged").size()).is_equal(2)


func test_only_a_change_of_ready_is_accepted() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureBaseMode.ready(game, P2, false, 4)
	FixtureBaseMode.ready(game, P2, true)
	FixtureBaseMode.ready(game, P2, true, 6)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unchanged", &"unchanged"])
	assert_int(game.view_of(P1).events_named(&"ReadyChanged").size()).is_equal(1)


func test_all_ready_starts_the_countdown() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureBaseMode.ready(game, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureBaseMode.ready(game, P2)
	assert_str(game.phase_id()).is_equal("countdown")
	var changed := game.view_of(P1).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
	assert_str(changed.phase).is_equal("countdown")
	assert_int(changed.end_tick).is_equal(game.current_phase().entered_tick + 100)


func test_settings_that_do_not_fit_the_map_hold_the_lobby_and_say_why() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	# The small map has 1 knife marker; knives is 2.
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"map": FixtureBaseMode.SMALL_MAP})
	assert_str(game.state.map).is_equal(FixtureBaseMode.SMALL_MAP)
	FixtureBaseMode.ready(game, P1)
	FixtureBaseMode.ready(game, P2)
	assert_str(game.phase_id()).is_equal("lobby")
	var changed := game.view_of(P2).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
	assert_str(changed.map).is_equal(FixtureBaseMode.SMALL_MAP)
	assert_int(changed.players).is_equal(2)
	assert_dict(changed.needed_markers).is_equal({&"round_player": 2, &"knife": 2, &"circle": 1})
	assert_dict(changed.map_markers).is_equal({&"round_player": 4, &"knife": 1, &"circle": 1})
	assert_dict(changed.needed_colours).is_equal({&"circle": 1})
	assert_dict(changed.palettes).is_equal({&"circle": 2})
	assert_array(Array(changed.shortfalls)).is_equal(["2 knife marker(s) needed, the map has 1"])
	# A change that fits fires all_ready at once: the ready flags stayed.
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"knives": 1}})
	assert_str(game.phase_id()).is_equal("countdown")


func test_more_stations_than_palette_colours_do_not_fit() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"circles": 3}})
	FixtureBaseMode.ready(game, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	var changed := game.view_of(P1).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
	assert_array(Array(changed.shortfalls)).is_equal(
		["3 circle colour(s) needed, the palette has 2"]
	)


func test_the_player_count_must_be_within_the_modes_bounds() -> void:
	var mode := FixtureBaseMode.mode()
	mode.min_players = 2
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.ready(game, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	var changed := game.view_of(P1).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
	assert_array(Array(changed.shortfalls)).is_equal(["1 player(s), the mode plays with 2 to 4"])
	FixtureBaseMode.join(game, P2)
	FixtureBaseMode.ready(game, P2)
	assert_str(game.phase_id()).is_equal("countdown")


func test_the_host_changes_settings_and_un_readies_nobody() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureBaseMode.join(game, P3)
	FixtureBaseMode.ready(game, P2)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"knives": 3, "circles": 2}})
	assert_dict(game.state.settings).is_equal({&"knives": 3, &"circles": 2})
	assert_bool(game.state.player(P2).ready).is_true()
	for peer: int in [P1, P2, P3]:
		var changed := (
			game.view_of(peer).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
		)
		assert_dict(changed.settings).is_equal({&"knives": 3, &"circles": 2})


func test_only_the_host_changes_settings() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P2, {"settings": {"knives": 3}})
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(game.state.settings[&"knives"]).is_equal(2)


func test_a_bad_change_is_rejected_whole() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	var bad: Array[Dictionary] = [
		{"settings": {"knives": 3, "bogus": 1}},
		{"settings": {"knives": 3.0}},
		{"settings": "knives"},
		{"settings": {"knives": 3, "circles": 11}},
		{"settings": {"knives": -1}},
		{"settings": {"knives": 3}, "map": "fixture://elsewhere"},
		{"map": 5},
	]
	for args: Dictionary in bad:
		FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, args)
	(
		assert_array(FixtureModes.rejections(game, P1))
		. is_equal(
			[
				&"unknown_setting",
				&"unknown_setting",
				&"unknown_setting",
				&"out_of_bounds",
				&"out_of_bounds",
				&"unknown_map",
				&"unknown_map",
			]
		)
	)
	assert_dict(game.state.settings).is_equal({&"knives": 2, &"circles": 1})
	assert_str(game.state.map).is_equal(FixtureBaseMode.MAP)


func test_a_leave_that_leaves_everyone_ready_starts_the_countdown() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureBaseMode.ready(game, P1)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_str(game.phase_id()).is_equal("countdown")


func test_an_empty_lobby_is_never_all_ready() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, 3)
	assert_str(game.phase_id()).is_equal("lobby")
