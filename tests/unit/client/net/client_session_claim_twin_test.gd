extends GdUnitTestSuite
## ClientSession's RELIABLE claims (#429, the engineer's A1 + B3 on PR #434; ARCHITECTURE §4.3,
## §4.6, §7.1): the first claim of every epoch it adopts (the Welcome, a placement, a Correction)
## goes on MoveClaimReliable, and right before a player action it resends its last claim, exactly
## as sent, on the twin: once per claim, never a claim of an older epoch, never before a session
## control, never where it sends no claims. A resend is not a claim: claim_sent does not fire for
## it, and the claims after it are the ones a run without the action sends.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
## One client tick at 20 Hz, in microseconds.
const TICK_USEC := 50000

var _harness: Harness
## claim_sent as it fired: [epoch, tick, covered].
var _told: Array[Array] = []


func before_test() -> void:
	_harness = Harness.new()
	_told.clear()
	_harness.session.claim_sent.connect(_on_claim_sent)


func after_test() -> void:
	_harness.close()


func test_the_first_claim_of_every_epoch_goes_on_the_reliable_twin() -> void:
	_harness.welcome(&"lobby", 1)
	_harness.pump(TICK_USEC)
	_harness.pump(TICK_USEC)
	assert_array(_names()).contains_exactly(
		[WireSchema.RELIABLE_CLAIM, Intents.MOVE_CLAIM, Intents.MOVE_CLAIM]
	)
	# A refused claim's Correction: a new epoch, whose first claim goes on the twin again.
	_harness.send(CorrectionEvent.new(_harness.peer, 2, Vector3(3, 0, 3), Vector3.ZERO))
	_harness.pump(TICK_USEC)
	_harness.pump(TICK_USEC)
	# A placement: the event, then its Correction.
	var spots: Dictionary[int, Vector3] = {_harness.peer: Vector3(7, 0, 7)}
	_harness.send(PlayersPlacedEvent.new(spots))
	_harness.send(CorrectionEvent.new(_harness.peer, 3, Vector3(7, 0, 7), Vector3.ZERO))
	_harness.pump(TICK_USEC)
	_harness.pump(TICK_USEC)
	var claims := _harness.claims()
	var expected: Array[StringName] = [
		WireSchema.RELIABLE_CLAIM,
		Intents.MOVE_CLAIM,
		Intents.MOVE_CLAIM,
		WireSchema.RELIABLE_CLAIM,
		Intents.MOVE_CLAIM,
		WireSchema.RELIABLE_CLAIM,
		Intents.MOVE_CLAIM,
	]
	assert_array(_names()).contains_exactly(expected)
	assert_array(_epochs(claims)).contains_exactly([1, 1, 1, 2, 2, 3, 3])
	assert_array(_harness.resends()).is_empty()
	# One claim_sent per claim, whichever row carried it; the placement's first covers one tick.
	assert_int(_told.size()).is_equal(claims.size())
	assert_int(_told[-2][2] as int).is_equal(1)
	assert_int(_harness.session.placements).is_equal(1)


func test_a_player_action_resends_the_last_claim_right_before_it() -> void:
	_harness.welcome(&"lobby", 1)
	_harness.session.set_motion(Vector3(2, 0, 2), Vector3.ONE, Vector3.LEFT, true, true, true)
	_harness.pump(TICK_USEC)
	var told := _told.size()
	var seq := _harness.session.send_intent(Intents.PICK_UP, {"item": 4})
	assert_int(seq).is_greater(0)
	_harness.deliver()
	var last := _harness.sent.slice(-3)
	assert_array(_names_of(last)).contains_exactly(
		[Intents.MOVE_CLAIM, WireSchema.RELIABLE_CLAIM, Intents.PICK_UP]
	)
	assert_dict(last[1].fields).is_equal(last[0].fields)
	assert_int(last[2].seq).is_equal(seq)
	assert_array(_harness.resends()).contains_exactly([last[1]])
	assert_int(_told.size()).is_equal(told)
	# The next claim goes on as if no action had been sent: the next tick, covering one tick.
	_harness.pump(TICK_USEC)
	var next := _harness.claims()[-1]
	assert_str(str(next.name)).is_equal(str(Intents.MOVE_CLAIM))
	var expected_tick: int = last[0].fields["client_tick"] + 1
	assert_int(next.fields["client_tick"] as int).is_equal(expected_tick)
	assert_int(_told[-1][2] as int).is_equal(1)
	assert_int(_told.size()).is_equal(told + 1)


func test_a_throw_resends_the_last_claim_right_before_it() -> void:
	# §7.1.16: the host launches from the last accepted position, so a lost claim would throw
	# from a step behind; the twin carries it on the reliable lane just ahead of the Throw.
	_harness.welcome(&"round", 1)
	_harness.session.set_motion(Vector3(3, 0, -1), Vector3.ONE, Vector3.LEFT, true, true, true)
	_harness.pump(TICK_USEC)
	var told := _told.size()
	var facing := Vector3(0.0, 0.5, -0.75)
	var seq := _harness.session.send_intent(Intents.THROW, {"facing": facing})
	assert_int(seq).is_greater(0)
	_harness.deliver()
	var last := _harness.sent.slice(-3)
	assert_array(_names_of(last)).contains_exactly(
		[Intents.MOVE_CLAIM, WireSchema.RELIABLE_CLAIM, Intents.THROW]
	)
	assert_dict(last[1].fields).is_equal(last[0].fields)
	assert_int(last[2].seq).is_equal(seq)
	assert_bool(last[2].fields["facing"] == facing).is_true()
	assert_array(_harness.resends()).contains_exactly([last[1]])
	assert_int(_told.size()).is_equal(told)


