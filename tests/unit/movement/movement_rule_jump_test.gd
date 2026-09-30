extends GdUnitTestSuite
## MovementRule's jumps and heights (ARCHITECTURE §7, §7.1): a jump needs a WorldQuery floor
## within step height below the last accepted feet, and stamina for the living; the feet stay
## within the jump height (plus MovementRule.jump_slack) of the take-off until the next landing; a
## rise without a jump stays within the step height (plus STEP_CLEARANCE and the slope allowance).
## Players are placed at z = 5 on the ground (y = 0); the world has a 0.3 m step at z 6 to 8 and a
## 0.9 m ledge at z 10 to 14.

const P1 := 1
const UP := Vector3(0, 1, 0)
const NORTH := Vector3(0, 0, 1)
## The jump height (1 m) plus the slack: 0.4 * (1 - cos 45°) + 0.01, about 0.127 m.
const PEAK := 1.12
const OVER_PEAK := 1.14


func test_a_jump_from_the_floor_costs_its_stamina_and_rises_to_the_jump_height() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
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
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(90000)
	FixtureMoves.claim(game, P1, Vector3(player.position.x, 0.2 + OVER_PEAK, 5), _air())
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


func test_a_jump_needs_a_world_query_floor_within_step_height() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	# The claim says it stands on the floor 0.305 m above the ground, where WorldQuery finds no
	# floor within the step height (0.3 m).
	FixtureMoves.step(game, P1, UP * 0.305)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(100000)


func test_a_second_jump_in_the_air_is_corrected() -> void:
	var game := _round()
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	FixtureMoves.step(game, P1, UP * 0.3, _air())
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.3, _air({"jumped": true}))
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
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(9750)
	# One more tick passed: 10500 covers it, and 500 is left.
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(500)
	var last: SelfStatusEvent = FixtureMoves.statuses(game, P1).back()
	assert_int(last.stamina).is_equal(500)
	assert_bool(last.sprint_available).is_false()


func test_a_ghost_jumps_without_stamina_and_no_higher() -> void:
	var game := _round()
	var ghost := game.state.player(P1)
	ghost.life = PlayerState.Life.GHOST
	ghost.stamina = 0
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := ghost.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	FixtureMoves.claim(game, P1, ground + UP * PEAK, _air())
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(ghost.stamina).is_equal(0)
	FixtureMoves.claim(game, P1, ground + UP * OVER_PEAK, _air())
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
	# 0.5 m north: up to 0.3 + 0.01 + 0.5 * tan 45° = 0.81 m higher, as up a 45° slope.
	FixtureMoves.step(game, P1, NORTH * 0.5 + UP * 0.8, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	# 0.5 m further north, 0.85 m above the base (the ground): corrected.
	FixtureMoves.claim(game, P1, ground + NORTH * 1.0 + UP * 0.85, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)


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
	var fields := _air({"jumped": true, "moving": true})
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.2, fields)
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.6, _air({"moving": true}))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * 0.2, _air({"moving": true}))
	FixtureMoves.step(game, P1, NORTH * 0.2 + UP * -0.1, {"moving": true})
	assert_float(player.position.z).is_greater(10.0)
	assert_float(player.position.y).is_equal_approx(0.9, 1e-5)
	var ledge := player.position
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	FixtureMoves.claim(game, P1, ledge + UP * PEAK, _air())
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_less(85000)


func test_the_jump_bound_lasts_only_until_the_next_landing() -> void:
	var game := _round()
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ground := player.position
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
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
	FixtureMoves.step(game, P1, UP * 0.1, _air({"jumped": true}))
	FixtureMoves.step(game, P1, UP * 0.5, _air({"jumped": true}))
	FixtureMoves.step(game, P1, UP * -0.1, {"moving": true})
	FixtureMoves.steps(game, P1, 3, NORTH * 0.3, FixtureMoves.sprinting())
	var replayed := Match.replay(game.command_log, FixtureModes.basic())
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))
	assert_array(game.command_log.world_answers).is_not_empty()


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
