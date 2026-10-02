extends GdUnitTestSuite
## MovementRule (ARCHITECTURE §7, §7.1): epochs, well-formed claims, horizontal speed over the
## client's tick delta with the client's tick rate bounded, the push allowance (only near another
## living player), the downed's crawl, the stored facing (a unit vector, pitch within ±89°),
## Correction with a new epoch to that player only. Jumps and heights: movement_rule_jump_test.gd.
## Numbers per tick: FixtureMoves.

const P1 := 1
const P2 := 2
const EAST := Vector3(1, 0, 0)
const NORTH := Vector3(0, 0, 1)


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


func test_a_first_claim_with_a_negative_client_tick_is_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	var epoch := player.epoch
	# The first claim after a placement has no client-tick baseline to be measured against.
	FixtureMoves.claim(game, P1, player.position, {"client_tick": -5})
	assert_int(player.epoch).is_equal(epoch + 1)
	# So the stale-claim drop still works for the claims after it.
	FixtureMoves.claim(game, P1, player.position, {"client_tick": 3})
	FixtureMoves.claim(game, P1, player.position, {"client_tick": 2})
	assert_int(player.claim_tick).is_equal(3)
	assert_int(player.epoch).is_equal(epoch + 1)


func test_a_living_player_alone_walks_at_walk_speed() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Walk 0.225 + slack 0.05 = 0.275 m per tick: with nobody near, nobody pushes.
	FixtureMoves.step(game, P1, EAST * 0.27, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 0.3, {"moving": true})
	var found := FixtureMoves.corrections(game, P1)
	assert_int(found.size()).is_equal(seen + 1)
	assert_vector(found[found.size() - 1].position).is_equal(at)
	assert_vector(player.position).is_equal(at)


func test_a_living_player_near_another_walks_at_walk_speed_plus_the_push_allowance() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	_put(game, P2, player.position + NORTH * 0.8)
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
	# Sprint 0.35 + slack 0.05 = 0.4 m per tick in the sprint state.
	FixtureMoves.step(game, P1, EAST * 0.38, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_bool(player.sprinting).is_true()
	player.stamina = 19000
	player.sprinting = false
	FixtureMoves.step(game, P1, EAST * 0.38, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_the_tick_after_a_sprint_ran_out_goes_at_walk_speed() -> void:
	# No tick of sprint beyond the stamina (#155): the client predicts its own and stops
	# sprinting with the tick its stamina ran out in. A claim right after it that still goes at
	# sprint speed is corrected; a walk tick passes.
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, EAST * 0.35, FixtureMoves.sprinting())
	player.stamina = 1000
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 0.35, FixtureMoves.sprinting())
	assert_int(player.stamina).is_equal(0)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 0.35, FixtureMoves.sprinting())
	var found := FixtureMoves.corrections(game, P1)
	assert_int(found.size()).is_equal(seen + 1)
	assert_vector(found[found.size() - 1].position).is_equal(at)
	FixtureMoves.step(game, P1, EAST * 0.22, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_bool(player.sprinting).is_false()
	assert_vector(player.position).is_equal(at + EAST * 0.22)


func test_the_claim_that_stops_a_sprint_needs_its_latched_flags() -> void:
	# A sprinter who lets go within a claim's tick moved most of a sprint tick: the client latches
	# the flags over the claim's steps (#155), so that claim says sprint and movement input and
	# passes. The same travel in a claim without them, the flags of its last step alone, is held to
	# the walk and corrected.
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, EAST * 0.35, FixtureMoves.sprinting())
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 0.34, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 0.34)
	var found := FixtureMoves.corrections(game, P1)
	assert_int(found.size()).is_equal(seen + 1)
	assert_vector(found[found.size() - 1].position).is_equal(at)


