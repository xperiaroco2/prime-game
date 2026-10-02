extends GdUnitTestSuite
## ClientSession's MoveClaims (ARCHITECTURE §4.3, E2): one per client tick (20 Hz of its own clock)
## with its epoch, the client tick and the jumps counted in that epoch, reset at each new epoch; a
## Correction's position adopted; none before Welcome, and none in a phase whose allowlist (the
## client's own copy of the mode) does not accept MoveClaim from it. A claim reports the sprint
## state and the movement input if any step since the last claim had them (#155), its masks repeat
## them for each of the last 32 client ticks, and claim_sent tells its epoch and tick, the ticks it
## covers, its flags and whether it moved, as the host's stamina counts them.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
## One client tick at 20 Hz, in microseconds.
const TICK_USEC := 50000

var _harness: Harness


func before_test() -> void:
	_harness = Harness.new()


func after_test() -> void:
	_harness.close()


func test_no_claim_before_welcome() -> void:
	for i in 10:
		_harness.pump()
	assert_array(_harness.sent_named(Intents.MOVE_CLAIM)).is_empty()


func test_one_claim_per_client_tick_with_a_rising_client_tick() -> void:
	_harness.welcome(&"lobby", 4)
	var first := _harness.sent_named(Intents.MOVE_CLAIM).size()
	# 60 frames of 1/60 s: one second, 20 client ticks.
	for i in 60:
		_harness.pump()
	var claims := _harness.sent_named(Intents.MOVE_CLAIM)
	assert_int(claims.size() - first).is_between(19, 21)
	for i in range(1, claims.size()):
		var step: int = claims[i].fields["client_tick"] - claims[i - 1].fields["client_tick"]
		assert_int(step).is_equal(1)
	for claim: WireMessage in claims:
		assert_int(claim.fields["epoch"] as int).is_equal(4)


func test_after_a_freeze_one_claim_carries_the_newest_client_tick() -> void:
	_harness.welcome()
	_harness.pump()
	var before := _harness.sent_named(Intents.MOVE_CLAIM)
	var last_tick: int = before[-1].fields["client_tick"]
	# A 5 s freeze of this client's main thread: one step covers it.
	_harness.pump(5000000)
	var claims := _harness.sent_named(Intents.MOVE_CLAIM)
	assert_int(claims.size()).is_equal(before.size() + 1)
	assert_int(claims[-1].fields["client_tick"] as int).is_equal(last_tick + 100)


func test_the_claim_carries_the_movers_motion() -> void:
	_harness.welcome()
	var at := Vector3(1.5, 0.25, -3)
	_harness.session.set_motion(at, Vector3(4, 0, 0), Vector3.RIGHT, true, true, false)
	_harness.pump(TICK_USEC)
	var claim := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	assert_vector(claim["position"] as Vector3).is_equal(at)
	assert_vector(claim["velocity"] as Vector3).is_equal(Vector3(4, 0, 0))
	assert_vector(claim["facing"] as Vector3).is_equal(Vector3.RIGHT)
	assert_bool(claim["sprint"] as bool).is_true()
	assert_bool(claim["moving"] as bool).is_true()
	assert_bool(claim["on_floor"] as bool).is_false()


func test_the_first_claims_start_at_the_welcome_spot() -> void:
	var welcome := _harness.welcome()
	var claim := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	assert_vector(claim["position"] as Vector3).is_equal(welcome.spot)
	assert_int(claim["jumps"] as int).is_equal(0)


func test_jumps_count_up_within_an_epoch_and_reset_at_a_correction() -> void:
	_harness.welcome(&"lobby", 1)
	_harness.session.count_jump()
	_harness.pump(TICK_USEC)
	_harness.session.count_jump()
	_harness.session.count_jump()
	_harness.pump(TICK_USEC)
	var claims := _harness.sent_named(Intents.MOVE_CLAIM)
	assert_int(claims[-2].fields["jumps"] as int).is_equal(1)
	assert_int(claims[-1].fields["jumps"] as int).is_equal(3)
	var placed := Vector3(7, 1, 7)
	var moved: Array[Vector3] = []
	_harness.session.corrected.connect(
		func(position: Vector3, _velocity: Vector3) -> void: moved.append(position)
	)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, placed, Vector3(0, -1, 0)))
	_harness.pump(TICK_USEC)
	var after := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	assert_int(after["epoch"] as int).is_equal(2)
	assert_int(after["jumps"] as int).is_equal(0)
	assert_vector(after["position"] as Vector3).is_equal(placed)
	assert_vector(after["velocity"] as Vector3).is_equal(Vector3(0, -1, 0))
	assert_array(moved).contains_exactly([placed])
	assert_int(_harness.session.jumps()).is_equal(0)


