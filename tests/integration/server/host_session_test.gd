extends GdUnitTestSuite
## HostSession (ARCHITECTURE §4.5): starting, joining and leaving over the wire, refused joins,
## the hello deadline, per-peer delivery with snapshots after events, the loading deadline's
## DisconnectPeer, and the fatal row error. Over a LoopbackHub with a fake clock
## (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_the_real_mode_starts_with_its_content_hash_and_welcomes_its_own_client() -> void:
	# The real start: every level's world, the markers read through them, a seed from Crypto.
	var mode := load(BASE_MODE) as GameMode
	var schema := WireSchema.game(true)
	var hub := LoopbackHub.new()
	var session := HostSession.new(LoopbackTransport.new(schema.kind_table(), hub), schema)
	session.replay_dir = ""
	assert_bool(session.start(mode, 7301, 8, 0)).is_true()
	assert_array(Array(session.errors)).is_empty()
	var fingerprint := ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)
	assert_int(session.content_hash).is_equal(fingerprint)
	assert_int(session.game.content_hash).is_equal(fingerprint)
	assert_int(session.game.command_log.content_hash).is_equal(fingerprint)
	assert_str(String(session.game.phase_id())).is_equal(String(mode.first_phase))
	assert_int(session.game.ticked_through()).is_equal(-1)
	var own := ClientSession.new(session.own_client, mode, schema)
	own.load_levels = false
	var now := 0
	for _i in 10:
		now += Harness.FRAME_USEC
		session.step(now)
		own.step(now)
	assert_bool(own.is_welcomed()).is_true()
	assert_int(own.model.own_peer).is_equal(NetTransport.HOST_ID)
	assert_int(session.game.ticked_through()).is_equal(session.tick_of(now))
	session.close()
	assert_str(String(own.end_reason)).is_empty()
	own.step(now + Harness.FRAME_USEC)
	assert_str(String(own.end_reason)).is_equal(String(ClientSession.HOST_LOST))


func test_a_level_with_errors_refuses_the_host() -> void:
	var mode := Harness.fixture_mode()
	mode.lobby_level = "res://tests/fixtures/server/no_such_level.tscn"
	var schema := WireSchema.game(true)
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	var session := HostSession.new(transport, schema)
	assert_bool(session.start(mode, 7302, 8, 0)).is_false()
	assert_str("; ".join(session.errors)).contains("no_such_level")
	assert_bool(transport.is_host()).is_false()
	assert_object(session.game).is_null()


func test_a_refused_mode_refuses_the_host() -> void:
	var mode := Harness.fixture_mode()
	mode.first_phase = &"nowhere"
	var schema := WireSchema.game(true)
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	var session := HostSession.new(transport, schema)
	var started := session.start_with(
		mode, FlatWorldQuery.new(), Harness.layouts(), 7303, 8, 0, Harness.SEED
	)
	assert_bool(started).is_false()
	assert_array(Array(session.errors)).is_not_empty()
	assert_bool(transport.is_host()).is_false()
	assert_object(session.game).is_null()


func test_a_refused_start_may_be_retried_on_another_port() -> void:
	var schema := WireSchema.game(true)
	var hub := LoopbackHub.new()
	var first := HostSession.new(LoopbackTransport.new(schema.kind_table(), hub), schema)
	first.replay_dir = ""
	var mode := Harness.fixture_mode()
	var world := FlatWorldQuery.new()
	assert_bool(first.start_with(mode, world, Harness.layouts(), 7304, 8, 0, 1)).is_true()
	var second := HostSession.new(LoopbackTransport.new(schema.kind_table(), hub), schema)
	second.replay_dir = ""
	assert_bool(second.start_with(mode, world, Harness.layouts(), 7304, 8, 0, 1)).is_false()
	assert_str("; ".join(second.errors)).contains("7304")
	assert_object(second.game).is_null()
	assert_bool(second.is_running()).is_false()
	assert_bool(second.start_with(mode, world, Harness.layouts(), 7305, 8, 0, 1)).is_true()
	assert_array(Array(second.errors)).is_empty()
	assert_object(second.game).is_not_null()
	assert_bool(second.is_running()).is_true()
	second.close()
	first.close()


func test_the_seed_comes_from_the_operating_system() -> void:
	# 8 random bytes: two equal seeds in a row would be a 2^-64 chance.
	assert_int(HostSession.random_seed()).is_not_equal(HostSession.random_seed())


func test_ticks_come_from_the_clock() -> void:
	_h = Harness.new()
	assert_bool(_h.started).is_true()
	assert_int(_h.session.tick_of(_h.now)).is_equal(0)
	assert_int(_h.session.tick_of(_h.now + 49999)).is_equal(0)
	assert_int(_h.session.tick_of(_h.now + 50000)).is_equal(1)
	# 60 Hz frames: tick 0 on the first, tick 1 on the third (50.001 ms).
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(0)
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(0)
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(1)
	# A 5 s freeze: the ticks run through it.
	_h.now += 5 * Harness.SECOND
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(_h.session.tick_of(_h.now))


