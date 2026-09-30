extends GdUnitTestSuite
## Loading (ARCHITECTURE §3.2, §3.5, §9.4): RefuseJoins and LoadMatch on entry; LoadAck with the
## current match id, once; the deadline drops who did not confirm, never the host; a leave drops
## too; `all_loaded` when every remaining player confirmed.

const P1 := 1
const P2 := 2
const P3 := 3
## 60 s at 20 Hz.
const DEADLINE_TICKS := 1200


func test_entering_loading_refuses_joins_and_names_the_match() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	assert_str(game.phase_id()).is_equal("loading")
	assert_array(FixtureBaseMode.directives(game)).is_equal(["AllowJoins", "RefuseJoins"])
	for peer: int in [P1, P2]:
		var load := game.view_of(peer).events_named(&"LoadMatch")[0] as LoadMatchEvent
		assert_int(load.match_id).is_equal(0)
		assert_str(load.map).is_equal(FixtureBaseMode.MAP)
		assert_dict(load.settings).is_equal({&"knives": 2, &"circles": 1})
	# PhaseChanged announces no deadline: only a countdown's or the clock's end.
	var changed := game.view_of(P1).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
	assert_int(changed.end_tick).is_equal(-1)


func test_every_ack_moves_on_to_the_round() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	FixtureBaseMode.load_ack(game, P2)
	assert_str(game.phase_id()).is_equal("loading")
	var loaded := game.view_of(P1).events_named(&"PlayerLoaded")[0] as PlayerLoadedEvent
	assert_int(loaded.peer).is_equal(P2)
	FixtureBaseMode.load_ack(game, P1)
	assert_str(game.phase_id()).is_equal("round")
	assert_array(game.view_of(P2).event_names().slice(-5)).is_equal(
		[&"PlayerLoaded", &"PlayerLoaded", &"PlayersPlaced", &"Correction", &"PhaseChanged"]
	)


func test_an_ack_of_another_match_is_dropped_and_a_second_is_rejected() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	var before := game.emitted().size()
	FixtureBaseMode.load_ack(game, P2, 7)
	FixtureModes.send(game, Intents.LOAD_ACK, P2, {"match_id": "0"})
	FixtureModes.send(game, Intents.LOAD_ACK, P2, {})
	assert_int(game.emitted().size()).is_equal(before)
	FixtureBaseMode.load_ack(game, P2)
	FixtureBaseMode.load_ack(game, P2, -1, 9)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unchanged"])
	assert_int(game.view_of(P1).events_named(&"PlayerLoaded").size()).is_equal(1)


func test_the_deadline_drops_who_did_not_confirm() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2, P3])
	var entered := game.current_phase().entered_tick
	FixtureBaseMode.load_ack(game, P1)
	FixtureBaseMode.load_ack(game, P2)
	while game.ticked_through() < entered + DEADLINE_TICKS - 1:
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	assert_array(game.state.peers()).is_equal([P1, P2, P3])
	var from := game.view_of(P1).events.size()
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureBaseMode.directives(game).slice(-1)).is_equal(["DisconnectPeer 3"])
	assert_array(game.state.peers()).is_equal([P1, P2])
	assert_array(FixtureBaseMode.names_since(game, P1, from).slice(0, 1)).is_equal([&"PlayerLeft"])
	assert_str(game.phase_id()).is_equal("round")
	# Its late PeerLeft changes nothing.
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	assert_array(game.diagnostics).is_empty()


func test_the_host_is_never_dropped() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	FixtureBaseMode.load_ack(game, P2)
	FixtureModes.run_ticks(game, DEADLINE_TICKS + 5)
	assert_str(game.phase_id()).is_equal("loading")
	assert_array(game.state.peers()).is_equal([P1, P2])
	assert_array(FixtureBaseMode.directives(game)).not_contains(["DisconnectPeer 1"])
	FixtureBaseMode.load_ack(game, P1)
	assert_str(game.phase_id()).is_equal("round")


func test_a_leave_drops_the_player() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	FixtureBaseMode.load_ack(game, P1)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(game.state.peers()).is_equal([P1])
	var left := game.view_of(P1).events_named(&"PlayerLeft")[0] as PlayerLeftEvent
	assert_int(left.peer).is_equal(P2)
	assert_str(game.phase_id()).is_equal("round")


func test_a_connection_while_loading_is_disconnected() -> void:
	var game := FixtureBaseMode.in_loading([P1])
	FixtureModes.send(game, Intents.PEER_CONNECTED, P3)
	FixtureBaseMode.hello(game, P3, "late")
	assert_array(FixtureBaseMode.directives(game).slice(-1)).is_equal(["DisconnectPeer 3"])
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"not_accepted"])
	assert_object(game.state.player(P3)).is_null()
