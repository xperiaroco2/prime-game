extends GdUnitTestSuite
## MovementRule's jumps and heights (ARCHITECTURE §7, §7.1): a jump needs a WorldQuery floor
## within step height below the last accepted feet, and stamina for the living; the feet stay
## within the jump height (plus MovementRule.jump_slack) of the take-off until the next landing; a
## rise without a jump stays within the step height (plus STEP_CLEARANCE and the slope allowance).
## A downed player never jumps and climbs the step height.
## Players are placed at z = 5 on the ground (y = 0); the world has a 0.3 m step at z 6 to 8 and a
## 0.9 m ledge at z 10 to 14.

const P1 := 1
const UP := Vector3(0, 1, 0)
const NORTH := Vector3(0, 0, 1)
## The jump height (1 m) plus the slack: 0.4 * (1 - cos 45°) + 0.01, about 0.127 m.
const PEAK := 1.12
const OVER_PEAK := 1.14
## Where the staircase of 5 cm steps (a 45° slope) starts, north of the players.
const SLOPE_FOOT := 5.2


func test_a_jump_from_the_floor_costs_its_stamina_and_rises_to_the_jump_height() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(player.stamina).is_equal(90000)
	for height: float in [0.5, 0.9, PEAK]:
		FixtureMoves.claim(game, P1, ground + UP * height, _air())
		FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.claim(game, P1, ground + UP * OVER_PEAK, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_float(player.position.y).is_equal_approx(PEAK, 1e-5)


func test_the_jump_slack_covers_a_rolled_landing_and_a_step_crossing() -> void:
	var rules := FixtureModes.player_rules()
	var expected := 0.4 * (1.0 - cos(deg_to_rad(45.0))) + 0.01
	assert_float(MovementRule.jump_slack(rules)).is_equal_approx(expected, 1e-6)
	assert_float(MovementRule.jump_slack(rules)).is_between(PEAK - 1.0, OVER_PEAK - 1.0)


func test_a_jump_right_after_a_landing_within_one_claim_passes() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, UP * 0.2, _air())
	var seen := FixtureMoves.corrections(game, P1).size()
	# The last claim was in the air 0.2 m above the ground; within the next 50 ms the client
	# landed and jumped (its physics runs at 60 Hz), so this claim is the jump. WorldQuery finds
	# the floor within step height below the last feet, and the peak counts from those feet.
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(90000)
	FixtureMoves.claim(game, P1, Vector3(player.position.x, 0.2 + OVER_PEAK, 5), _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_a_jump_needs_a_world_query_floor_within_step_height() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	# Up a slope WorldQuery does not know, the claim says it stands on the floor 0.4 m above the
	# ground, where WorldQuery finds no floor within the step height plus STEP_CLEARANCE (0.31 m).
	FixtureMoves.step(game, P1, Vector3(0, 0.4, 0.1), {"moving": true})
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(100000)


func test_a_jump_while_crossing_a_ledge_at_step_height_passes() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, NORTH * 0.5, {"moving": true})
	# Crossing onto the 0.3 m step at z = 6, the client's feet are STEP_CLEARANCE above its top
	# while the ray at the origin still finds the ground below: it counts as on the floor.
	FixtureMoves.step(game, P1, Vector3(0, 0.31, 0.4), {"moving": true})
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(90000)


func test_a_second_jump_in_the_air_is_corrected() -> void:
	var game := _round()
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	FixtureMoves.step(game, P1, UP * 0.3, _air())
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.3, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	# 90000 after the first jump, then two ticks of regeneration, and no second cost.
	assert_int(game.state.player(P1).stamina).is_equal(91500)


func test_a_jump_needs_its_full_cost_settled_up_to_now() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 9000
	var seen := FixtureMoves.corrections(game, P1).size()
	# Settled first: one tick of regeneration gives 9750, short of the jump's 10000.
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(9750)
	# One more tick passed: 10500 covers it, and 500 is left.
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(500)
	var last: SelfStatusEvent = FixtureMoves.statuses(game, P1).back()
	assert_int(last.stamina).is_equal(500)
	assert_bool(last.sprint_available).is_false()


