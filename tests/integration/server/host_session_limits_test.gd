extends GdUnitTestSuite
## HostSession's limits (ARCHITECTURE §4.5 "Rate limits and malformed packets", E7, E17): a looping
## client dropped over its budget but never disconnected, voice that never starves a SetReady, the
## disconnect after 50 malformed messages in 10 s, peer 1's exemptions, and debug kinds from peer
## 1 only.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const SET_READY := 2
## SetReady with seq 1 and a bool of 7: the codec rejects it.
const BAD_SET_READY := [1, 0, 0, 0, 7]

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_looping_client_is_dropped_over_its_budget_but_never_disconnected() -> void:
	_h = Harness.new()
	var looping := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	var seconds := 20
	var frames := ceili(seconds * Harness.SECOND / float(Harness.FRAME_USEC))
	for i in frames:
		looping.send_intent(Intents.SET_READY, {"ready": i % 2 == 0})
		_h.pump()
	assert_bool(looping.is_ended()).is_false()
	assert_bool(_h.transport.peers().has(2)).is_true()
	assert_int(_h.session.over_budget).is_greater(0)
	var logged := 0
	for command: MatchCommand in _h.session.game.command_log.commands:
		if command.kind == Intents.SET_READY and command.peer == 2:
			logged += 1
	# Its bucket and what refilled it, never one per frame.
	var most := int(PeerBudget.INTENTS + PeerBudget.INTENTS_PER_SECOND * (seconds + 1))
	assert_int(logged).is_less_equal(most)
	assert_int(logged + _h.session.over_budget).is_equal(frames)
	assert_int(_h.transport.rejects.of_reason(NetRejects.Reason.OVER_BUDGET)).is_equal(
		_h.session.over_budget
	)


func test_talking_at_a_high_bitrate_never_starves_set_ready() -> void:
	_h = Harness.new()
	var talker := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	var frame := PackedByteArray()
	frame.resize(WireSchema.MAX_OPUS)
	for _i in 600:
		for _j in 20:
			talker.send_voice(frame)
		_h.pump()
	assert_int(_h.session.over_budget).is_greater(0)
	talker.send_intent(Intents.SET_READY, {"ready": true})
	_h.pump_frames(3)
	assert_bool(_h.session.game.state.player(2).ready).is_true()
	assert_array(talker.view.events_named(&"Rejected")).is_empty()


func test_fifty_malformed_messages_in_ten_seconds_disconnect_the_peer() -> void:
	_h = Harness.new()
	var broken := _h.raw()
	_h.pump()
	broken.hello(_h.session.content_hash)
	_h.pump_frames(3)
	# Half rejected by the codec, half by the transport (a truncated frame), one under the limit.
	for i in HostSession.MALFORMED_LIMIT - 1:
		if i % 2 == 0:
			broken.send_bytes(SET_READY, PackedByteArray(BAD_SET_READY))
		else:
			_h.transport._push_packet(
				2, PackedByteArray([SET_READY, 9]), NetKindTable.Lane.RELIABLE
			)
		_h.pump()
	assert_bool(broken.lost).is_false()
	assert_int(_h.session.bad_payloads).is_equal(25)
	broken.send_bytes(SET_READY, PackedByteArray(BAD_SET_READY))
	_h.pump_frames(2)
	assert_bool(broken.lost).is_true()
	assert_int(_h.session.malformed_disconnects).is_equal(1)
	assert_bool(_h.session.is_running()).is_true()
	assert_int(_h.transport.rejects.of_reason(NetRejects.Reason.BAD_PAYLOAD)).is_equal(26)
	# A Rejected from core/ is a rule's answer, never malformed: the session counted none here.
	assert_array(_h.session.game.view_of(2).events_named(&"Rejected")).is_empty()


func test_malformed_messages_spread_over_more_than_ten_seconds_are_tolerated() -> void:
	_h = Harness.new()
	var broken := _h.raw()
	_h.pump()
	broken.hello(_h.session.content_hash)
	_h.pump_frames(3)
	for _round in 2:
		for _i in HostSession.MALFORMED_LIMIT - 1:
			broken.send_bytes(SET_READY, PackedByteArray(BAD_SET_READY))
		_h.pump()
		_h.pump_seconds(10.1)
	assert_bool(broken.lost).is_false()
	assert_int(_h.session.bad_payloads).is_equal(2 * (HostSession.MALFORMED_LIMIT - 1))


