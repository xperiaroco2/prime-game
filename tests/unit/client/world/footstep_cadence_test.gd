extends GdUnitTestSuite
## FootstepCadence (#525): the step interval as a pure function of the speed (walk vs run), and
## the cadence fed how far the drawn feet moved each frame: steps at that interval while walking,
## none while standing, none for a placement (a move no one could make in a frame).

const WALK := 4.5
const SPRINT := 7.0
const FRAME := 1.0 / 60.0


func test_standing_has_no_interval() -> void:
	assert_bool(is_inf(FootstepCadence.interval_s(0.0, WALK, SPRINT))).is_true()
	var slow := FootstepCadence.MIN_SPEED_MPS - 0.01
	assert_bool(is_inf(FootstepCadence.interval_s(slow, WALK, SPRINT))).is_true()
	# A mode with no speed steps never.
	assert_bool(is_inf(FootstepCadence.interval_s(3.0, 0.0, 0.0))).is_true()


func test_the_interval_at_walk_and_sprint_speed() -> void:
	var walk := FootstepCadence.interval_s(WALK, WALK, SPRINT)
	var sprint := FootstepCadence.interval_s(SPRINT, WALK, SPRINT)
	assert_float(walk).is_equal_approx(FootstepCadence.WALK_INTERVAL_S, 0.0001)
	assert_float(sprint).is_equal_approx(FootstepCadence.SPRINT_INTERVAL_S, 0.0001)
	# Running steps come faster than walking ones, and a speed between lies between.
	assert_float(sprint).is_less(walk)
	var between := FootstepCadence.interval_s((WALK + SPRINT) / 2.0, WALK, SPRINT)
	assert_float(between).is_between(sprint, walk)
	# Below walk speed the walk stride holds: slower feet, longer intervals.
	var stride := WALK * FootstepCadence.WALK_INTERVAL_S
	assert_float(FootstepCadence.interval_s(2.0, WALK, SPRINT)).is_equal_approx(
		stride / 2.0, 0.0001
	)
	assert_float(FootstepCadence.interval_s(2.0, WALK, SPRINT)).is_greater(walk)


func test_walking_steps_once_per_interval() -> void:
	assert_int(_steps(WALK, 3.0)).is_equal(_expected(WALK, 3.0))
	assert_int(_steps(SPRINT, 3.0)).is_equal(_expected(SPRINT, 3.0))
	assert_int(_steps(SPRINT, 3.0)).is_greater(_steps(WALK, 3.0))


func test_standing_still_never_steps() -> void:
	assert_int(_steps(0.0, 3.0)).is_equal(0)
	assert_int(_steps(FootstepCadence.MIN_SPEED_MPS * 0.5, 3.0)).is_equal(0)


func test_a_still_frame_keeps_the_place_in_the_step() -> void:
	# A frame with no movement between two snapshots neither steps nor starts the step again.
	var cadence := FootstepCadence.new()
	cadence.advance(Vector3(WALK * FRAME, 0, 0), FRAME, WALK, SPRINT)
	var progress := cadence.progress
	assert_bool(cadence.advance(Vector3.ZERO, FRAME, WALK, SPRINT)).is_false()
	assert_float(cadence.progress).is_equal(progress)


func test_a_placement_plays_no_step_and_starts_again() -> void:
	var cadence := FootstepCadence.new()
	cadence.progress = 0.99
	# 10 m in one frame: a respawn, a round start, the host's correction.
	assert_bool(cadence.advance(Vector3(10, 0, 0), FRAME, WALK, SPRINT)).is_false()
	assert_float(cadence.progress).is_equal(FootstepCadence.START)
	# Just under what SnapshotBuffer lets anyone move is a step's worth of movement.
	var fastest := SnapshotBuffer.SNAP_SPEED_MPS * FRAME * 0.99
	cadence.progress = 0.99
	assert_bool(cadence.advance(Vector3(fastest, 0, 0), FRAME, WALK, SPRINT)).is_true()


func test_only_horizontal_movement_counts() -> void:
	# Falling or riding a lift straight up is no walk.
	var cadence := FootstepCadence.new()
	for i: int in 120:
		assert_bool(cadence.advance(Vector3(0, -WALK * FRAME, 0), FRAME, WALK, SPRINT)).is_false()


## How many steps `seconds` of walking at `speed` play, frame by frame.
func _steps(speed: float, seconds: float) -> int:
	var cadence := FootstepCadence.new()
	var count := 0
	for i: int in roundi(seconds / FRAME):
		if cadence.advance(Vector3(0, 0, -speed * FRAME), FRAME, WALK, SPRINT):
			count += 1
	return count


## The steps `seconds` at `speed` hold: the first half an interval in, then one per interval.
func _expected(speed: float, seconds: float) -> int:
	var interval := FootstepCadence.interval_s(speed, WALK, SPRINT)
	return floori((seconds - interval * (1.0 - FootstepCadence.START)) / interval + 0.0001) + 1