func test_it_stops_claiming_where_the_phase_accepts_no_claim_and_resumes_after() -> void:
	_harness.welcome(&"countdown")
	_harness.pump(TICK_USEC)
	var in_countdown := _harness.sent_named(Intents.MOVE_CLAIM).size()
	assert_int(in_countdown).is_greater(0)
	_harness.send(PhaseChangedEvent.new(&"loading", -1))
	for i in 20:
		_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(in_countdown)
	_harness.send(PhaseChangedEvent.new(&"round", 12000))
	_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(in_countdown + 1)
	_harness.send(PhaseChangedEvent.new(&"end", -1))
	for i in 20:
		_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(in_countdown + 1)


func test_a_downed_player_claims_where_its_phase_accepts_the_downed_only() -> void:
	# The fixture's round accepts MoveClaim from living and downed players; its lobby from the
	# living only (FixtureBaseMode).
	var round_accepts := FixtureBaseMode.mode().find_phase(&"round").senders_of(Intents.MOVE_CLAIM)
	assert_int(round_accepts & AcceptSpec.From.DOWNED).is_not_equal(0)
	_harness.welcome(&"round")
	_harness.send(KnockedDownEvent.new(_harness.peer, Vector3(2, 0, 2)))
	_harness.pump(TICK_USEC)
	var as_downed := _harness.sent_named(Intents.MOVE_CLAIM).size()
	_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(as_downed + 1)
	assert_int(_harness.session.model.life_of(_harness.peer)).is_equal(ClientModel.Life.DOWNED)


func test_a_downed_player_in_a_phase_for_the_living_does_not_claim() -> void:
	var mode := FixtureBaseMode.mode()
	var lobby_accepts := mode.find_phase(&"lobby").senders_of(Intents.MOVE_CLAIM)
	assert_int(lobby_accepts & AcceptSpec.From.DOWNED).is_equal(0)
	_harness.welcome(&"lobby")
	# No mode knocks down in the lobby; a KnockedDown there still makes this client downed to its
	# own rules.
	_harness.send(KnockedDownEvent.new(_harness.peer, Vector3(2, 0, 2)))
	_harness.pump(TICK_USEC)
	var claims := _harness.sent_named(Intents.MOVE_CLAIM).size()
	for i in 5:
		_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(claims)


func test_a_dead_player_never_claims_even_where_every_player_may() -> void:
	# The dead send no intents (E25): a phase that takes MoveClaim from any player does not make a
	# dead client claim.
	_harness.mode.find_phase(&"round").accepts = [
		AcceptSpec.of(Intents.MOVE_CLAIM, AcceptSpec.From.PLAYER | AcceptSpec.From.HOST)
	]
	_harness.welcome(&"round")
	_harness.pump(TICK_USEC)
	var living := _harness.sent_named(Intents.MOVE_CLAIM).size()
	assert_int(living).is_greater(0)
	_harness.send(KnockedDownEvent.new(_harness.peer, Vector3(2, 0, 2)))
	_harness.pump(TICK_USEC)
	var downed := _harness.sent_named(Intents.MOVE_CLAIM).size()
	assert_int(downed).is_greater(living)
	_harness.send(DiedEvent.new(_harness.peer, Vector3(2, 0, 2)))
	for i in 5:
		_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(downed)
	assert_int(_harness.session.model.life_of(_harness.peer)).is_equal(ClientModel.Life.DEAD)


