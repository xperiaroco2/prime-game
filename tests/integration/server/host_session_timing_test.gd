extends GdUnitTestSuite
## HostSession's clock (ARCHITECTURE §4.5 "One step"): a host freeze whose waiting claims pass,
## commands queued before a freeze stamped at the next tick, and a client's backlog after its own
## freeze. A freeze is a jump of the fake clock (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
## 1 m/s, well under the fixture's walk speed.
const PACE := Vector3(1, 0, 0)

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_five_second_host_freeze_lets_the_waiting_claims_pass() -> void:
	_h = Harness.new()
	var walker := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	var at := walker.view.events_named(&"Welcome")[0].fields["spot"] as Vector3
	_h.pump_frames(6)
	# The walker keeps walking and claiming while the host is frozen for 5 s; its claims wait in
	# the host's socket, and the newest one is applied after the catch-up.
	var frames := ceili(5.0 * Harness.SECOND / Harness.FRAME_USEC)
	for _i in frames:
		at += PACE * Harness.FRAME_USEC / Harness.SECOND
		walker.set_motion(at, PACE, Vector3.FORWARD, false, true, true)
		_h.now += Harness.FRAME_USEC
		walker.step(_h.now)
		_h.own.step(_h.now)
	_h.pump()
	assert_int(_h.session.game.ticked_through()).is_equal(_h.session.tick_of(_h.now))
	assert_array(walker.view.events_named(&"Correction")).is_empty()
	# Where its newest claim put it: a claim goes once per client tick, up to 3 frames before.
	var accepted := _h.session.game.state.player(2).position
	assert_float(accepted.distance_to(at)).is_less(0.06)
	assert_array(_h.mismatches(walker)).is_empty()


func test_commands_queued_before_a_freeze_are_stamped_with_the_next_tick() -> void:
	_h = Harness.new()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.settle_after_tick()
	var last := _h.session.game.ticked_through()
	second.send_intent(Intents.SET_READY, {"ready": true})
	# The host reads it in a step with no tick due: it waits in the queue.
	_h.now += Harness.FRAME_USEC
	_h.session.step(_h.now)
	assert_int(_h.session.game.ticked_through()).is_equal(last)
	assert_object(_ready_command(2)).is_null()
	# Then a 5 s freeze: it is applied on the tick after the last one run, before the catch-up.
	_h.now += 5 * Harness.SECOND
	_h.session.step(_h.now)
	var applied := _ready_command(2)
	assert_object(applied).is_not_null()
	assert_int(applied.tick).is_equal(last + 1)
	assert_int(_h.session.game.ticked_through()).is_equal(_h.session.tick_of(_h.now))
	assert_bool(_h.session.game.state.player(2).ready).is_true()


func test_commands_read_on_a_due_tick_are_stamped_with_it() -> void:
	_h = Harness.new()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.settle_after_tick()
	second.send_intent(Intents.SET_READY, {"ready": true})
	_h.now += 3 * Harness.SECOND
	_h.session.step(_h.now)
	assert_int(_ready_command(2).tick).is_equal(_h.session.tick_of(_h.now))


func test_a_client_s_freeze_backlog_passes_its_budget_and_relays_only_the_newest_voice() -> void:
	_h = Harness.new()
	var thawed := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(6)
	_h.frozen.append(thawed)
	_h.pump_seconds(5)
	_h.frozen.clear()
	# On the thaw it sends 5 s of voice, a ready flag and one claim covering the freeze.
	var heard_before := _h.voice_of(_h.own).size()
	for i in 250:
		thawed.send_voice(PackedByteArray([i & 0xFF, 2]))
	thawed.send_intent(Intents.SET_READY, {"ready": true})
	_h.pump_frames(3)
	assert_int(_h.session.over_budget).is_equal(0)
	assert_bool(_h.session.game.state.player(2).ready).is_true()
	assert_int(_h.session.voice_dropped()).is_equal(250 - VoiceRelay.NEWEST_PER_POLL)
	var heard := _h.voice_of(_h.own).slice(heard_before)
	assert_int(heard.size()).is_equal(VoiceRelay.NEWEST_PER_POLL)
	for i in VoiceRelay.NEWEST_PER_POLL:
		assert_str(heard[i]).ends_with("%02x02" % (245 + i))
	assert_array(thawed.view.events_named(&"Correction")).is_empty()


func _ready_command(peer: int) -> MatchCommand:
	for command: MatchCommand in _h.session.game.command_log.commands:
		if command.kind == Intents.SET_READY and command.peer == peer:
			return command
	return null
