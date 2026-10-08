extends GdUnitTestSuite
## ClientSession against HostSession over a LoopbackHub (ARCHITECTURE §4.6; 3g's handoff on #101):
## a whole Lobby, Countdown, Loading, Round, End, Lobby cycle with claims accepted and stopping in
## Loading and End, LoadAck accepted, a Correction adopted and the next claim accepted, and what
## each client decoded compared with view_of. The Hello handshake, wrong_content and joins_closed
## are in host_session_test.gd, the voice in host_session_voice_test.gd.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_whole_cycle_from_lobby_back_to_lobby() -> void:
	_h = Harness.new()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(0.5)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"countdown", 10)).is_true()
	assert_bool(_h.run_until_phase(&"loading", 400)).is_true()
	# Both acknowledge LoadMatch (bots: without loading), and LoadingPhase takes both; the pregame
	# runs its 3 s (#213).
	assert_bool(_h.run_until_phase(&"pregame", 20)).is_true()
	assert_bool(_h.run_until_phase(&"round", 200)).is_true()
	for client: ClientSession in _h.clients:
		var loaded := client.view.events_named(&"PlayerLoaded")
		assert_int(loaded.size()).is_equal(2)
	_h.pump_seconds(1)
	_h.session.game.state.add_to_counter(0, &"crew_win", 1)
	assert_bool(_h.run_until_phase(&"end", 3)).is_true()
	_h.session.game.state.set_counter(0, &"crew_win", 0)
	# The counter is checked on the next call, a claim's: the claims in flight at the change are
	# applied in End (and dropped, E15); the clients send none after it.
	var in_flight: int = _h.claims_in.get(&"end", 0)
	assert_int(in_flight).is_less_equal(_h.clients.size())
	_h.pump_seconds(1)
	assert_int(_h.claims_in.get(&"end", 0)).is_equal(in_flight)
	_h.own.send_intent(Intents.RETURN_TO_LOBBY)
	assert_bool(_h.run_until_phase(&"lobby", 6)).is_true()
	_h.pump_seconds(1)
	# Claims in every phase that takes them, none in Loading and Pregame.
	for phase: StringName in [&"lobby", &"countdown", &"round"]:
		assert_int(_h.claims_in.get(phase, 0)).is_greater(0)
	assert_int(_h.claims_in.get(&"loading", 0)).is_equal(0)
	assert_int(_h.claims_in.get(&"pregame", 0)).is_equal(0)
	assert_str(second.model.phase).is_equal("lobby")
	# Each placement (into the round, back into the lobby) is a Correction the client adopts; the
	# claims after it pass, so there is no other.
	for client: ClientSession in _h.clients:
		assert_int(client.view.events_named(&"Correction").size()).is_equal(2)
		assert_array(client.view.events_named(&"Rejected")).is_empty()
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(Array(_h.session.game.diagnostics)).is_empty()


func test_a_correction_is_adopted_and_the_next_claim_passes() -> void:
	_h = Harness.new()
	var jumper := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(6)
	var spot := _h.session.game.state.player(2).position
	jumper.set_motion(spot + Vector3(50, 0, 0), Vector3.ZERO, Vector3.FORWARD, false, true, true)
	var corrected := func() -> bool: return not jumper.view.events_named(&"Correction").is_empty()
	assert_bool(_h.pump_until(corrected, 10)).is_true()
	var correction := jumper.view.events_named(&"Correction")[0]
	assert_vector(correction.fields["position"] as Vector3).is_equal(spot)
	# It adopted the host's position and epoch: its claims from there pass, with a small step.
	jumper.set_motion(spot + Vector3(0.05, 0, 0), Vector3.ZERO, Vector3.FORWARD, false, true, true)
	_h.pump_seconds(1)
	assert_int(jumper.view.events_named(&"Correction").size()).is_equal(1)
	assert_int(jumper.model.epoch).is_equal(correction.fields["epoch"] as int)
	assert_vector(_h.session.game.state.player(2).position).is_equal(spot + Vector3(0.05, 0, 0))
	assert_array(_h.mismatches(jumper)).is_empty()


func test_what_each_client_decoded_is_its_view_of() -> void:
	_h = Harness.new()
	var second := _h.join()
	var third := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	second.send_intent(Intents.SET_READY, {"ready": true})
	_h.own.send_intent(Intents.CHANGE_SETTINGS, {"settings": {&"knives": 3}})
	third.send_voice(PackedByteArray([3, 3]))
	second.send_voice(PackedByteArray([2]))
	_h.pump_seconds(1)
	third.leave()
	_h.pump_seconds(1)
	for client: ClientSession in [_h.own, second]:
		assert_array(client.view.event_names()).is_not_empty()
		assert_array(client.view.snapshots.keys()).is_not_empty()
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(_h.voice_of(_h.own)).is_not_empty()
	# A peer that left decoded a prefix of its view.
	var left := _h.session.game.view_of(3)
	assert_int(third.view.events.size()).is_less_equal(left.events.size())
