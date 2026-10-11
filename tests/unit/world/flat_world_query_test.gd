extends GdUnitTestSuite
## FlatWorldQuery, the fake geometry of the tests and the core scenario runner, and the recording
## and replaying wrappers that put WorldQuery answers into the command log (ARCHITECTURE §3.3,
## §7.1).

const WALL := AABB(Vector3(2, 0, -5), Vector3(0.2, 3, 10))


func test_the_floor_is_below_every_point_above_it() -> void:
	var world := FlatWorldQuery.new(0.5)
	assert_vector(world.floor_below(Vector3(3, 2, -1))).is_equal(Vector3(3, 0.5, -1))
	assert_vector(world.floor_below(Vector3(3, 0.5, -1))).is_equal(Vector3(3, 0.5, -1))
	assert_bool(world.floor_below(Vector3(3, 0, -1)) == WorldQuery.NO_FLOOR).is_true()


func test_walls_block_the_line_of_sight() -> void:
	var world := FlatWorldQuery.new().add_wall(WALL)
	assert_bool(world.line_of_sight(Vector3(0, 1, 0), Vector3(4, 1, 0))).is_false()
	assert_bool(world.line_of_sight(Vector3(0, 1, 0), Vector3(1.9, 1, 0))).is_true()
	assert_bool(world.line_of_sight(Vector3(0, 4, 0), Vector3(4, 4, 0))).is_true()
	assert_bool(FlatWorldQuery.new().line_of_sight(Vector3.ZERO, Vector3(99, 0, 0))).is_true()


func test_a_placed_item_rests_on_the_floor() -> void:
	var world := FlatWorldQuery.new()
	assert_vector(world.rest_position(Vector3(0, 1, 0), Vector3(1, 1, 0))).is_equal(
		Vector3(1, 0, 0)
	)


func test_a_placed_item_stops_before_a_wall() -> void:
	var world := FlatWorldQuery.new().add_wall(WALL)
	var rest := world.rest_position(Vector3(0, 1, 0), Vector3(4, 1, 0))
	assert_float(rest.x).is_equal_approx(2.0 - FlatWorldQuery.WALL_MARGIN, 0.0001)
	assert_float(rest.y).is_equal(0.0)


func test_answers_are_recorded_and_replayed_in_order() -> void:
	var recorded := CommandLog.new()
	var recording := RecordingWorldQuery.new(FlatWorldQuery.new().add_wall(WALL), recorded)
	var a := recording.line_of_sight(Vector3(0, 1, 0), Vector3(4, 1, 0))
	var b := recording.floor_below(Vector3(1, 3, 1))
	var c := recording.rest_position(Vector3(0, 1, 0), Vector3(4, 1, 0))
	var d := recording.stand_floor_below(Vector3(2, 5, 2))
	assert_vector(d).is_equal(Vector3(2, 0, 2))
	assert_array(recorded.world_answers).is_equal([a, b, c, d])
	var replay := ReplayWorldQuery.new(recorded.world_answers)
	assert_bool(replay.line_of_sight(Vector3.ZERO, Vector3.ZERO)).is_equal(a)
	assert_vector(replay.floor_below(Vector3.ZERO)).is_equal(b)
	assert_vector(replay.rest_position(Vector3.ZERO, Vector3.ZERO)).is_equal(c)
	assert_vector(replay.stand_floor_below(Vector3.ZERO)).is_equal(d)
	assert_bool(replay.diverged).is_false()


func test_a_replay_that_asks_something_else_diverges() -> void:
	var replay := ReplayWorldQuery.new([true])
	replay.floor_below(Vector3.ZERO)
	assert_bool(replay.diverged).is_true()


