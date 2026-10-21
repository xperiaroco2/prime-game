extends GdUnitTestSuite
## The bot scenarios' fake world with storeys (tests/fixtures/storeyed_world.gd, #1209;
## ARCHITECTURE §9.7): its floors, its flights and their stairwells, the House's stairs joining its
## storeys for a walk, and a scenario's walk that would fall failing.

const StoreyedWorld := preload("res://tests/fixtures/storeyed_world.gd")
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
const MAP := "res://map.tscn"
const SCENARIOS := "res://content/scenarios/"
const HOUSE_SCENARIO := SCENARIOS + "bots_carry_items_between_the_house_storeys.tres"
## The walks over the House's stairs the scenarios take (HOUSE_SCENARIO): the pantry stairs down
## to storage, and the external stairs up to the balcony.
const PANTRY_DOWN: Array[Vector3] = [
	Vector3(27, 0, 29.6), Vector3(27, -1.6, 25), Vector3(25, -1.6, 25), Vector3(25, -3.2, 30)
]
const UPSTAIRS: Array[Vector3] = [Vector3(39, 0, 13.8), Vector3(39, 3.2, 22.2)]
## A bot's longest claim of travel: sprinting, one tick.
const CLAIM_M := 0.35
const STEP_M := 0.3


func test_the_floor_below_is_the_highest_storey_or_flight_at_or_below_the_point() -> void:
	var world := StoreyedWorld.new(MAP, [0.0, -3.0], [Vector3(0, -3, 0), Vector3(0, 0, 6)], 1.0)
	# Off the flight: the storeys, the highest at or below the point; none below the lowest.
	assert_vector(world.floor_below(Vector3(5, 1, 3))).is_equal(Vector3(5, 0, 3))
	assert_vector(world.floor_below(Vector3(5, -1, 3))).is_equal(Vector3(5, -3, 3))
	assert_vector(world.floor_below(Vector3(5, -4, 3))).is_equal(WorldQuery.NO_FLOOR)
	# Over the flight: its slope, rising evenly from its bottom to its top.
	assert_vector(world.floor_below(Vector3(0, -1, 3))).is_equal_approx(
		Vector3(0, -1.5, 3), Vector3.ONE * 0.0001
	)
	assert_vector(world.floor_below(Vector3(0.4, -1, 3))).is_equal_approx(
		Vector3(0.4, -1.5, 3), Vector3.ONE * 0.0001
	)
	# The upper storey is cut out over the flight (its stairwell); beside it, it is not.
	assert_vector(world.floor_below(Vector3(0, 0.5, 3))).is_equal_approx(
		Vector3(0, -1.5, 3), Vector3.ONE * 0.0001
	)
	assert_vector(world.floor_below(Vector3(0.6, 0.5, 3))).is_equal(Vector3(0.6, 0, 3))
	# The lower storey, at the flight's bottom, is not cut: under the flight's slope it is the floor.
	assert_vector(world.floor_below(Vector3(0, -2.9, 3))).is_equal(Vector3(0, -3, 3))
	# Past either end the flight is not there.
	assert_vector(world.floor_below(Vector3(0, 0.5, 6.5))).is_equal(Vector3(0, 0, 6.5))
	assert_vector(world.floor_below(Vector3(0, -2, -0.5))).is_equal(Vector3(0, -3, -0.5))
	assert_vector(world.stand_floor_below(Vector3(0, -1, 3))).is_equal(
		world.floor_below(Vector3(0, -1, 3))
	)


func test_another_level_is_one_flat_floor_at_y_0() -> void:
	# Match tells the world the level of each phase it enters (use_level): the lobby is flat.
	var world := StoreyedWorld.new(MAP, [0.0, -3.0], [Vector3(0, -3, 0), Vector3(0, 0, 6)], 1.0)
	world.use_level("res://lobby.tscn")
	assert_vector(world.floor_below(Vector3(0, 0.5, 3))).is_equal(Vector3(0, 0, 3))
	assert_vector(world.floor_below(Vector3(5, -1, 3))).is_equal(WorldQuery.NO_FLOOR)
	assert_vector(world.sweep(Vector3(0, 2, 3), Vector3(0, -2, 3), 0.1)).is_equal_approx(
		Vector3(0, 0.1, 3), Vector3.ONE * 0.0001
	)
	world.use_level(MAP)
	assert_vector(world.floor_below(Vector3(0, 0.5, 3))).is_equal_approx(
		Vector3(0, -1.5, 3), Vector3.ONE * 0.0001
	)


func test_a_sweep_stops_on_the_floor_below_its_start() -> void:
	var world := StoreyedWorld.new(MAP, [0.0, -3.0], [], 1.0)
	# From above the ground floor, a fall stops on it; from the basement, on the basement's.
	assert_vector(world.sweep(Vector3(0, 2, 0), Vector3(0, -2, 0), 0.1)).is_equal_approx(
		Vector3(0, 0.1, 0), Vector3.ONE * 0.0001
	)
	assert_vector(world.sweep(Vector3(0, -1, 0), Vector3(0, -5, 0), 0.1)).is_equal_approx(
		Vector3(0, -2.9, 0), Vector3.ONE * 0.0001
	)