func test_a_core_rejected_is_not_malformed() -> void:
	_h = Harness.new()
	var eager := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	# LoadAck in the lobby: Rejected(not_accepted) every time, never a disconnect.
	for _i in HostSession.MALFORMED_LIMIT + 10:
		eager.send_intent(Intents.LOAD_ACK, {"match_id": 0})
		_h.pump()
	assert_int(eager.view.events_named(&"Rejected").size()).is_equal(
		HostSession.MALFORMED_LIMIT + 10
	)
	assert_bool(eager.is_ended()).is_false()
	assert_int(_h.session.malformed_disconnects).is_equal(0)


func test_peer_one_is_exempt_from_the_budgets() -> void:
	_h = Harness.new()
	assert_bool(_h.welcome_all()).is_true()
	for i in 300:
		_h.own.send_intent(Intents.SET_READY, {"ready": i % 2 == 0})
	_h.pump_frames(3)
	assert_int(_h.session.over_budget).is_equal(0)
	var logged := 0
	for command: MatchCommand in _h.session.game.command_log.commands:
		if command.kind == Intents.SET_READY:
			logged += 1
	assert_int(logged).is_equal(300)


func test_a_malformed_own_client_ends_the_session_and_is_never_disconnected() -> void:
	_h = Harness.new()
	assert_bool(_h.welcome_all()).is_true()
	var own_transport := _h.session.own_client
	for _i in HostSession.MALFORMED_LIMIT - 1:
		own_transport.send(1, SET_READY, PackedByteArray(BAD_SET_READY))
	_h.pump()
	assert_bool(_h.session.is_running()).is_true()
	own_transport.send(1, SET_READY, PackedByteArray(BAD_SET_READY))
	_h.pump()
	assert_bool(_h.session.is_running()).is_false()
	assert_str(String(_h.session.end_reason)).is_equal(String(HostSession.OWN_CLIENT_MALFORMED))
	assert_str("; ".join(_h.session.errors)).contains("peer 1")
	assert_int(_h.session.malformed_disconnects).is_equal(0)


func test_a_debug_kind_is_taken_from_peer_one_only() -> void:
	_h = Harness.new()
	var other := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	other.force_role(2, "dissident")
	_h.pump_frames(3)
	assert_int(_h.session.bad_payloads).is_equal(1)
	assert_array(_forced()).is_empty()
	_h.own.force_role(2, "dissident")
	_h.pump_frames(3)
	# The command names the player the message names, and comes from peer 1's message.
	assert_array(_forced()).is_equal(["ForceRole 2 dissident"])
	assert_int(_h.session.bad_payloads).is_equal(1)


func test_a_force_clock_is_taken_from_peer_one_only() -> void:
	# The second debug kind (M4-3) takes the same path as ForceRole: refused from another peer.
	_h = Harness.new()
	var other := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	other.force_clock(2, 40)
	_h.pump_frames(3)
	assert_int(_h.session.bad_payloads).is_equal(1)
	assert_array(_forced()).is_empty()
	_h.own.force_clock(1, 40)
	_h.pump_frames(3)
	assert_array(_forced()).is_equal(["ForceClock 1 40"])
	assert_int(_h.session.game.state.forced_clock_s).is_equal(40)
	assert_int(_h.session.bad_payloads).is_equal(1)


func test_a_release_host_neither_decodes_nor_takes_a_debug_kind() -> void:
	_h = Harness.new(null, true, WireSchema.game(false))
	var debug_client := _h.raw()
	_h.pump()
	debug_client.hello(_h.session.content_hash)
	_h.pump_frames(3)
	var force := WireMessage.new(&"ForceRole", {"role": "dissident"}, 1, 2)
	assert_int(debug_client.send(force)).is_equal(OK)
	_h.pump_frames(3)
	assert_int(_h.transport.rejects.of_reason(NetRejects.Reason.UNKNOWN_KIND)).is_equal(1)
	assert_array(_forced()).is_empty()
	# Its own client cannot even send one: the release table has no such kind.
	assert_int(_h.own.force_role(1, "dissident")).is_equal(-1)


func _forced() -> Array[String]:
	var found: Array[String] = []
	for command: MatchCommand in _h.session.game.command_log.commands:
		if command.kind == Intents.FORCE_ROLE:
			found.append("ForceRole %d %s" % [command.peer, command.get_string("role")])
		elif command.kind == Intents.FORCE_CLOCK:
			found.append("ForceClock %d %d" % [command.peer, command.get_int("seconds", -1)])
	return found