func test_every_player_action_resends_and_a_session_control_does_not() -> void:
	var controls := {
		Intents.SET_READY: {"ready": true},
		Intents.CHANGE_SETTINGS: {"settings": {}},
		Intents.RETURN_TO_LOBBY: {},
		Intents.LOAD_ACK: {"match_id": 1},
	}
	var actions := {
		Intents.PICK_UP: {"item": 0},
		Intents.PUT_DOWN: {"facing": Vector3.FORWARD},
		Intents.USE: {"facing": Vector3.FORWARD},
		Intents.RAISE: {"target": 1},
		Intents.STOP_RAISE: {},
		Intents.GIVE_UP: {},
		Intents.SWAP: {},
		Intents.THROW: {"facing": Vector3.FORWARD},
	}
	_harness.welcome(&"lobby", 1)
	for intent: StringName in controls:
		_harness.pump(TICK_USEC)
		assert_int(_harness.session.send_intent(intent, controls[intent] as Dictionary)).is_greater(
			0
		)
		_harness.deliver()
		assert_str(str(_harness.sent[-2].name)).override_failure_message(str(intent)).is_equal(
			str(Intents.MOVE_CLAIM)
		)
	assert_array(_harness.resends()).is_empty()
	for intent: StringName in actions:
		_harness.pump(TICK_USEC)
		assert_int(_harness.session.send_intent(intent, actions[intent] as Dictionary)).is_greater(
			0
		)
		_harness.deliver()
		assert_str(str(_harness.sent[-2].name)).override_failure_message(str(intent)).is_equal(
			str(WireSchema.RELIABLE_CLAIM)
		)
	assert_int(_harness.resends().size()).is_equal(actions.size())


func test_two_actions_after_one_claim_resend_it_once() -> void:
	_harness.welcome(&"lobby", 1)
	_harness.pump(TICK_USEC)
	_harness.session.send_intent(Intents.PICK_UP, {"item": 0})
	_harness.session.send_intent(Intents.USE, {"facing": Vector3.FORWARD})
	_harness.deliver()
	assert_array(_names_of(_harness.sent.slice(-4))).contains_exactly(
		[Intents.MOVE_CLAIM, WireSchema.RELIABLE_CLAIM, Intents.PICK_UP, Intents.USE]
	)
	# A new claim, then an action: resent again.
	_harness.pump(TICK_USEC)
	_harness.session.send_intent(Intents.SWAP)
	_harness.deliver()
	assert_int(_harness.resends().size()).is_equal(2)


func test_no_resend_when_the_last_claim_went_on_the_twin() -> void:
	_harness.welcome(&"lobby", 1)
	_harness.session.send_intent(Intents.PICK_UP, {"item": 0})
	_harness.deliver()
	assert_array(_names_of(_harness.sent.slice(-2))).contains_exactly(
		[WireSchema.RELIABLE_CLAIM, Intents.PICK_UP]
	)
	assert_array(_harness.resends()).is_empty()


func test_no_resend_of_an_older_epochs_claim() -> void:
	_harness.welcome(&"lobby", 1)
	_harness.pump(TICK_USEC)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, Vector3(3, 0, 3), Vector3.ZERO))
	_harness.deliver()
	assert_int(_harness.session.model.epoch).is_equal(2)
	_harness.session.send_intent(Intents.PICK_UP, {"item": 0})
	_harness.deliver()
	assert_array(_names_of(_harness.sent.slice(-2))).contains_exactly(
		[Intents.MOVE_CLAIM, Intents.PICK_UP]
	)
	assert_array(_harness.resends()).is_empty()


func test_no_resend_where_it_sends_no_claims() -> void:
	_harness.welcome(&"countdown", 1)
	_harness.pump(TICK_USEC)
	_harness.send(PhaseChangedEvent.new(&"loading", -1))
	_harness.deliver()
	assert_bool(_harness.session.claims_accepted()).is_false()
	_harness.session.send_intent(Intents.PICK_UP, {"item": 0})
	_harness.deliver()
	assert_array(_names_of(_harness.sent.slice(-2))).contains_exactly(
		[Intents.MOVE_CLAIM, Intents.PICK_UP]
	)
	assert_array(_harness.resends()).is_empty()


func _names() -> Array[StringName]:
	return _names_of(_harness.claims())


func _names_of(messages: Array[WireMessage]) -> Array[StringName]:
	var found: Array[StringName] = []
	for message: WireMessage in messages:
		found.append(message.name)
	return found


func _epochs(messages: Array[WireMessage]) -> Array[int]:
	var found: Array[int] = []
	for message: WireMessage in messages:
		found.append(message.fields["epoch"] as int)
	return found


func _on_claim_sent(epoch: int, tick: int, covered: int, _sprint: bool, _moved: bool) -> void:
	_told.append([epoch, tick, covered])
