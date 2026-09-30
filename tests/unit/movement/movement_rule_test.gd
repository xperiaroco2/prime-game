extends GdUnitTestSuite
## MovementRule (ARCHITECTURE §7, §7.1): epochs, well-formed claims, horizontal speed over the
## client's tick delta with the client's tick rate bounded, the push allowance, ghosts' speeds,
## Correction with a new epoch to that player only. Jumps and heights: movement_rule_jump_test.gd.
## Numbers per tick: FixtureMoves.

const P1 := 1
const P2 := 2
const EAST := Vector3(1, 0, 0)


func test_a_claim_of_another_epoch_is_dropped_without_a_correction() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	var was_at := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, was_at + EAST * 0.1, {"epoch": player.epoch - 1})
	FixtureMoves.claim(game, P1, was_at + EAST * 0.1, {"epoch": player.epoch + 1})
	assert_vector(player.position).is_equal(was_at)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_claim_whose_client_tick_does_not_rise_is_dropped() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, EAST * 0.1)
	var at := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, at + EAST * 0.1, {"client_tick": player.claim_tick})
	FixtureMoves.claim(game, P1, at + EAST * 0.1, {"client_tick": player.claim_tick - 1})
	assert_vector(player.position).is_equal(at)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_claim_with_a_value_that_is_not_finite_is_corrected_for_that_player_only() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	var at := player.position
	var epoch := player.epoch
	var others := game.view_of(P2).events.size()
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, Vector3(NAN, 0, 0))
	FixtureMoves.claim(game, P1, at, {"epoch": epoch + 1, "velocity": Vector3(INF, 0, 0)})
	FixtureMoves.claim(game, P1, at, {"epoch": epoch + 2, "facing": Vector3(0, -INF, 0)})
	var found := FixtureMoves.corrections(game, P1)
	assert_int(found.size()).is_equal(seen + 3)
	assert_int(found[found.size() - 1].epoch).is_equal(epoch + 3)
	assert_vector(found[found.size() - 1].position).is_equal(at)
	assert_int(player.epoch).is_equal(epoch + 3)
	assert_vector(player.position).is_equal(at)
	assert_int(game.view_of(P2).events.size()).is_equal(others)


func test_a_claim_missing_a_field_is_corrected() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1])
	var player := game.state.player(P1)
	var epoch := player.epoch
	var claim := {"epoch": epoch, "position": player.position + EAST * 0.1}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim)
	assert_int(player.epoch).is_equal(epoch + 1)
	var claim_tick_as_float := {
		"epoch": epoch + 1,
		"client_tick": 1.0,
		"position": player.position,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
	}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim_tick_as_float)
	assert_int(player.epoch).is_equal(epoch + 2)


func test_a_living_player_walks_at_walk_speed_plus_the_push_allowance() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Walk 0.225 + push 0.35 + slack 0.05 = 0.625 m per tick.
	FixtureMoves.step(game, P1, Vector3(0.6, 0, 0.1), {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 0.64, {"moving": true})
	var found := FixtureMoves.corrections(game, P1)
	assert_int(found.size()).is_equal(seen + 1)
	assert_vector(found[found.size() - 1].position).is_equal(at)
	assert_vector(player.position).is_equal(at)


func test_sprint_speed_needs_the_sprint_state() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Sprint 0.35 + push 0.35 + slack 0.05 = 0.75 m per tick in the sprint state.
	FixtureMoves.step(game, P1, EAST * 0.7, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_bool(player.sprinting).is_true()
	player.stamina = 19000
	player.sprinting = false
	FixtureMoves.step(game, P1, EAST * 0.7, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_speed_is_measured_over_the_clients_own_tick_delta() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureModes.run_ticks(game, 2)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Three client ticks since the last claim: 3 * 0.575 + 0.05 = 1.775 m.
	FixtureMoves.step(game, P1, EAST * 1.7, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureModes.run_ticks(game, 2)
	var at := player.position
	# Three host ticks passed, but the client claims only one of its own.
	FixtureMoves.step(game, P1, EAST * 1.7, {"moving": true, "client_tick": player.claim_tick + 1})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(player.position).is_equal(at)


func test_a_teleport_is_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var at := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, Vector3(20, 0, 0), {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(player.position).is_equal(at)


func test_a_client_tick_that_runs_ahead_of_the_host_is_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Within one host tick the client claims ever more ticks of its own: the lead of 10 passes,
	# then the credit is spent and the next claim is corrected, so inflating the client tick
	# cannot buy distance.
	var tick := player.claim_tick
	for i in 12:
		tick += 1
		var to := player.position + EAST * 0.2
		FixtureMoves.claim(game, P1, to, {"moving": true, "client_tick": tick})
	# The eleventh claim is corrected, and so is the twelfth: in the new epoch it covers two
	# client ticks with no credit left.
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 2)
	assert_int(player.claim_tick).is_equal(tick - 2)


func test_a_catch_up_burst_after_a_five_second_gap_passes() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.steps(game, P1, 5, EAST * 0.2, {"moving": true})
	var seen := FixtureMoves.corrections(game, P1).size()
	# The host hears nothing for 5 s (100 ticks), then the claims the client sent meanwhile, one
	# per client tick, all arrive in one host tick (#70).
	FixtureModes.run_ticks(game, 100)
	var tick := player.claim_tick
	var at := player.position
	for i in 100:
		tick += 1
		at += EAST * 0.2
		FixtureMoves.claim(game, P1, at, {"moving": true, "client_tick": tick})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_vector(player.position).is_equal_approx(at, Vector3.ONE * 1e-4)
	assert_int(player.claim_tick).is_equal(tick)


func test_a_burst_without_a_gap_is_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.steps(game, P1, 5, EAST * 0.2, {"moving": true})
	var seen := FixtureMoves.corrections(game, P1).size()
	var tick := player.claim_tick
	for i in 100:
		tick += 1
		var to := player.position + EAST * 0.2
		FixtureMoves.claim(game, P1, to, {"moving": true, "client_tick": tick})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_greater(seen)


func test_a_client_whose_ticks_ran_ahead_of_a_stalled_host_is_corrected_once() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.steps(game, P1, 5, EAST * 0.2, {"moving": true})
	var seen := FixtureMoves.corrections(game, P1).size()
	# The host stalls and loses 50 ticks while the client goes on at 20 Hz: its 50 claims of the
	# old epoch arrive in one host tick, past the credit.
	var old_epoch := player.epoch
	var tick := player.claim_tick
	var at := player.position
	for i in 50:
		tick += 1
		at += EAST * 0.2
		FixtureMoves.claim(game, P1, at, {"moving": true, "client_tick": tick, "epoch": old_epoch})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	# The Correction reaches the client two ticks later; it goes on from the host's position with
	# its own client tick, still 50 ahead of the host's, one claim per host tick.
	FixtureModes.run_ticks(game, 2)
	tick += 2
	at = player.position
	for i in 20:
		tick += 1
		at += EAST * 0.2
		FixtureMoves.claim(game, P1, at, {"moving": true, "client_tick": tick})
		FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.claim_tick).is_equal(tick)
	assert_vector(player.position).is_equal_approx(at, Vector3.ONE * 1e-4)


func test_the_host_never_corrects_overlapping_players() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var one := game.state.player(P1)
	var two := game.state.player(P2)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P2, Vector3.ZERO)
	var seen_one := FixtureMoves.corrections(game, P1).size()
	var seen_two := FixtureMoves.corrections(game, P2).size()
	# P1 walks into P2 until both stand on the same spot.
	var target := two.position
	for i in 20:
		var to := one.position.move_toward(target, 0.2)
		FixtureMoves.claim(game, P1, to, {"moving": true})
		FixtureMoves.claim(game, P2, two.position)
		FixtureModes.run_ticks(game, 1)
	assert_vector(one.position).is_equal(two.position)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen_one)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen_two)