func test_a_jump_claim_pays_for_the_sprint_it_covers() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# The last claim stood still without sprint; nine host ticks later one jump claim covers ten
	# client ticks of sprinting 0.35 m each. Its own ticks are settled with its own flags: ten
	# sprint ticks (10 * 1000), then the jump (10000).
	FixtureModes.run_ticks(game, 9)
	var fields := FixtureMoves.jumped(game, P1)
	fields.merge(FixtureMoves.sprinting())
	FixtureMoves.step(game, P1, Vector3(3.5, 0.1, 0), fields)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(80000)


func test_a_downed_players_new_jump_is_corrected_whatever_its_stamina() -> void:
	# The crawl (M4-2): no jump, even with full stamina and a floor under the feet.
	var game := _round()
	var downed := game.state.player(P1)
	downed.life = PlayerState.Life.DOWNED
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := downed.position
	var stamina := downed.stamina
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(downed.position).is_equal(ground)
	assert_int(downed.stamina).is_greater_equal(stamina)
	# Even a jump that rises nothing: the count alone is a jump.
	FixtureMoves.step(game, P1, Vector3.ZERO, FixtureMoves.jumped(game, P1, {"on_floor": true}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 2)


func test_a_downed_player_climbs_a_step_height_rise_and_no_more() -> void:
	var game := _round()
	var downed := game.state.player(P1)
	downed.life = PlayerState.Life.DOWNED
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := downed.position
	var seen := FixtureMoves.corrections(game, P1).size()
	# Step height 0.3 m plus the client's 0.01 m clearance, as for the living.
	FixtureMoves.step(game, P1, UP * 0.305, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.claim(game, P1, ground + UP * 0.33, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_a_rise_without_a_jump_is_bounded_by_the_step_height() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	# Step height 0.3 m plus the client's 0.01 m clearance over a ledge's edge.
	FixtureMoves.step(game, P1, UP * 0.305, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.claim(game, P1, ground + UP * 0.33, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_a_rise_may_add_the_horizontal_travel_on_a_slope() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	# 0.5 m north in three ticks (walking, up to 0.725 m): up to 0.3 + 0.01 + 0.5 * tan 45° =
	# 0.81 m higher, as up a 45° slope.
	FixtureModes.run_ticks(game, 2)
	FixtureMoves.step(game, P1, NORTH * 0.5 + UP * 0.8, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	# 0.5 m further north, 0.85 m above the base (the ground): corrected.
	FixtureModes.run_ticks(game, 2)
	FixtureMoves.claim(game, P1, ground + NORTH * 1.0 + UP * 0.85, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_a_claim_covering_stored_credit_climbs_at_most_the_slope_ticks() -> void:
	# A client keeps quiet for 40 ticks, then one claim covering them all walks 8 m north onto a
	# roof 3 m up. The slope allowance used to count all 8 m (0.3 + 0.01 + 8 = 8.31 m of rise);
	# it now counts at most SLOPE_TICKS (10) ticks of the claim's allowed travel: 9.05 m * 10 / 40,
	# about 2.26 m, so up to about 2.57 m.
	assert_bool(_quiet_climb_corrected(3.0)).is_true()
	assert_bool(_quiet_climb_corrected(2.5)).is_false()


func test_an_honest_climb_whose_claims_were_lost_is_not_corrected() -> void:
	# Walking up a 45° staircase of 5 cm steps, as up a slope. The unreliable claims are lost: one,
	# then nine in a row, so the next claim covers two, then ten ticks of climbing from the last
	# landing. Capping the rise to one tick's travel would correct both (#74).
	var world := FixtureTerrainWorld.new()
	for k in range(1, 97):
		world.add_platform(0, SLOPE_FOOT + 0.05 * (k - 1), 30, 30, 0.05 * k)
	var game := FixtureMoves.in_round([P1], world)
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	var walk := {"moving": true}
	for lost: int in [0, 0, 0, 1, 0, 9, 0]:
		FixtureModes.run_ticks(game, lost)
		var to := player.position + NORTH * 0.225 * (lost + 1)
		to.y = _on_slope(to.z)
		FixtureMoves.step(game, P1, to - player.position, walk)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_float(player.position.y).is_greater(3.0)


func test_walking_up_steps_moves_the_base_to_each_landing() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Walk north onto the 0.3 m step at z 6; landed there, the next 0.3 m counts from its top.
	FixtureMoves.steps(game, P1, 5, NORTH * 0.2, {"moving": true})
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.3, {"moving": true})
	FixtureMoves.steps(game, P1, 2, NORTH * 0.2, {"moving": true})
	assert_float(player.position.y).is_equal_approx(0.3, 1e-5)
	FixtureMoves.step(game, P1, UP * 0.305, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_jump_onto_a_ledge_lands_there_and_the_next_jump_starts_from_it() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.position.z = 9.3
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, player.position)
	FixtureModes.run_ticks(game, 1)
	var fields := FixtureMoves.jumped(game, P1, {"moving": true})
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.2, fields)
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.6, _air({"moving": true}))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.2, _air({"moving": true}))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * -0.1, {"moving": true})
	assert_float(player.position.z).is_greater(10.0)
	assert_float(player.position.y).is_equal_approx(0.9, 1e-5)
	var ledge := player.position
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	FixtureMoves.claim(game, P1, ledge + UP * PEAK, _air())
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_less(85000)


func test_the_jump_bound_lasts_only_until_the_next_landing() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	FixtureMoves.claim(game, P1, ground + UP * 0.9, _air())
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.claim(game, P1, ground)
	FixtureModes.run_ticks(game, 1)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, ground + UP * 0.5, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(player.position).is_equal(ground)


func test_a_replay_of_jumps_and_corrections_matches_the_recording() -> void:
	var game := _round()
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	FixtureMoves.step(game, P1, UP * 0.5, FixtureMoves.jumped(game, P1))
	FixtureMoves.step(game, P1, UP * -0.1, {"moving": true})
	FixtureMoves.steps(game, P1, 3, NORTH * 0.3, FixtureMoves.sprinting())
	var replayed := Match.replay(game.command_log, FixtureModes.basic())
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))
	assert_array(game.command_log.world_answers).is_not_empty()