func test_the_host_flag_counts_for_the_hosts_own_client_only() -> void:
	# A lobby that takes MoveClaim from the host's own player only.
	var only_host := AcceptSpec.of(Intents.MOVE_CLAIM, AcceptSpec.From.HOST)
	_harness.mode.find_phase(&"lobby").accepts = [only_host]
	var own := ClientSession.new(
		LoopbackTransport.own_client_of(_harness.host), _harness.mode, _harness.schema
	)
	own.step(_harness.now)
	_harness.welcome(&"lobby")
	var own_welcome := WelcomeEvent.new(NetTransport.HOST_ID, Vector3.ZERO, 1)
	own_welcome.map = Harness.TINY_MAP
	own_welcome.phase = &"lobby"
	var payload := _harness.schema.encode(WireMessage.new(&"Welcome", own_welcome.to_dict()))
	_harness.host.send(NetTransport.HOST_ID, _harness.schema.kind_of(&"Welcome"), payload)
	for i in 3:
		_harness.now += TICK_USEC
		own.step(_harness.now)
		_harness.pump(TICK_USEC)
	var from_host := 0
	for claim: WireMessage in _harness.sent_named(Intents.MOVE_CLAIM):
		assert_int(claim.fields["epoch"] as int).is_equal(1)
		from_host += 1
	assert_bool(own.is_welcomed()).is_true()
	assert_int(from_host).is_between(2, 4)
	# The remote client (peer 2) sent none: every claim above came from peer 1.
	assert_int(_harness.claims_from(_harness.peer)).is_equal(0)
	assert_int(_harness.claims_from(NetTransport.HOST_ID)).is_equal(from_host)
	own.leave()


func test_a_claim_holds_exactly_the_fields_core_declares() -> void:
	_harness.welcome()
	var claim := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	var declared: Dictionary = Intents.FIELDS[Intents.MOVE_CLAIM]
	assert_array(claim.keys()).contains_exactly_in_any_order(declared.keys())
	for field: String in declared:
		assert_int(typeof(claim[field])).is_equal(declared[field] as int)


func test_a_claim_says_sprint_and_moving_if_any_step_since_the_last_claim_did() -> void:
	_harness.welcome()
	_harness.pump(TICK_USEC)
	var at := Vector3(1, 0, 2)
	# Three physics steps in one claim's tick: a sprint, a walk that let go of sprint, a stop.
	_harness.session.set_motion(
		at + Vector3(0.12, 0, 0), Vector3.ZERO, Vector3.RIGHT, true, true, true
	)
	_harness.session.set_motion(
		at + Vector3(0.2, 0, 0), Vector3.ZERO, Vector3.RIGHT, false, true, true
	)
	_harness.session.set_motion(
		at + Vector3(0.2, 0, 0), Vector3.ZERO, Vector3.RIGHT, false, false, true
	)
	_harness.pump(TICK_USEC)
	var claim := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	assert_bool(claim["sprint"] as bool).is_true()
	assert_bool(claim["moving"] as bool).is_true()
	assert_vector(claim["position"] as Vector3).is_equal(at + Vector3(0.2, 0, 0))
	# The next claim covers only the steps after it: standing still.
	_harness.session.set_motion(
		at + Vector3(0.2, 0, 0), Vector3.ZERO, Vector3.RIGHT, false, false, true
	)
	_harness.pump(TICK_USEC)
	var next := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	assert_bool(next["sprint"] as bool).is_false()
	assert_bool(next["moving"] as bool).is_false()


func test_claim_sent_tells_the_covered_ticks_the_flags_and_whether_it_moved() -> void:
	var told: Array[Array] = []
	_harness.session.claim_sent.connect(
		func(epoch: int, tick: int, covered: int, sprint: bool, moved: bool) -> void:
			told.append([covered, sprint, moved])
			assert_int(epoch).is_equal(_harness.session.model.epoch)
			assert_int(tick).is_equal(_harness.session.last_claim_tick())
	)
	var welcome := _harness.welcome()
	# The first claim after the Welcome counts as one tick, as the host's fresh claim does.
	assert_array(told).contains_exactly([[1, false, false]])
	var at := welcome.spot + Vector3(0.3, 0, 0)
	_harness.session.set_motion(at, Vector3.ZERO, Vector3.RIGHT, true, true, true)
	_harness.pump(TICK_USEC)
	assert_array(told[-1]).is_equal([1, true, true])
	# Movement input without travel (against a wall) moved nothing.
	_harness.session.set_motion(at, Vector3.ZERO, Vector3.RIGHT, true, true, true)
	_harness.pump(TICK_USEC)
	assert_array(told[-1]).is_equal([1, true, false])
	# Travel without input (a push) is not the player's own movement either.
	_harness.session.set_motion(
		at + Vector3.FORWARD, Vector3.ZERO, Vector3.RIGHT, false, false, true
	)
	_harness.pump(TICK_USEC)
	assert_array(told[-1]).is_equal([1, false, false])
	# A frozen client's next claim covers the whole freeze.
	_harness.pump(5000000)
	assert_int(told[-1][0] as int).is_equal(100)


