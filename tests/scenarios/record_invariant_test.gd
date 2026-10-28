extends GdUnitTestSuite
## The record invariant (ScenarioInvariants.record_problems, the photo ADR §8, #781) over
## hand-built ShotTaken records: a good row passes; a dead player's row, a row beyond the bound, a
## row far from every accepted position and a peer named twice are each caught. P9 (#788) plants
## the record builder's bug over House's shots.

const LENS := Vector3(0, 1.6, 0)
const RANGE_M := 10.0
const STEP_M := 1.0


func _row(peer: int, at: Vector3) -> Dictionary:
	return {
		"peer": peer,
		"position": at,
		"facing": Vector3.FORWARD,
		"downed": false,
		"held_item": -1,
		"belt_item": -1,
		"belt_item2": -1,
	}


func _problems(rows: Array, living: PackedInt32Array, accepted: Dictionary) -> PackedStringArray:
	var earlier: Dictionary[int, Vector3] = {}
	earlier.assign(accepted)
	var lists: Array[Dictionary] = [earlier, {}]
	return ScenarioInvariants.record_problems(rows, LENS, RANGE_M, STEP_M, living, lists)


func test_a_row_where_its_player_stands_in_range_passes() -> void:
	var at := Vector3(0, 0, -5)
	var problems := _problems([_row(2, at)], PackedInt32Array([1, 2]), {1: Vector3.ZERO, 2: at})
	assert_array(Array(problems)).is_empty()


func test_a_row_at_the_bound_passes_and_beyond_it_is_caught() -> void:
	var edge := RANGE_M + PhotoTask.RECORD_MARGIN_M + STEP_M
	var inside := LENS + Vector3(0, 0, -edge + 0.01)
	var beyond := LENS + Vector3(0, 0, -edge - 0.01)
	var good := _problems([_row(2, inside)], PackedInt32Array([2]), {2: inside})
	assert_array(Array(good)).is_empty()
	var bad := _problems([_row(2, beyond)], PackedInt32Array([2]), {2: beyond})
	assert_int(bad.size()).is_equal(1)
	assert_str(bad[0]).contains("from the lens")


func test_a_dead_players_row_is_caught() -> void:
	var at := Vector3(0, 0, -3)
	var problems := _problems([_row(3, at)], PackedInt32Array([1, 2]), {3: at})
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("not alive or downed")


func test_a_row_a_step_away_from_every_accepted_position_is_caught() -> void:
	var at := Vector3(0, 0, -3)
	var near := _problems([_row(2, at)], PackedInt32Array([2]), {2: at + Vector3(STEP_M, 0, 0)})
	assert_array(Array(near)).is_empty()
	var far := _problems(
		[_row(2, at)], PackedInt32Array([2]), {2: at + Vector3(STEP_M + 0.1, 0, 0)}
	)
	assert_int(far.size()).is_equal(1)
	assert_str(far[0]).contains("a step away")


func test_a_row_matching_only_the_later_accepted_position_passes() -> void:
	var at := Vector3(0, 0, -3)
	var earlier: Dictionary[int, Vector3] = {2: at + Vector3(5, 0, 0)}
	var now: Dictionary[int, Vector3] = {2: at}
	var lists: Array[Dictionary] = [earlier, now]
	var problems := ScenarioInvariants.record_problems(
		[_row(2, at)], LENS, RANGE_M, STEP_M, PackedInt32Array([2]), lists
	)
	assert_array(Array(problems)).is_empty()


func test_a_peer_named_twice_is_caught() -> void:
	var at := Vector3(0, 0, -3)
	var problems := _problems([_row(2, at), _row(2, at)], PackedInt32Array([2]), {2: at})
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("twice")


func test_the_step_is_the_widest_claim() -> void:
	var rules := PlayerRules.new()
	rules.sprint_speed_mps = 6.0
	var ticks := MovementRule.MAX_TICK_CREDIT + MovementRule.PUSH_TICKS
	var expected := ticks * 6.0 / Ticks.RATE + MovementRule.DISTANCE_SLACK_M
	assert_float(ScenarioInvariants.record_step(rules)).is_equal_approx(expected, 1e-6)
	assert_float(ScenarioInvariants.record_step(null)).is_equal(0.0)


func test_the_photo_task_is_found_by_its_camera_kind() -> void:
	var camera := StationKind.new()
	camera.id = &"camera"
	var task := PhotoTask.new()
	task.camera = camera
	var mode := GameMode.new()
	mode.task_types.append(task)
	assert_object(ScenarioInvariants.photo_task_of(mode, &"camera")).is_same(task)
	assert_object(ScenarioInvariants.photo_task_of(mode, &"board")).is_null()