func test_a_merged_burst_of_three_jumps_pays_each_and_grants_one_jump_height() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	# The LATEST lane kept only the newest claim of a burst of three ticks: the count rose by 3
	# since the last accepted one. Each jump is paid (3 * 10000); the take-offs of the merged
	# claims are lost, so the burst gets one jump height from the last accepted feet (E2).
	FixtureModes.run_ticks(game, 2)
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 3}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(70000)
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(3)
	FixtureMoves.claim(game, P1, ground + UP * PEAK, _air())
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	FixtureMoves.claim(game, P1, ground + UP * OVER_PEAK, _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_a_jump_whose_claim_was_lost_counts_in_the_next_claim() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	# The claim that took off (count 1) never arrived; the next one, already 0.6 m up, still says 1:
	# above the step height, it passes only as the jump.
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, UP * 0.6, _air({"jumps": 1}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(90000)
	FixtureMoves.claim(game, P1, ground + UP * PEAK, _air())
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_claim_with_the_same_count_is_no_new_jump() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	FixtureMoves.step(game, P1, UP * -0.1)
	assert_int(player.stamina).is_equal(90750)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Landed; the count is still 1, so a rise beyond the step height is corrected, and nothing paid.
	FixtureMoves.claim(game, P1, player.position + UP * 0.5, _air({"jumps": 1}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(90750)


func test_a_jump_count_that_falls_within_an_epoch_is_corrected_and_restarts_at_zero() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	var epoch := player.epoch
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 0}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.epoch).is_equal(epoch + 1)
	# The client adopted the new epoch and counts from 0: a claim with 0 is on time, 1 a new jump.
	FixtureMoves.step(game, P1, UP * -0.2, {"jumps": 0})
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 1}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(1)


func test_stamina_for_fewer_than_the_counted_jumps_is_corrected() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 27000
	var seen := FixtureMoves.corrections(game, P1).size()
	# A claim of three jumps over three ticks, settled first: three ticks of regeneration give
	# 29250, short of three jumps' 30000.
	FixtureModes.run_ticks(game, 2)
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 3}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(29250)
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(0)
	# In the new epoch, two jumps (20000) are covered by 30000.
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 2}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(10000)


