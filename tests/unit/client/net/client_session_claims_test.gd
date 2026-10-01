extends GdUnitTestSuite
## ClientSession's MoveClaims (ARCHITECTURE §4.3, E2): one per client tick (20 Hz of its own clock)
## with its epoch, the client tick and the jumps counted in that epoch, reset at each new epoch; a
## Correction's position adopted; none before Welcome, and none in a phase whose allowlist (the
## client's own copy of the mode) does not accept MoveClaim from it.

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
	_harness.send(DiedEvent.new(_harness.peer, Vector3(2, 0, 2)))
	_harness.pump(TICK_USEC)
	var as_downed := _harness.sent_named(Intents.MOVE_CLAIM).size()
	_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(as_downed + 1)
	assert_bool(_harness.session.model.is_alive(_harness.peer)).is_false()


func test_a_downed_player_in_a_phase_for_the_living_does_not_claim() -> void:
	var mode := FixtureBaseMode.mode()
	var lobby_accepts := mode.find_phase(&"lobby").senders_of(Intents.MOVE_CLAIM)
	assert_int(lobby_accepts & AcceptSpec.From.DOWNED).is_equal(0)
	_harness.welcome(&"lobby")
	# No mode kills in the lobby; a Died there still makes this client downed to its own rules.
	_harness.send(DiedEvent.new(_harness.peer, Vector3(2, 0, 2)))
	_harness.pump(TICK_USEC)
	var claims := _harness.sent_named(Intents.MOVE_CLAIM).size()
	for i in 5:
		_harness.pump(TICK_USEC)
	assert_int(_harness.sent_named(Intents.MOVE_CLAIM).size()).is_equal(claims)


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
