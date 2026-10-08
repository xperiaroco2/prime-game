extends GdUnitTestSuite
## End (ARCHITECTURE §3.2, §3.5, §9.4): `back` on its end tick, `seconds` (the fixture's 3 s) after
## the entry with no intent (#212), or earlier on the host's ReturnToLobby; with no `seconds` only
## the host's ReturnToLobby; joins are refused (and in Round); a leave sets the life state `left`
## and emits PlayerLeft.

const P1 := 1
const P2 := 2
const P3 := 3


func test_with_no_intent_the_end_goes_back_to_the_lobby_on_its_announced_tick() -> void:
	var game := FixtureBaseMode.in_end([P1, P2])
	var entered := game.current_phase().entered_tick
	for peer: int in [P1, P2]:
		var changed := game.view_of(peer).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
		assert_str(changed.phase).is_equal("end")
		assert_int(changed.end_tick).is_equal(entered + 3 * Ticks.RATE)
	var end := entered + 3 * Ticks.RATE
	while game.ticked_through() < end - 1:
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.run_ticks(game, 1)
	assert_int(game.ticked_through()).is_equal(end)
	assert_str(game.phase_id()).is_equal("lobby")
	# The `back` row ran: the match is reset, everyone un-ready, and everyone was told.
	assert_str(game.state.winner).is_empty()
	for peer: int in [P1, P2]:
		assert_bool(game.state.player(peer).ready).is_false()
		var changed := game.view_of(peer).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
		assert_dict(changed.to_dict()).is_equal({"phase": &"lobby", "end_tick": -1})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_an_end_with_no_seconds_waits_for_the_host() -> void:
	var mode := FixtureBaseMode.mode()
	mode.find_phase(&"end").settings.erase(&"seconds")
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	var changed := game.view_of(P1).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
	assert_int(changed.end_tick).is_equal(-1)
	FixtureModes.run_ticks(game, 10 * Ticks.RATE)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")


func test_the_end_s_seconds_are_0_to_60() -> void:
	var phase := EndPhase.new()
	for good: float in [0.0, 3.0, 60.0]:
		assert_array(Array(phase.check_settings({&"seconds": good}))).is_empty()
	assert_array(Array(phase.check_settings({}))).is_empty()
	assert_array(Array(phase.check_settings({&"seconds": 61.0}))).is_equal(
		["seconds is 61, outside 0 to 60"]
	)
	assert_array(Array(phase.check_settings({&"secs": 3.0}))).is_equal(["unknown setting secs"])


func test_the_hosts_return_to_lobby_goes_back() -> void:
	var game := FixtureBaseMode.in_end([P1, P2])
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P2, {}, 4)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	# Everyone is un-ready again: the lobby waits.
	for peer: int in [P1, P2]:
		assert_bool(game.state.player(peer).ready).is_false()


func test_a_leave_in_end_marks_the_player_left() -> void:
	var game := FixtureBaseMode.in_end([P1, P2, P3])
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.LEFT)
	var left := game.view_of(P1).events_named(&"PlayerLeft")[0] as PlayerLeftEvent
	assert_int(left.peer).is_equal(P3)
	assert_array(game.view_of(P3).events_named(&"PlayerLeft")).is_empty()
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	assert_int(game.view_of(P1).events_named(&"PlayerLeft").size()).is_equal(1)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_array(game.state.peers()).is_equal([P1, P2])


func test_joins_are_refused_in_end_and_in_the_round() -> void:
	var game := FixtureBaseMode.in_round([P1])
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	assert_array(FixtureBaseMode.directives(game).slice(-1)).is_equal(["DisconnectPeer 2"])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.PEER_CONNECTED, P3)
	assert_array(FixtureBaseMode.directives(game).slice(-1)).is_equal(["DisconnectPeer 3"])
	assert_bool(game.state.newcomers.is_empty()).is_true()