func test_more_new_jumps_than_covered_ticks_is_corrected() -> void:
	# A client lands between two jumps, so a claim adds at most one jump per client tick it
	# covers (#117 item 6): two in one tick are corrected and cost nothing; two in two pass.
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 2}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(player.position).is_equal(ground)
	assert_int(player.stamina).is_equal(100000)
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(0)
	# In the new epoch, after a claim standing still: two jumps in a claim covering two ticks.
	FixtureMoves.step(game, P1, Vector3.ZERO, {"jumps": 0})
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 2}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(80000)
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(2)


func test_a_claim_without_an_int_jump_count_is_corrected() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, Vector3.ZERO, {"jumps": 1.0})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	var claim := {
		"epoch": player.epoch,
		"client_tick": game.ticked_through() + 1,
		"position": player.position,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"on_floor": true,
	}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 2)


func test_a_jump_count_outside_the_wires_u16_is_corrected() -> void:
	# A huge count would overflow count * jump cost: 2^60 jumps of 10000 wrap to a cost of 0.
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.stamina = 0
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": MovementRule.MAX_JUMPS + 1}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumps": 1 << 60}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 2)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"jumps": -1})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 3)
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(0)
	# Only regeneration: short of one jump's 10000.
	assert_int(player.stamina).is_less(10000)


func test_a_jump_from_a_ledges_edge_stands_on_the_ledge() -> void:
	# E10: the take-off's floor is the highest under the capsule's footprint. On the ledge's edge
	# the feet's own ray misses the ledge (the ground is 0.9 m below), a ray 0.4 m ahead hits it.
	var game := _on_ledge_edge(0.4)
	var player := game.state.player(P1)
	var stamina := player.stamina
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_less(stamina)


func test_with_one_ray_a_jump_from_a_ledges_edge_would_be_corrected() -> void:
	var game := _on_ledge_edge(0.0)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


## P1 jumped onto the 0.9 m ledge at z 10 and walked back to its edge (z 9.7, feet at 0.9), on a
## world whose footprint radius is `radius`.
func _on_ledge_edge(radius: float) -> Match:
	var world := FixtureTerrainWorld.new()
	world.add_platform(0, 6, 30, 8, 0.3).add_platform(0, 10, 30, 14, 0.9)
	world.footprint_radius = radius
	var game := FixtureMoves.in_round([P1], world)
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	player.position.z = 9.3
	FixtureMoves.claim(game, P1, player.position)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.2, FixtureMoves.jumped(game, P1))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.6, _air({"moving": true}))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.2, _air({"moving": true}))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * -0.1, {"moving": true})
	FixtureMoves.steps(game, P1, 2, NORTH * -0.2, {"moving": true})
	FixtureModes.run_ticks(game, 5)
	assert_float(player.position.z).is_equal_approx(9.7, 1e-5)
	assert_float(player.position.y).is_equal_approx(0.9, 1e-5)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(1)
	return game


## Whether one claim covering 40 quiet ticks, walking 8 m north from the ground onto a roof
## `height` up, is corrected.
func _quiet_climb_corrected(height: float) -> bool:
	var world := FixtureTerrainWorld.new()
	world.add_platform(0, 12.5, 30, 14, height)
	var game := FixtureMoves.in_round([P1], world)
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureModes.run_ticks(game, 39)
	FixtureMoves.step(game, P1, NORTH * 8.0 + UP * height, {"moving": true})
	return FixtureMoves.corrections(game, P1).size() > seen


## The top of the 5 cm step of the staircase of test_an_honest_climb... under `z`: the ground
## before SLOPE_FOOT.
func _on_slope(z: float) -> float:
	return maxf(0.0, 0.05 * ceilf((z - SLOPE_FOOT) / 0.05))


## A round of P1 on the stepped world.
func _round() -> Match:
	var world := FixtureTerrainWorld.new()
	world.add_platform(0, 6, 30, 8, 0.3).add_platform(0, 10, 30, 14, 0.9)
	return FixtureMoves.in_round([P1], world)


## The fields of a claim in the air, plus `more`.
func _air(more: Dictionary = {}) -> Dictionary:
	var fields := {"on_floor": false}
	fields.merge(more, true)
	return fields