func test_join_and_leave() -> void:
	_h = Harness.new()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	assert_int(_h.peer_of(second)).is_equal(2)
	assert_array(_h.own.model.roster.keys()).contains_exactly_in_any_order([1, 2])
	assert_str(second.model.roster[2].name).is_equal("Player2")
	second.leave()
	_h.pump_frames(4)
	assert_bool(_h.session.game.state.is_present(2)).is_false()
	assert_array(_h.own.view.event_names()).contains([&"PlayerLeft"])
	assert_array(_h.own.model.roster.keys()).is_equal([1])
	assert_array(_h.mismatches(_h.own)).is_empty()


func test_wrong_version_is_rejected_and_disconnected() -> void:
	_h = Harness.new()
	var raw := _h.raw()
	_h.pump()
	raw.hello(_h.session.content_hash, WireSchema.VERSION + 1)
	_h.pump_frames(4)
	assert_array(raw.names()).is_equal([&"Rejected"])
	assert_str(str(raw.received[0].fields["reason"])).is_equal("wrong_version")
	assert_bool(raw.lost).is_true()


func test_wrong_content_ends_the_join() -> void:
	_h = Harness.new()
	var other := Harness.fixture_mode()
	other.max_players = 3
	var stranger := _h.join(other)
	_h.pump_frames(4)
	assert_str(String(stranger.end_reason)).is_equal("wrong_content")
	assert_array(stranger.view.event_names()).is_equal([&"Rejected"])
	assert_bool(_h.transport.peers().has(2)).is_false()
	assert_bool(_h.welcome_all()).is_false()


func test_joins_closed_rejects_then_disconnects_the_join() -> void:
	# A countdown that takes no Hello: a newcomer's Hello gets Rejected(joins_closed), then
	# DisconnectPeer (E14), in that order.
	var mode := Harness.fixture_mode()
	var countdown := mode.find_phase(&"countdown")
	var accepts: Array[AcceptSpec] = []
	for spec: AcceptSpec in countdown.accepts:
		if spec.intent != Intents.HELLO:
			accepts.append(spec)
	countdown.accepts = accepts
	_h = Harness.new(mode)
	assert_bool(_h.welcome_all()).is_true()
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"countdown", 10)).is_true()
	var late := _h.join()
	_h.pump_frames(4)
	assert_str(String(late.end_reason)).is_equal("joins_closed")
	assert_array(late.view.event_names()).is_equal([&"Rejected"])
	assert_array(late.view.snapshots.keys()).is_empty()
	assert_bool(_h.transport.peers().has(2)).is_false()
	assert_array(FixtureBaseMode.directives(_h.session.game)).contains(["DisconnectPeer 2"])


func test_a_peer_without_hello_is_disconnected_at_the_hello_deadline() -> void:
	_h = Harness.new()
	var lurker := _h.raw()
	_h.pump()
	_h.pump_seconds(9.9)
	assert_bool(lurker.lost).is_false()
	assert_bool(_h.transport.peers().has(2)).is_true()
	_h.pump_seconds(0.2)
	assert_bool(lurker.lost).is_true()
	# It decoded nothing: no everyone event, snapshot or voice reaches a peer that is not a player.
	assert_array(lurker.received).is_empty()
	assert_bool(_h.session.is_running()).is_true()


func test_a_hello_read_in_a_step_with_no_tick_due_beats_the_deadline() -> void:
	_h = Harness.new(null, false)
	var late := _h.raw()
	_h.pump()
	var joined := _h.now
	# The deadline falls 10 ms into a tick; the Hello is read 20 ms into it, when no tick is due.
	var tick_usec := Harness.SECOND / Ticks.RATE
	var boundary := Harness.SECOND + (_h.session.tick_of(joined) + 10) * tick_usec
	_h.session.hello_deadline_usec = boundary + 10000 - joined
	_h.session.step(boundary)
	late.poll()
	assert_bool(late.lost).is_false()
	late.hello(_h.session.content_hash)
	_h.session.step(boundary + 20000)
	assert_int(_h.session.game.ticked_through()).is_equal(_h.session.tick_of(boundary))
	_h.session.step(boundary + tick_usec)
	_h.now = boundary + tick_usec
	late.poll()
	assert_bool(late.lost).is_false()
	assert_array(late.names().slice(0, 1)).is_equal([&"Welcome"])


func test_the_hello_deadline_is_a_setting_and_spares_peer_one() -> void:
	_h = Harness.new(null, false)
	_h.session.hello_deadline_usec = 30 * Harness.SECOND
	var lurker := _h.raw()
	_h.pump_seconds(20)
	assert_bool(lurker.lost).is_false()
	# Peer 1 never sent its Hello either: it is never disconnected.
	_h.pump_seconds(20)
	assert_bool(lurker.lost).is_true()
	assert_bool(_h.transport.peers().has(NetTransport.HOST_ID)).is_true()
	assert_bool(_h.session.is_running()).is_true()


