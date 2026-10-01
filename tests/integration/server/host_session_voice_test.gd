extends GdUnitTestSuite
## HostSession's voice relay and reused peer ids (ARCHITECTURE §4.5 "Voice relay", "One outbox
## slice per call"): VoiceUp relayed as VoiceDown along speakers_for only, no relay under Round's
## routing after a catch-up into End, nothing from a peer that is not a player, and a leave and a
## join with one peer id between two ticks, for events and voice.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_voice_goes_only_along_speakers_for() -> void:
	# Lobby markers 2 m apart, heard within 3 m: 1 and 2 hear each other, 2 and 3 too, 1 and 3 not.
	_h = Harness.new()
	var second := _h.join()
	var third := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(3)
	var tick := _h.session.game.ticked_through()
	_h.own.send_voice(PackedByteArray([1, 1]))
	second.send_voice(PackedByteArray([2, 2, 2]))
	third.send_voice(PackedByteArray([3]))
	_h.pump()
	assert_array(_h.voice_of(_h.own)).is_equal(["2:%d:020202" % tick])
	assert_array(_h.voice_of(second)).is_equal(["1:%d:0101" % tick, "3:%d:03" % tick])
	assert_array(_h.voice_of(third)).is_equal(["2:%d:020202" % tick])
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()


func test_voice_from_a_peer_that_is_not_a_player_goes_nowhere() -> void:
	_h = Harness.new()
	var second := _h.join()
	var lurker := _h.raw()
	assert_bool(_h.welcome_all()).is_true()
	lurker.send(WireMessage.new(&"VoiceUp", {"seq": 0, "opus": PackedByteArray([9])}))
	_h.pump_frames(3)
	assert_array(_h.voice_of(_h.own)).is_empty()
	assert_array(_h.voice_of(second)).is_empty()
	assert_array(lurker.received).is_empty()


func test_a_catch_up_from_round_into_end_relays_no_voice_under_round_s_routing() -> void:
	_h = Harness.new()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 400)).is_true()
	_h.pump_frames(3)
	second.send_voice(PackedByteArray([5]))
	_h.pump()
	assert_int(_h.voice_of(_h.own).size()).is_equal(1)
	# The crew wins on the next tick; the host is frozen meanwhile, and the speaker talks on.
	_h.session.game.state.add_to_counter(0, &"crew_win", 1)
	_h.freeze_host(1.0)
	second.send_voice(PackedByteArray([6]))
	_h.pump()
	assert_str(String(_h.session.game.phase_id())).is_equal("end")
	assert_int(_h.voice_of(_h.own).size()).is_equal(1)
	assert_array(_h.mismatches(_h.own)).is_empty()


func test_a_leave_and_a_join_with_one_peer_id_between_two_ticks() -> void:
	_h = Harness.new()
	var leaver := _h.join()
	var third := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.settle_after_tick()
	var tick := _h.session.game.ticked_through()
	# Frame 1, no tick due: peer 3 readies (ReadyChanged goes to every player, peer 2 included),
	# then peer 2 leaves.
	third.send_intent(Intents.SET_READY, {"ready": true})
	leaver.leave()
	_h.pump()
	# Frame 2, no tick due: a new connection takes id 2 and talks; peer 3 talks, which the old
	# peer 2 could hear (2 m away).
	var taker := _h.raw_as(2)
	taker.poll()
	assert_int(taker.peer).is_equal(2)
	taker.send(WireMessage.new(&"VoiceUp", {"seq": 0, "opus": PackedByteArray([7])}))
	third.send_voice(PackedByteArray([3]))
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(tick)
	# Frame 3: the tick applies ReadyChanged, PeerLeft(2), then PeerConnected(2).
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(tick + 1)
	_h.pump_frames(3)
	# The new peer 2 got nothing meant for the old one, and nobody heard it as the old one.
	assert_array(taker.received).is_empty()
	assert_bool(taker.lost).is_false()
	assert_array(_h.voice_of(_h.own)).is_empty()
	assert_array(_h.voice_of(third)).is_empty()
	assert_array(third.view.event_names()).contains([&"ReadyChanged", &"PlayerLeft"])
	assert_bool(_h.session.game.state.newcomers.has(2)).is_true()
	assert_array(_h.mismatches(_h.own)).is_empty()
	assert_array(_h.mismatches(third)).is_empty()
	# And as a newcomer it may join.
	taker.hello(_h.session.content_hash)
	_h.pump_frames(3)
	assert_array(taker.names()).contains([&"Welcome"])


func test_a_refused_hello_of_a_peer_that_left_spares_the_one_that_took_its_id() -> void:
	_h = Harness.new()
	var leaver := _h.raw()
	_h.pump()
	_h.settle_after_tick()
	var tick := _h.session.game.ticked_through()
	# Frame 1, no tick due: peer 2 says Hello with the wrong content and leaves.
	leaver.hello(_h.session.content_hash + 1)
	leaver.transport.close()
	_h.pump()
	# Frame 2, no tick due: a new connection takes id 2.
	var taker := _h.raw_as(2)
	taker.poll()
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(tick)
	# Frame 3: the tick refuses the old Hello (Rejected, DisconnectPeer 2), then PeerLeft(2) and
	# PeerConnected(2). The DisconnectPeer is about the old connection: the new one stays.
	_h.pump_frames(3)
	assert_int(_h.session.game.ticked_through()).is_greater(tick)
	assert_array(FixtureBaseMode.directives(_h.session.game)).contains(["DisconnectPeer 2"])
	assert_bool(taker.lost).is_false()
	assert_array(taker.received).is_empty()
	taker.hello(_h.session.content_hash)
	_h.pump_frames(3)
	assert_array(taker.names().slice(0, 1)).is_equal([&"Welcome"])
	assert_bool(taker.lost).is_false()