func test_a_correction_drops_the_steps_before_it_and_a_placement_restarts_the_count() -> void:
	var told: Array[Array] = []
	_harness.session.claim_sent.connect(
		func(epoch: int, _tick: int, covered: int, sprint: bool, moved: bool) -> void:
			told.append([epoch, covered, sprint, moved])
	)
	_harness.welcome(&"lobby", 1)
	_harness.pump(TICK_USEC)
	# Steps that sprinted, then the host's Correction before the next claim: the claim from where
	# the host put it says nothing of them.
	var placed := Vector3(7, 0, 7)
	_harness.session.set_motion(Vector3(9, 0, 9), Vector3.ZERO, Vector3.RIGHT, true, true, true)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, placed, Vector3.ZERO))
	_harness.pump(TICK_USEC * 2)
	var claim := _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
	assert_bool(claim["sprint"] as bool).is_false()
	assert_bool(claim["moving"] as bool).is_false()
	assert_array(told[-1]).is_equal([2, 2, false, false])
	# A placement: the host restarts its client-tick baseline, so the next claim is one tick.
	var spots: Dictionary[int, Vector3] = {_harness.peer: placed}
	_harness.send(PlayersPlacedEvent.new(spots))
	_harness.send(CorrectionEvent.new(_harness.peer, 3, placed, Vector3.ZERO))
	_harness.pump(TICK_USEC * 3)
	assert_int(_harness.session.placements).is_equal(1)
	assert_array(told[-1]).is_equal([3, 1, false, false])


func test_the_masks_give_each_client_tick_the_flags_of_the_claim_that_covered_it() -> void:
	var at := _harness.welcome().spot
	# A sprint tick, a tick standing still holding sprint, a walk tick, then two ticks in one claim
	# (a hitch) sprinting.
	_claim_step(at + Vector3(0.3, 0, 0), true, true, 1)
	_claim_step(at + Vector3(0.3, 0, 0), true, true, 1)
	_claim_step(at + Vector3(0.5, 0, 0), false, true, 1)
	var claim := _claim_step(at + Vector3(1.1, 0, 0), true, true, 2)
	# Oldest to newest from bit 5: the Welcome's claim, sprint, standing, walk, two sprinted ticks.
	assert_int(claim["sprint_ticks"] as int).is_equal(0b011011)
	assert_int(claim["moved_ticks"] as int).is_equal(0b010111)
	# A frozen client's claim covers more ticks than the masks hold: all take its flags.
	claim = _claim_step(at + Vector3(1.1, 0, 0), true, false, 40)
	assert_int(claim["sprint_ticks"] as int).is_equal(0xFFFFFFFF)
	assert_int(claim["moved_ticks"] as int).is_equal(0)


func test_a_correction_keeps_the_masks_of_the_claims_before_it() -> void:
	# The host's next claim covers the ticks of the refused claim and of those in flight: it
	# settles them by the masks, as the predicted stamina settles those claims.
	var at := _harness.welcome(&"lobby", 1).spot
	_claim_step(at + Vector3(0.3, 0, 0), true, true, 1)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, at, Vector3.ZERO))
	_harness.pump()
	var claim := _claim_step(at + Vector3(0.2, 0, 0), false, true, 1)
	assert_int((claim["sprint_ticks"] as int) & 0b11).is_equal(0b10)
	assert_int((claim["moved_ticks"] as int) & 0b11).is_equal(0b11)


func test_the_move_epsilon_is_the_hosts() -> void:
	# claim_sent's moved_itself must be what MovementRule counts, or the predicted stamina drifts.
	assert_float(ClientSession.MOVE_EPSILON).is_equal(MovementRule.MOVE_EPSILON)
	assert_float(PlayerController.MOVE_EPSILON).is_equal(MovementRule.MOVE_EPSILON)


## One claim's tick: a step at `to` with `sprint` and `moving`, then the clock `ticks` client ticks
## on, which sends the claim; returns its fields.
func _claim_step(to: Vector3, sprint: bool, moving: bool, ticks: int) -> Dictionary:
	_harness.session.set_motion(to, Vector3.ZERO, Vector3.RIGHT, sprint, moving, true)
	_harness.pump(TICK_USEC * ticks)
	return _harness.sent_named(Intents.MOVE_CLAIM)[-1].fields
