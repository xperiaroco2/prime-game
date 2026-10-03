extends GdUnitTestSuite
## Loading (ARCHITECTURE §3.2, §3.5, §9.4): RefuseJoins, the waiting newcomers disconnected (E14)
## and LoadMatch on entry; a Hello refused with `joins_closed`; LoadAck with the
## current match id, once; the deadline drops who did not confirm, never the host; a leave drops
## too; `all_loaded` when every remaining player confirmed.

const P1 := 1
const P2 := 2
const P3 := 3
const P5 := 5
## 60 s at 20 Hz.
const DEADLINE_TICKS := 1200


func test_entering_loading_refuses_joins_and_names_the_match() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	assert_str(game.phase_id()).is_equal("loading")
	assert_array(FixtureBaseMode.directives(game)).is_equal(["AllowJoins", "RefuseJoins"])
	for peer: int in [P1, P2]:
		var load_event := game.view_of(peer).events_named(&"LoadMatch")[0] as LoadMatchEvent
		assert_int(load_event.match_id).is_equal(0)
		assert_str(load_event.map).is_equal(FixtureBaseMode.MAP)
		assert_dict(load_event.settings).is_equal({&"knives": 2, &"circles": 1})
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
	var emitted_before := game.emitted().size()
	FixtureBaseMode.load_ack(game, P2, 7)
	FixtureModes.send(game, Intents.LOAD_ACK, P2, {"match_id": "0"})
	FixtureModes.send(game, Intents.LOAD_ACK, P2, {})
	assert_int(game.emitted().size()).is_equal(emitted_before)
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
	# #119: the dropped player alone hears why, right before its DisconnectPeer.
	var told := game.view_of(P3).events_named(&"Disconnecting")
	assert_int(told.size()).is_equal(1)
	assert_str((told[0] as DisconnectingEvent).reason).is_equal("load_deadline")
	assert_int((told[0] as DisconnectingEvent).peer).is_equal(P3)
	for peer: int in [P1, P2]:
		assert_array(game.view_of(peer).events_named(&"Disconnecting")).is_empty()
	var names: Array[StringName] = []
	for emitted: EmittedEvent in game.emitted():
		names.append(emitted.event.event_name())
	assert_int(names.rfind(&"Disconnecting")).is_equal(names.rfind(&"DisconnectPeer") - 1)
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
	# Its Hello was in flight: it is told why (E14), and not disconnected a second time.
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"joins_closed"])
	assert_int(FixtureBaseMode.directives(game).count("DisconnectPeer 3")).is_equal(1)
	assert_object(game.state.player(P3)).is_null()


func test_the_entry_disconnects_every_waiting_newcomer_and_tells_it_nothing() -> void:
	var game := FixtureBaseMode.in_countdown([P1, P2])
	# Two connections that never sent Hello (lurkers), in the countdown.
	for peer: int in [P5, P3]:
		FixtureModes.send(game, Intents.PEER_CONNECTED, peer)
	FixtureModes.run_ticks(game, 101)
	assert_str(game.phase_id()).is_equal("loading")
	assert_array(FixtureBaseMode.directives(game)).is_equal(
		["AllowJoins", "RefuseJoins", "DisconnectPeer 3", "DisconnectPeer 5"]
	)
	assert_bool(game.state.newcomers.is_empty()).is_true()
	for peer: int in [P3, P5]:
		assert_array(game.view_of(peer).event_names()).is_empty()
	# The disconnect comes before LoadMatch, which only the players receive.
	var names := FixtureModes.names(game)
	assert_int(names.rfind(&"DisconnectPeer")).is_less(names.find(&"LoadMatch"))
	# A Hello of P5's that was in flight is told why, with no second DisconnectPeer; its late
	# PeerLeft changes nothing.
	FixtureBaseMode.hello(game, P5, "late", JoinRules.PROTOCOL_VERSION, 1)
	assert_array(FixtureModes.rejections(game, P5)).is_equal([&"joins_closed"])
	assert_int(FixtureBaseMode.directives(game).count("DisconnectPeer 5")).is_equal(1)
	FixtureModes.send(game, Intents.PEER_LEFT, P5)
	assert_array(game.state.peers()).is_equal([P1, P2])
	assert_array(game.diagnostics).is_empty()


func test_a_mode_without_a_loading_deadline_is_refused() -> void:
	var mode := FixtureBaseMode.mode()
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	mode.find_phase(&"loading").settings.erase(&"deadline_seconds")
	var errors := Array(ModeCheck.run(mode).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).contains("missing setting deadline_seconds")


func test_an_empty_roster_never_moves_on() -> void:
	# The host is never dropped, so the roster is never empty; if every player still left (the
	# host's own PeerLeft included), Loading reports no `all_loaded` for nobody.
	var game := FixtureBaseMode.in_loading([P1, P2])
	FixtureBaseMode.load_ack(game, P2)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	assert_array(game.state.peers()).is_empty()
	assert_str(game.phase_id()).is_equal("loading")
	FixtureModes.run_ticks(game, DEADLINE_TICKS + 5)
	assert_str(game.phase_id()).is_equal("loading")
