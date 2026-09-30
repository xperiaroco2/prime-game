extends GdUnitTestSuite
## End (ARCHITECTURE §3.2, §3.5, §9.4): the host's ReturnToLobby reports `back`; joins are refused
## (and in Round); a leave sets the life state `left` and emits PlayerLeft.

const P1 := 1
const P2 := 2
const P3 := 3


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