func test_a_claim_that_lets_go_of_sprint_but_walks_on_needs_its_sprint_flag() -> void:
	# Two physics steps of sprint and one of walk (7 + 7 + 4.5 m/s over 1/60 s: 0.308 m) are past
	# the walk's 0.275 m: the claim passes with its latched sprint flag and is corrected without it.
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, EAST * 0.35, FixtureMoves.sprinting())
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 0.308, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.step(game, P1, EAST * 0.308, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_bool(player.sprinting).is_true()


func test_speed_is_measured_over_the_clients_own_tick_delta() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureModes.run_ticks(game, 2)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Three client ticks since the last claim: 3 * 0.225 + 0.05 = 0.725 m.
	FixtureMoves.step(game, P1, EAST * 0.7, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureModes.run_ticks(game, 2)
	var at := player.position
	# Three host ticks passed, but the client claims only one of its own.
	FixtureMoves.step(game, P1, EAST * 0.7, {"moving": true, "client_tick": player.claim_tick + 1})
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


func test_a_catch_up_burst_merged_into_its_newest_claim_passes() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.steps(game, P1, 5, EAST * 0.2, {"moving": true})
	var seen := FixtureMoves.corrections(game, P1).size()
	# As above, but the transport merges a LATEST backlog into its newest message (ARCHITECTURE
	# §4): after 5 s the host gets one claim that covers all 100 client ticks (#70).
	FixtureModes.run_ticks(game, 100)
	var tick := player.claim_tick + 100
	var at := player.position + EAST * 20.0
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
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 50000
	var seen := FixtureMoves.corrections(game, P1).size()
	# Holding sprint without movement input while P2 pushes: walk 0.225 + push 0.35 + slack 0.05
	# = 0.625 m per tick, and sprint costs nothing: each tick regenerates.
	for i in 4:
		_put(game, P2, player.position + NORTH * 0.8)
		FixtureMoves.step(game, P1, EAST * 0.6, {"sprint": true, "moving": false})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(53000)
	# Sprint speed of its own needs the movement input that pays for it.
	_put(game, P2, player.position + NORTH * 0.8)
	FixtureMoves.step(game, P1, EAST * 0.7, {"sprint": true, "moving": false})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	FixtureMoves.step(game, P1, EAST * 0.7, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_the_push_allowance_needs_a_living_player_within_reach_of_the_path() -> void:
	# A modified client claiming it is pushed, with nobody near, got walk + sprint (11.5 m/s) with
	# no input and no stamina (#76). Now only another living player's last accepted position
	# within MovementRule.push_reach() (2.2 m) of the claim's path grants it.
	var game := FixtureMoves.in_round([P1, P2])
	var reach := MovementRule.push_reach(FixtureModes.player_rules())
	assert_float(reach).is_equal_approx(2.2, 1e-6)
	# Beyond the reach of the path's end (0.6 m east of the start), and ahead within it.
	assert_bool(_pushed_claim_corrected(game, EAST * (0.6 + reach + 0.05))).is_true()
	assert_bool(_pushed_claim_corrected(game, EAST * (0.6 + reach - 0.05))).is_false()
	# Beside the middle of the path, just beyond the reach and just within it.
	assert_bool(_pushed_claim_corrected(game, EAST * 0.3 + NORTH * (reach + 0.05))).is_true()
	assert_bool(_pushed_claim_corrected(game, EAST * 0.3 + NORTH * (reach - 0.05))).is_false()
	# Near, with its feet more than the capsule's height (1.8 m) above: on another floor.
	assert_bool(_pushed_claim_corrected(game, NORTH * 0.8 + Vector3.UP * 1.9)).is_true()
	assert_bool(_pushed_claim_corrected(game, NORTH * 0.8 + Vector3.UP * 1.7)).is_false()
	# The downed and the dead push nobody.
	var other := game.state.player(P2)
	other.life = PlayerState.Life.DOWNED
	assert_bool(_pushed_claim_corrected(game, NORTH * 0.8)).is_true()
	other.life = PlayerState.Life.DEAD
	assert_bool(_pushed_claim_corrected(game, NORTH * 0.8)).is_true()


func test_the_push_reach_grows_while_the_pushers_claims_are_lost() -> void:
	# The pusher's unreliable claims are lost while it pushes: its last accepted position falls
	# behind, by a tick of sprinting (0.35 m) for each host tick lost, up to PUSH_TICKS (3.5 m).
	var game := FixtureMoves.in_round([P1, P2])
	var reach := MovementRule.push_reach(FixtureModes.player_rules())
	var beside := EAST * 0.3 + NORTH * (reach + 0.3)
	assert_bool(_pushed_after_lost_claims(game, beside, 0)).is_true()
	assert_bool(_pushed_after_lost_claims(game, beside, 1)).is_false()
	beside = EAST * 0.3 + NORTH * (reach + 3.4)
	assert_bool(_pushed_after_lost_claims(game, beside, 20)).is_false()
	beside = EAST * 0.3 + NORTH * (reach + 3.6)
	assert_bool(_pushed_after_lost_claims(game, beside, 20)).is_true()


func test_a_claim_covering_stored_credit_is_pushed_for_at_most_the_push_ticks() -> void:
	# P1 keeps quiet for 40 ticks beside P2, then one claim without input covers them all. Walk
	# 40 * 0.225 = 9 m, plus the push for at most PUSH_TICKS (10) ticks, 3.5 m, plus 0.05 m:
	# 12.55 m. Counting the push over all 40 ticks would allow 23.05 m.
	assert_int(MovementRule.PUSH_TICKS).is_equal(10)
	assert_bool(_quiet_push_corrected(12.5)).is_false()
	assert_bool(_quiet_push_corrected(12.6)).is_true()
	assert_bool(_quiet_push_corrected(20.0)).is_true()


func test_a_downed_player_crawls_with_no_sprint_and_no_push_allowance() -> void:
	var game := FixtureMoves.in_round([P1])
	var downed := game.state.player(P1)
	downed.life = PlayerState.Life.DOWNED
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# The crawl: 1 m/s is 0.05 m per tick, plus a tenth of it as slack, with or without sprint.
	FixtureMoves.step(game, P1, EAST * 0.054, {"moving": true})
	FixtureMoves.step(game, P1, EAST * 0.054, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	# Sprinting buys nothing: a living walker's 0.225 m per tick is corrected.
	FixtureMoves.step(game, P1, EAST * 0.2, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	# Nobody pushes the downed: no push allowance either, with no movement input.
	var fields := {"client_tick": downed.claim_tick + 1}
	FixtureMoves.step(game, P1, EAST * 0.11, fields)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 2)


func test_one_tick_claims_do_not_double_the_crawl_speed() -> void:
	# A fixed slack per claim (0.05 m) is a whole tick of the crawl: a client claiming every tick
	# would crawl at about 1.9 m/s. The crawl's slack is in proportion to its own travel.
	var game := FixtureMoves.in_round([P1])
	var downed := game.state.player(P1)
	downed.life = PlayerState.Life.DOWNED
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.steps(game, P1, 20, EAST * 0.05, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.steps(game, P1, 20, EAST * 0.095, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_greater(seen)


func test_a_downed_player_spends_no_stamina_and_regenerates() -> void:
	var game := FixtureMoves.in_round([P1])
	var downed := game.state.player(P1)
	downed.life = PlayerState.Life.DOWNED
	downed.stamina = 0
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	var stamina_before := downed.stamina
	FixtureMoves.steps(game, P1, 20, EAST * 0.05, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	# 750 thousandths a tick, as for a living player who does not sprint.
	assert_int(downed.stamina).is_equal(stamina_before + 20 * 750)
	assert_bool(downed.sprinting).is_false()


func test_the_stored_facing_is_the_claims_direction_as_a_unit_vector() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3(0, 0, 2)})
	assert_vector(player.facing).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 1e-6)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3(3, 0, 4) * 1e30})
	assert_vector(player.facing).is_equal_approx(Vector3(0.6, 0, 0.8), Vector3.ONE * 1e-6)


func test_a_zero_facing_keeps_the_last_one() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3(1, 0, 0)})
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3.ZERO})
	assert_vector(player.facing).is_equal(Vector3(1, 0, 0))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_facing_straight_down_keeps_the_last_yaw_at_89_degrees() -> void:
	# A bot falling straight down claims (0, -1, 0) (the M4 ADR §3).
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3(1, 0, 0)})
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3(0, -1, 0)})
	var most := deg_to_rad(MovementRule.MAX_PITCH_DEG)
	var expected := Vector3(cos(most), -sin(most), 0)
	assert_vector(player.facing).is_equal_approx(expected, Vector3.ONE * 1e-6)


