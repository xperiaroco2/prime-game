extends GdUnitTestSuite
## The defaults that follow the player count (ARCHITECTURE §9.1, #1492): a whole-number setting
## with a `defaults_by_players` table that the host never named takes the table's value for the
## players present on every join (before Welcome), on a leave in the Lobby and the Countdown and on
## the return to the lobby (ResetMatch), never in Loading; a number the host named keeps his value
## for the session. A fixture mode (FixtureBaseMode, 1 to 4 players) with a `dissidents` table
## {2: 1, 4: 2} over a default of 0: 1 player 0, 2 or 3 players 1, 4 players 2.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const HUMANS := &"dissidents"


func test_a_join_re_derives_the_default_before_welcome() -> void:
	var game := _started()
	var seen: Array[int] = []
	var welcomed: Array[int] = []
	for peer: int in [P1, P2, P3, P4]:
		FixtureBaseMode.join(game, peer)
		seen.append(_last_humans(game, P1))
		var welcome := game.view_of(peer).events_named(&"Welcome")[0] as WelcomeEvent
		welcomed.append(welcome.settings[HUMANS])
	assert_array(seen).is_equal([0, 1, 1, 2])
	assert_array(welcomed).is_equal([0, 1, 1, 2])


func test_a_leave_in_the_lobby_re_derives_the_default() -> void:
	var game := _joined([P1, P2, P3, P4])
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	assert_int(_last_humans(game, P1)).is_equal(1)
	assert_int(game.state.settings[HUMANS]).is_equal(1)
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_int(_last_humans(game, P1)).is_equal(0)


func test_a_leave_in_the_countdown_re_derives_the_default() -> void:
	var game := _joined([P1, P2, P3, P4])
	for peer: int in [P1, P2, P3, P4]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	var changed := game.view_of(P1).events.slice(from).filter(
		func(event: MatchEvent) -> bool: return event is SettingsChangedEvent
	)
	assert_int(changed.size()).is_equal(1)
	assert_int((changed[0] as SettingsChangedEvent).settings[HUMANS]).is_equal(1)
	assert_int(game.state.settings[HUMANS]).is_equal(1)


func test_a_drop_in_loading_keeps_the_value_load_match_carried() -> void:
	# The settings froze when Loading began: a drop there tells nobody a new value, so the deal
	# must read the one LoadMatch carried.
	var game := _joined([P1, P2, P3, P4])
	for peer: int in [P1, P2, P3, P4]:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	assert_str(game.phase_id()).is_equal("loading")
	var load_match := game.view_of(P1).events_named(&"LoadMatch")[0] as LoadMatchEvent
	assert_int(load_match.settings[HUMANS]).is_equal(2)
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	assert_int(game.state.present_peers().size()).is_equal(3)
	assert_int(game.state.settings[HUMANS]).is_equal(2)


func test_a_number_the_host_names_stays_through_joins_and_leaves() -> void:
	var game := _joined([P1, P2])
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"dissidents": 0}})
	FixtureBaseMode.join(game, P3)
	FixtureBaseMode.join(game, P4)
	assert_int(_last_humans(game, P1)).is_equal(0)
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	assert_int(_last_humans(game, P1)).is_equal(0)


func test_a_named_number_equal_to_the_default_still_stays() -> void:
	# The host's word, not the value: 1 is the default at 2 players, and it stays 1 at 4.
	var game := _joined([P1, P2])
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"dissidents": 1}})
	FixtureBaseMode.join(game, P3)
	FixtureBaseMode.join(game, P4)
	assert_int(_last_humans(game, P1)).is_equal(1)


func test_a_rejected_change_or_another_setting_names_nothing() -> void:
	var game := _joined([P1, P2])
	var refused := {"settings": {"knives": 1, "dissidents": 9}}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, refused)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([RejectReasons.OUT_OF_BOUNDS])
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"knives": 1}})
	assert_dict(game.state.host_settings).is_equal({&"knives": true})
	FixtureBaseMode.join(game, P3)
	FixtureBaseMode.join(game, P4)
	assert_int(_last_humans(game, P1)).is_equal(2)


func test_the_return_to_the_lobby_re_derives_it_from_the_players_left() -> void:
	var game := _in_end([P1, P2, P3, P4])
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	# Left in End, both still counted until the reset drops them.
	assert_int(game.state.settings[HUMANS]).is_equal(2)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(_last_humans(game, P1)).is_equal(1)
	assert_int(game.state.settings[HUMANS]).is_equal(1)


func test_a_named_number_survives_the_return_to_the_lobby() -> void:
	var mode := _mode()
	var game := _started(mode)
	for peer: int in [P1, P2, P3, P4]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"dissidents": 3}})
	_through_to_end(game, [P1, P2, P3, P4])
	FixtureModes.send(game, Intents.PEER_LEFT, P4)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_int(_last_humans(game, P1)).is_equal(3)


func test_a_setting_without_a_table_is_left_alone() -> void:
	var game := _joined([P1, P2, P3, P4])
	assert_int(game.state.settings[&"knives"]).is_equal(2)
	assert_dict(game.state.host_settings).is_empty()


## FixtureBaseMode's mode with `dissidents` 0 to 3, default 0, following {2: 1, 4: 2}.
func _mode() -> GameMode:
	var mode := FixtureBaseMode.mode()
	var humans := FixtureModes.setting(HUMANS, 0, 0, 3)
	humans.defaults_by_players = {2: 1, 4: 2}
	mode.settings.append(humans)
	return mode


func _started(mode: GameMode = null) -> Match:
	var made := mode if mode != null else _mode()
	var game := Match.new(made, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	return game


func _joined(peers: Array[int]) -> Match:
	var game := _started()
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	return game


## `peers` ready, through the countdown, loading and the pregame, then the crew wins: End.
func _through_to_end(game: Match, peers: Array[int]) -> void:
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)


func _in_end(peers: Array[int]) -> Match:
	var game := _joined(peers)
	_through_to_end(game, peers)
	assert_str(game.phase_id()).is_equal("end")
	return game


## The `dissidents` value of the last SettingsChanged `peer` received.
func _last_humans(game: Match, peer: int) -> int:
	var changed := game.view_of(peer).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
	return changed.settings[HUMANS]
