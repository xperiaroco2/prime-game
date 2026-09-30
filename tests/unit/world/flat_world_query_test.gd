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
	var log := CommandLog.new()
	var recording := RecordingWorldQuery.new(inner, log)
	recording.use_level("res://a.tscn")
	assert_array(Array(inner.calls)).is_equal(["use_level res://a.tscn"])
	assert_array(log.world_answers).is_empty()
	var replay := ReplayWorldQuery.new([])
	replay.use_level("res://a.tscn")
	assert_bool(replay.diverged).is_false()
	assert_int(replay.unread()).is_equal(0)