func test_a_claimed_90_degree_pitch_is_clamped_to_89_degrees() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	var most := deg_to_rad(MovementRule.MAX_PITCH_DEG)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": Vector3(0, 1, 0)})
	# The placement's facing, Vector3.FORWARD, gives the yaw.
	var up := Vector3(0, sin(most), -cos(most))
	assert_vector(player.facing).is_equal_approx(up, Vector3.ONE * 1e-6)
	# A steep pitch with a yaw of its own keeps that yaw.
	var steep := Vector3(cos(deg_to_rad(89.9)), sin(deg_to_rad(89.9)), 0)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": steep})
	var clamped := Vector3(cos(most), sin(most), 0)
	assert_vector(player.facing).is_equal_approx(clamped, Vector3.ONE * 1e-6)
	# A pitch inside the bound is kept as claimed.
	var gentle := Vector3(1, 1, 0).normalized()
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": gentle})
	assert_vector(player.facing).is_equal_approx(gentle, Vector3.ONE * 1e-6)


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


## Sets `peer`'s last accepted position, as a claim the host accepted would.
func _put(game: Match, peer: int, at: Vector3) -> void:
	game.state.player(peer).position = at


## Whether P1's claim of 0.6 m east in one client tick, without movement input, is corrected while
## P2's last accepted position is at `offset` from P1's: within the push allowance (walk 0.225 +
## push 0.35 + slack 0.05 = 0.625 m) but beyond a walk alone (0.275 m). A claim standing still
## first makes the claim cover one tick, also after a correction.
func _pushed_claim_corrected(game: Match, offset: Vector3) -> bool:
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	_put(game, P2, player.position + offset)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 0.6)
	return FixtureMoves.corrections(game, P1).size() > seen


## Whether P1's one claim of `distance` m east without movement input, covering 40 client ticks
## after 39 quiet ones, is corrected while P2's last accepted position is beside its start.
func _quiet_push_corrected(distance: float) -> bool:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	_put(game, P2, player.position + NORTH * 0.8)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureModes.run_ticks(game, 39)
	FixtureMoves.step(game, P1, EAST * distance)
	return FixtureMoves.corrections(game, P1).size() > seen


## Whether P1's pushed claim of _pushed_claim_corrected is corrected while P2's claim at `offset`
## from P1 was accepted, then `lost` host ticks went by with none of P2's claims arriving (P1's
## standing still arrive, so its pushed claim covers one tick).
func _pushed_after_lost_claims(game: Match, offset: Vector3, lost: int) -> bool:
	var player := game.state.player(P1)
	var other := game.state.player(P2)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	_put(game, P2, player.position + offset)
	FixtureMoves.claim(game, P2, other.position)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	for i in lost:
		FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 0.6)
	return FixtureMoves.corrections(game, P1).size() > seen