func test_the_house_plays_in_the_storeyed_world_and_a_flat_map_on_one_floor() -> void:
	var house := load(HOUSE_SCENARIO) as BotScenario
	assert_str(house.played_map()).is_equal(ScenarioLevels.HOUSE)
	assert_bool(ScenarioLevels.world_of(house) is StoreyedWorld).is_true()
	var flat := BotScenario.new()
	flat.mode = load(BASE_MODE) as GameMode
	var world := ScenarioLevels.world_of(flat)
	assert_bool(world is StoreyedWorld).is_false()
	assert_bool(world is FlatWorldQuery).is_true()


func test_the_house_s_stairs_join_its_storeys_for_a_walk() -> void:
	var house := ScenarioLevels.world_of(load(HOUSE_SCENARIO) as BotScenario)
	# Down the pantry stairs from the ground floor to storage, and back up.
	assert_float(_walk(house, PANTRY_DOWN).y).is_equal_approx(-3.2, 0.0001)
	var up := PANTRY_DOWN.duplicate()
	up.reverse()
	assert_float(_walk(house, up).y).is_equal_approx(0.0, 0.0001)
	# Up the external stairs to the balcony, and back down.
	assert_float(_walk(house, UPSTAIRS).y).is_equal_approx(3.2, 0.0001)
	var down := UPSTAIRS.duplicate()
	down.reverse()
	assert_float(_walk(house, down).y).is_equal_approx(0.0, 0.0001)
	# Across the pantry's stairwell on the ground floor, a walk falls: the stairs are no floor there.
	var across: Array[Vector3] = [Vector3(30, 0, 27), Vector3(24, 0, 27)]
	var fell := _walk(house, across, false)
	assert_float(fell.y).is_less(-1.0)


func test_a_stalled_walk_of_several_ticks_a_claim_still_climbs_the_stairs() -> void:
	# After a stall over ENet one claim covers several ticks (two sprint ticks 0.7 m, three 1.05 m):
	# the lookup reaches a step and the claim's travel up, so the flight is found, not the floor
	# under it.
	var house := ScenarioLevels.world_of(load(HOUSE_SCENARIO) as BotScenario)
	for claim_m: float in [0.7, 1.05]:
		assert_float(_walk(house, UPSTAIRS, true, claim_m).y).is_equal_approx(3.2, 0.0001)
		assert_float(_walk(house, PANTRY_DOWN, true, claim_m).y).is_equal_approx(-3.2, 0.0001)


func test_a_walk_that_would_fall_fails_and_names_the_stairs() -> void:
	# A House scenario's bot walks to the pantry's stairwell, then across it on the ground floor.
	var scenario := load(HOUSE_SCENARIO).duplicate(true) as BotScenario
	var steps: Array[ScenarioStep] = scenario.steps_of(1).slice(0, 2)
	for at: Vector3 in [Vector3(30, 0, 27), Vector3(24, 0, 27)]:
		var target := ScenarioTarget.new()
		target.point = at
		var walk := StepWalkTo.new()
		walk.target = target
		walk.sprint = true
		walk.stop_m = 0.0
		steps.append(walk)
	# The other bots only ready up and wait for the round.
	scenario.scripts[0].steps = steps
	for bot in range(2, scenario.bots + 1):
		scenario.scripts[bot - 1].steps = scenario.steps_of(bot).slice(0, 2)
	var runner := ScenarioRunner.play(scenario)
	var text := "\n".join(runner.failures)
	assert_str(text).contains("bot 1").contains("step 4 (WalkTo)").contains(
		"route it over the stairs"
	)


## Walks `points` in claims of `claim_m`, each standing on the floor found from a step and the
## claim's travel above the last claim's feet, as ScenarioPlay's walk
## does; asserts no claim falls (unless `honest` is false) and returns where it ends.
func _walk(
	world: WorldQuery, points: Array[Vector3], honest: bool = true, claim_m: float = CLAIM_M
) -> Vector3:
	var at := points[0]
	var lowest_drop := 0.0
	for target: Vector3 in points.slice(1):
		while Vector2(target.x - at.x, target.z - at.z).length() > 0.0001:
			var flat := Vector3(target.x - at.x, 0.0, target.z - at.z)
			var travel := minf(claim_m, flat.length())
			var to := at + flat.normalized() * travel
			var below := world.floor_below(Vector3(to.x, at.y + STEP_M + travel, to.z))
			assert_vector(below).is_not_equal(WorldQuery.NO_FLOOR)
			if below == WorldQuery.NO_FLOOR:
				return at
			lowest_drop = maxf(lowest_drop, at.y - below.y - travel)
			if honest:
				(
					assert_float(at.y - below.y)
					. override_failure_message("a fall at %s" % to)
					. is_less_equal(STEP_M + travel)
				)
				(
					assert_float(below.y - at.y)
					. override_failure_message("a climb past a step at %s" % to)
					. is_less_equal(STEP_M + travel)
				)
			to.y = below.y
			at = to
	if not honest:
		assert_float(lowest_drop).is_greater(STEP_M)
	return at