func test_a_pushed_player_holding_sprint_moves_at_the_push_allowance_for_free() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 50000
	var seen := FixtureMoves.corrections(game, P1).size()
	# Holding sprint without movement input: sprint 0.35 + push 0.35 + slack 0.05 = 0.75 m per
	# tick, and sprint costs nothing: each tick regenerates.
	FixtureMoves.steps(game, P1, 4, EAST * 0.6, {"sprint": true, "moving": false})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(53000)


func test_a_ghost_moves_at_its_factor_without_a_push_allowance() -> void:
	var game := FixtureMoves.in_round([P1])
	var ghost := game.state.player(P1)
	ghost.life = PlayerState.Life.GHOST
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Walk 0.225 * 1.3 + 0.05 = 0.3425 m; sprint 0.35 * 1.3 + 0.05 = 0.505 m.
	FixtureMoves.step(game, P1, EAST * 0.34, {"moving": true})
	FixtureMoves.step(game, P1, EAST * 0.5, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.step(game, P1, EAST * 0.36, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	# After a correction the next claim would cover two client ticks: claim just one.
	var fields := FixtureMoves.sprinting()
	fields["client_tick"] = ghost.claim_tick + 1
	FixtureMoves.step(game, P1, EAST * 0.52, fields)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 2)


func test_stamina_never_limits_a_ghost() -> void:
	var game := FixtureMoves.in_round([P1])
	var ghost := game.state.player(P1)
	ghost.life = PlayerState.Life.GHOST
	ghost.stamina = 0
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.steps(game, P1, 30, EAST * 0.45, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(ghost.stamina).is_equal(0)


func test_after_a_placement_claims_start_again_from_the_placed_spot() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.steps(game, P1, 3, EAST * 0.3, FixtureMoves.sprinting())
	# 60 s pass, the round ends and End -> Lobby places the player in the lobby with a new epoch.
	FixtureModes.run_ticks(game, 1200)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	player.ready = false
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	var spot := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 0.2, {"moving": true})
	FixtureMoves.step(game, P1, EAST * 0.2, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_vector(player.position).is_equal_approx(spot + EAST * 0.4, Vector3.ONE * 1e-4)
	# The ticks of the scene change count as standing still, not as the last claim's sprint.
	assert_int(player.stamina).is_equal(100000)


func test_after_a_correction_claims_in_flight_are_dropped_and_the_next_epoch_goes_on() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 5, {"moving": true})
	var correction: CorrectionEvent = FixtureMoves.corrections(game, P1).back()
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, at + EAST * 5.2, {"epoch": correction.epoch - 1})
	assert_vector(player.position).is_equal(at)
	FixtureMoves.step(game, P1, EAST * 0.2, {"moving": true, "epoch": correction.epoch})
	assert_vector(player.position).is_equal_approx(at + EAST * 0.2, Vector3.ONE * 1e-4)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
