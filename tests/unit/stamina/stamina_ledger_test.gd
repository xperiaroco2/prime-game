extends GdUnitTestSuite
## StaminaLedger (ARCHITECTURE §7.1, Q7), driven by MoveClaims: a covered tick in the sprint state
## with the player's own movement costs 1000 thousandths, every other tick regenerates 750; the
## sprint state starts at 20 points and lasts until 0; claims never settle past the host tick;
## ticks no claim covers are settled with the last claim's flags seen a jump; the downed never
## sprint.

const P1 := 1
const NORTH := Vector3(0, 0, 1)
const UP := Vector3(0, 1, 0)


func test_a_sprinting_step_of_its_own_costs_a_twentieth_of_the_cost_per_second() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.steps(game, P1, 10, NORTH * 0.3, FixtureMoves.sprinting())
	assert_int(player.stamina).is_equal(90000)
	assert_bool(player.sprinting).is_true()


func test_sprint_without_movement_input_or_without_moving_regenerates() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 50000
	# Pushed: moved, but gave no movement input (the engineer's decision of 2026-09-30, #46).
	FixtureMoves.steps(game, P1, 2, NORTH * 0.3, {"sprint": true, "moving": false})
	assert_int(player.stamina).is_equal(51500)
	# Gave movement input against a wall: did not move.
	FixtureMoves.steps(game, P1, 2, Vector3.ZERO, FixtureMoves.sprinting())
	assert_int(player.stamina).is_equal(53000)
	assert_bool(player.sprinting).is_true()


func test_the_sprint_state_starts_at_the_threshold_and_lasts_until_zero() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 19250
	# Below 20 points sprint cannot start: the tick regenerates and the speed is a walk's.
	FixtureMoves.step(game, P1, NORTH * 0.2, FixtureMoves.sprinting())
	assert_bool(player.sprinting).is_false()
	assert_int(player.stamina).is_equal(20000)
	FixtureMoves.step(game, P1, NORTH * 0.3, FixtureMoves.sprinting())
	assert_bool(player.sprinting).is_true()
	assert_int(player.stamina).is_equal(19000)
	player.stamina = 1000
	# Once started, it lasts while stamina is above 0.
	FixtureMoves.step(game, P1, NORTH * 0.3, FixtureMoves.sprinting())
	assert_bool(player.sprinting).is_true()
	assert_int(player.stamina).is_equal(0)
	FixtureMoves.step(game, P1, NORTH * 0.2, FixtureMoves.sprinting())
	assert_bool(player.sprinting).is_false()
	assert_int(player.stamina).is_equal(750)
	FixtureMoves.step(game, P1, NORTH * 0.2, FixtureMoves.sprinting())
	assert_bool(player.sprinting).is_false()
	assert_int(player.stamina).is_equal(1500)


func test_at_zero_stamina_walking_works() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 0
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.steps(game, P1, 10, NORTH * 0.2, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(7500)


func test_a_claim_never_settles_past_the_host_tick() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var fields := FixtureMoves.sprinting()
	fields["client_tick"] = player.claim_tick + 5
	FixtureMoves.claim(game, P1, player.position + NORTH * 0.5, fields)
	assert_int(player.stamina_settled_tick).is_equal(game.ticked_through() + 1)
	assert_int(player.stamina).is_equal(99000)


func test_claims_spaced_out_do_not_regenerate_between_them() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	# One client tick of sprinting every 10 host ticks: each claim settles its one tick.
	for i in 5:
		var fields := FixtureMoves.sprinting()
		fields["client_tick"] = player.claim_tick + 1
		FixtureMoves.step(game, P1, NORTH * 0.3, fields)
		FixtureModes.run_ticks(game, 9)
	assert_int(player.stamina).is_equal(95000)


func test_ticks_no_claim_covers_are_settled_before_a_jump_with_the_last_claims_flags() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.steps(game, P1, 3, NORTH * 0.3, FixtureMoves.sprinting())
	assert_int(player.stamina).is_equal(97000)
	FixtureModes.run_ticks(game, 5)
	# The jump claims one client tick; the five silent ticks and its own are settled first, as the
	# last claim's sprinting by its own movement: 6 * 1000, then the jump's 10000.
	var jump := FixtureMoves.sprinting()
	jump.merge(FixtureMoves.jumped(game, P1))
	jump["client_tick"] = player.claim_tick + 1
	FixtureMoves.step(game, P1, NORTH * 0.3 + UP * 0.1, jump)
	assert_int(player.stamina).is_equal(81000)
	# The next claim covers six client ticks, but only the one host tick since is left to settle.
	var next := FixtureMoves.sprinting()
	next["on_floor"] = false
	FixtureMoves.step(game, P1, NORTH * 0.3 + UP * 0.2, next)
	assert_int(player.stamina).is_equal(80000)


func test_a_downed_player_is_never_in_the_sprint_state_and_regenerates() -> void:
	# The crawl (M4-2): holding sprint spends nothing, and the ticks regenerate as usual.
	var game := FixtureMoves.in_round([P1])
	var downed := game.state.player(P1)
	downed.life = PlayerState.Life.DOWNED
	downed.stamina = 30000
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var before := downed.stamina
	FixtureMoves.steps(game, P1, 10, NORTH * 0.05, FixtureMoves.sprinting())
	assert_int(downed.stamina).is_equal(before + 10 * 750)
	assert_bool(downed.sprinting).is_false()
	var last: SelfStatusEvent = FixtureMoves.statuses(game, P1).back()
	assert_bool(last.sprint_available).is_false()