func test_each_peer_gets_its_own_events_and_snapshots_after_them() -> void:
	_h = Harness.new()
	var watcher := _h.raw()
	_h.join()
	_h.pump()
	watcher.hello(_h.session.content_hash)
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(3)
	assert_array(watcher.names()).contains([&"Welcome"])
	# Peer 3 (the second client) readies: ReadyChanged comes before that tick's snapshot.
	var earlier := watcher.received.size()
	_h.clients[1].send_intent(Intents.SET_READY, {"ready": true})
	var changed_seen := func() -> bool: return not watcher.named(&"ReadyChanged").is_empty()
	assert_bool(_h.pump_until(changed_seen, 6)).is_true()
	_h.pump_frames(3)
	var order := watcher.names().slice(earlier)
	var changed := order.find(&"ReadyChanged")
	assert_int(changed).is_greater_equal(0)
	assert_int(order.find(&"Snapshot", changed)).is_greater(changed)
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()


func test_no_snapshot_for_catch_up_ticks() -> void:
	_h = Harness.new()
	var watcher := _h.raw()
	_h.pump()
	watcher.hello(_h.session.content_hash)
	_h.pump_frames(6)
	var earlier := watcher.named(&"Snapshot").size()
	_h.now += Harness.SECOND
	_h.pump()
	var snapshots := watcher.named(&"Snapshot")
	assert_int(snapshots.size()).is_equal(earlier + 1)
	assert_int(snapshots.back().fields["tick"] as int).is_equal(_h.session.tick_of(_h.now))


func test_a_loading_deadline_disconnects_the_peer_after_what_was_sent_to_it() -> void:
	_h = Harness.new()
	var slow := _h.raw()
	_h.pump()
	slow.hello(_h.session.content_hash)
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(3)
	slow.send(WireMessage.new(Intents.SET_READY, {"ready": true}, 1))
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"loading", 400)).is_true()
	assert_array(slow.names()).contains([&"LoadMatch"])
	# It never acknowledges: at the 60 s deadline it is disconnected, the round starts without it.
	_h.pump_seconds(61)
	assert_bool(slow.lost).is_true()
	assert_str(String(_h.session.game.phase_id())).is_equal("round")
	assert_bool(_h.session.is_running()).is_true()
	# Everything core/ addressed to it before the DisconnectPeer arrived, in order, then host_lost.
	var view := _h.session.game.view_of(slow.peer)
	var expected: Array[StringName] = view.event_names()
	var got: Array[StringName] = []
	for message: WireMessage in slow.received:
		if not message.name in [&"Snapshot", DecodedView.VOICE_BATCH, DecodedView.VOICE_DOWN]:
			got.append(message.name)
	assert_array(got).is_equal(expected)
	assert_array(FixtureBaseMode.directives(_h.session.game)).contains(
		["DisconnectPeer %d" % slow.peer]
	)


func test_a_failed_deal_ends_the_session_before_its_events_are_delivered() -> void:
	var mode := Harness.fixture_mode()
	for row: Transition in mode.transitions:
		if row.outcome == LoadingPhase.ALL_LOADED:
			row.actions.append(FixtureError.new())
	_h = Harness.new(mode)
	assert_bool(_h.welcome_all()).is_true()
	_h.ready_all()
	assert_bool(_h.pump_until(func() -> bool: return not _h.session.is_running(), 400)).is_true()
	assert_str(String(_h.session.end_reason)).is_equal(String(HostSession.ROW_ERROR))
	assert_str("; ".join(_h.session.errors)).contains("fixture error")
	_h.pump()
	assert_str(String(_h.own.end_reason)).is_equal(String(ClientSession.HOST_LOST))
	# The failing call's slice (the placement and the round's entry) never reached the client:
	# it decoded view_of(1) up to that slice and nothing of it.
	assert_str(_h.calls[_h.calls.size() - 1]).contains("LoadAck")
	var withheld: Array[StringName] = []
	for emitted: EmittedEvent in _h.last_slice:
		if not emitted.is_directive and emitted.recipients.has(NetTransport.HOST_ID):
			withheld.append(emitted.event.event_name())
	assert_array(withheld).contains([&"PlayersPlaced", &"PhaseChanged"])
	var view := _h.session.game.view_of(NetTransport.HOST_ID).event_names()
	var decoded := _h.own.view.event_names()
	assert_array(decoded).contains([&"LoadMatch"])
	assert_array(decoded).not_contains([&"PlayersPlaced"])
	assert_array(decoded).is_equal(view.slice(0, view.size() - withheld.size()))


func test_an_error_outside_a_row_is_only_logged() -> void:
	_h = Harness.new()
	assert_bool(_h.welcome_all()).is_true()
	_h.own.force_role(NetTransport.HOST_ID, "no_such_role")
	_h.pump_frames(4)
	assert_bool(_h.session.is_running()).is_true()
	assert_str("\n".join(_h.session.game.diagnostics)).contains("no_such_role")