func test_the_recording_forwards_use_level_without_an_answer_and_the_replay_ignores_it() -> void:
	var inner := FixtureLevelWorld.new()
	var command_log := CommandLog.new()
	var recording := RecordingWorldQuery.new(inner, command_log)
	recording.use_level("res://a.tscn")
	assert_array(Array(inner.calls)).is_equal(["use_level res://a.tscn"])
	assert_array(command_log.world_answers).is_empty()
	var replay := ReplayWorldQuery.new([])
	replay.use_level("res://a.tscn")
	assert_bool(replay.diverged).is_false()
	assert_int(replay.unread()).is_equal(0)


func test_a_sweep_with_nothing_in_the_way_reaches_its_end() -> void:
	var world := FlatWorldQuery.new().add_wall(WALL)
	var to := Vector3(1.5, 1, 3)
	assert_vector(world.sweep(Vector3(0, 1, 0), to, 0.15)).is_equal(to)


func test_a_sweep_stops_where_the_sphere_touches_a_wall_or_the_floor() -> void:
	var world := FlatWorldQuery.new().add_wall(WALL)
	var at_wall := world.sweep(Vector3(0, 1, 0), Vector3(4, 1, 0), 0.15)
	assert_vector(at_wall).is_equal_approx(Vector3(1.85, 1, 0), Vector3.ONE * 1e-4)
	var at_floor := world.sweep(Vector3(0, 1, 0), Vector3(0, -1, 1), 0.25)
	assert_vector(at_floor).is_equal_approx(Vector3(0, 0.25, 0.375), Vector3.ONE * 1e-4)
	# The nearer of the two: the floor before the wall.
	var low := world.sweep(Vector3(0, 1, 0), Vector3(4, -1, 0), 0.25)
	assert_vector(low).is_equal_approx(Vector3(1.5, 0.25, 0), Vector3.ONE * 1e-4)


func test_a_sweep_that_starts_touching_the_world_answers_its_start() -> void:
	var world := FlatWorldQuery.new().add_wall(WALL)
	var at_wall := Vector3(1.9, 1, 0)
	assert_vector(world.sweep(at_wall, Vector3(0, 1, 0), 0.15)).is_equal(at_wall)
	var on_floor := Vector3(0, 0.1, 0)
	assert_vector(world.sweep(on_floor, Vector3(0, 3, 0), 0.15)).is_equal(on_floor)


func test_the_terrain_fixture_s_platforms_stop_a_sweep() -> void:
	var world := FixtureTerrainWorld.new()
	world.add_platform(2, -1, 4, 1, 0.5)
	var into_side := world.sweep(Vector3(0, 0.3, 0), Vector3(3, 0.3, 0), 0.1)
	assert_vector(into_side).is_equal_approx(Vector3(1.9, 0.3, 0), Vector3.ONE * 1e-4)
	var onto_top := world.sweep(Vector3(3, 2, 0), Vector3(3, 0, 0), 0.1)
	assert_vector(onto_top).is_equal_approx(Vector3(3, 0.6, 0), Vector3.ONE * 1e-4)
	var over := Vector3(5, 0.7, 0)
	assert_vector(world.sweep(Vector3(1, 0.7, 0), over, 0.1)).is_equal(over)


func test_sweep_answers_are_recorded_and_replayed() -> void:
	var inner := FixtureLevelWorld.new()
	inner.add_wall(WALL)
	var recorded := CommandLog.new()
	var recording := RecordingWorldQuery.new(inner, recorded)
	var a := recording.sweep(Vector3(0, 1, 0), Vector3(4, 1, 0), 0.15)
	var b := recording.sweep(Vector3(0, 1, 0), Vector3(0, 1, 1), 0.15)
	assert_array(Array(inner.calls)).is_equal(["sweep", "sweep"])
	assert_array(recorded.world_answers).is_equal([a, b])
	var replay := ReplayWorldQuery.new(recorded.world_answers)
	assert_vector(replay.sweep(Vector3.ZERO, Vector3.ONE, 1.0)).is_equal(a)
	assert_vector(replay.sweep(Vector3.ZERO, Vector3.ONE, 1.0)).is_equal(b)
	assert_bool(replay.diverged).is_false()
	assert_int(replay.unread()).is_equal(0)
