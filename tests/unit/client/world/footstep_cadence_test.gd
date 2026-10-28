extends GdUnitTestSuite
## FootstepCadence (#525): the step interval as a pure function of the speed (walk vs run), and
## the cadence fed how far the drawn feet moved each frame: steps at that interval while walking,
## none while standing, none for a placement (a move no one could make in a frame); the quiet step
## (#792, #991): how quiet a step is by its speed (quiet at the crouch walk's, a walk's from the
## fast crouch's up), and the speed a step carries; the clip mode (#1334): steps on the drawn
## clip's foot contacts at the plan's rate, the phase starting again on a slot change.

const WALK := 4.5
const SPRINT := 7.0
const CROUCH := 2.0
const CROUCH_FAST := 2.8
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


func test_a_step_at_or_below_the_crouch_speed_is_wholly_quiet() -> void:
	assert_float(FootstepCadence.quiet_of(CROUCH, CROUCH, CROUCH_FAST)).is_equal(1.0)
	assert_float(FootstepCadence.quiet_of(1.0, CROUCH, CROUCH_FAST)).is_equal(1.0)
	assert_float(FootstepCadence.quiet_of(0.0, CROUCH, CROUCH_FAST)).is_equal(1.0)


func test_a_step_at_or_above_the_fast_crouch_speed_is_a_walks() -> void:
	# #991 (KD1 (b) changed): the fast crouch sounds like a walk; it was wholly quiet before.
	assert_float(FootstepCadence.quiet_of(CROUCH_FAST, CROUCH, CROUCH_FAST)).is_equal(0.0)
	assert_float(FootstepCadence.quiet_of(WALK, CROUCH, CROUCH_FAST)).is_equal(0.0)
	assert_float(FootstepCadence.quiet_of(SPRINT, CROUCH, CROUCH_FAST)).is_equal(0.0)


func test_between_the_crouch_and_the_fast_crouch_speed_the_quiet_eases_linearly() -> void:
	var middle := (CROUCH + CROUCH_FAST) / 2.0
	assert_float(FootstepCadence.quiet_of(middle, CROUCH, CROUCH_FAST)).is_equal_approx(0.5, 0.0001)
	var quarter := lerpf(CROUCH, CROUCH_FAST, 0.25)
	var eased := FootstepCadence.quiet_of(quarter, CROUCH, CROUCH_FAST)
	assert_float(eased).is_equal_approx(0.75, 0.0001)


func test_a_mode_without_a_crouch_speed_has_no_quiet_step() -> void:
	assert_float(FootstepCadence.quiet_of(1.0, 0.0, CROUCH_FAST)).is_equal(0.0)
	assert_float(FootstepCadence.quiet_of(0.0, 0.0, 0.0)).is_equal(0.0)


func test_equal_crouch_speeds_make_a_hard_edge() -> void:
	# PlayerRules.check lets crouch_fast_speed_mps equal crouch_speed_mps: no ease, but the crouch
	# walk stays quiet.
	assert_float(FootstepCadence.quiet_of(CROUCH, CROUCH, CROUCH)).is_equal(1.0)
	assert_float(FootstepCadence.quiet_of(1.0, CROUCH, CROUCH)).is_equal(1.0)
	assert_float(FootstepCadence.quiet_of(CROUCH + 0.01, CROUCH, CROUCH)).is_equal(0.0)
	assert_float(FootstepCadence.quiet_of(1.0, CROUCH, 1.5)).is_equal(1.0)
	assert_float(FootstepCadence.quiet_of(CROUCH + 0.01, CROUCH, 1.5)).is_equal(0.0)


func test_a_sneaking_step_at_or_below_the_crouch_walks_speed_is_silent() -> void:
	# #990: the sneak bit and a step at the crouch walk's speed, give or take the jitter margin.
	var edge := CROUCH + FootstepCadence.SNEAK_SPEED_MARGIN_MPS
	assert_float(FootstepCadence.SNEAK_SPEED_MARGIN_MPS).is_greater(0.0)
	assert_bool(FootstepCadence.silent_of(true, CROUCH, CROUCH)).is_true()
	assert_bool(FootstepCadence.silent_of(true, 1.0, CROUCH)).is_true()
	assert_bool(FootstepCadence.silent_of(true, edge, CROUCH)).is_true()


func test_a_sneaking_step_above_the_margin_is_heard() -> void:
	# A modified client that claims the sneak while it walks: heard (#989).
	var edge := CROUCH + FootstepCadence.SNEAK_SPEED_MARGIN_MPS
	assert_bool(FootstepCadence.silent_of(true, edge + 0.01, CROUCH)).is_false()
	assert_bool(FootstepCadence.silent_of(true, CROUCH_FAST, CROUCH)).is_false()
	assert_bool(FootstepCadence.silent_of(true, WALK, CROUCH)).is_false()


func test_a_step_without_the_sneak_bit_is_never_silent() -> void:
	assert_bool(FootstepCadence.silent_of(false, CROUCH, CROUCH)).is_false()
	assert_bool(FootstepCadence.silent_of(false, 1.0, CROUCH)).is_false()
	# Nor in a mode with no crouch speed (the sneak walks at it).
	assert_bool(FootstepCadence.silent_of(true, 0.0, 0.0)).is_false()


func test_a_step_carries_its_speed_over_the_step_not_one_frame() -> void:
	# Frames of 2.0 and 3.0 m/s alternate (an interpolated pose's jitter): the step's speed is
	# their mean; a standing frame between them neither counts nor resets it.
	var cadence := FootstepCadence.new()
	var stepped := false
	for i: int in 600:
		var speed := 2.0 if i % 2 == 0 else 3.0
		if i % 7 == 3:
			speed = 0.0
		if cadence.advance(Vector3(speed * FRAME, 0, 0), FRAME, WALK, SPRINT):
			stepped = true
			break
	assert_bool(stepped).is_true()
	assert_float(cadence.step_speed_mps).is_between(2.4, 2.6)


func test_the_clip_mode_steps_on_jog_fwd_s_contacts() -> void:
	# Jog_Fwd's table: a 0.917 s cycle, contacts at 0 and 0.458 s: a step every 0.458 s.
	var times := _clip_steps(_plan(&"Jog_Fwd", &"Front", 1.0), 0.917, 3.0)
	assert_float(times[0]).is_equal_approx(0.458, FRAME)
	for i: int in range(1, times.size()):
		assert_float(times[i] - times[i - 1]).is_equal_approx(0.4585, FRAME)
	assert_int(times.size()).is_equal(6)


func test_the_clip_mode_keeps_an_uneven_clip_s_rhythm() -> void:
	# Sprint_Fwd's table: 0.667 s, contacts at 0 and 0.375 s: gaps of 0.375 and 0.292 by turns.
	var times := _clip_steps(_plan(&"Sprint_Fwd", &"Sprint_Fwd", 1.0), 0.667, 2.0)
	assert_float(times[0]).is_equal_approx(0.375, FRAME)
	assert_float(times[1] - times[0]).is_equal_approx(0.292, FRAME)
	assert_float(times[2] - times[1]).is_equal_approx(0.375, FRAME)
	assert_float(times[3] - times[2]).is_equal_approx(0.292, FRAME)


func test_the_clip_mode_runs_at_the_plan_s_rate_over_the_real_cycle() -> void:
	# Twice the rate, half the gap; a clip twice as long (slice_m1's own lengths), twice the gap.
	var fast := _clip_steps(_plan(&"Jog_Fwd", &"Front", 2.0), 0.917, 2.0)
	assert_float(fast[1] - fast[0]).is_equal_approx(0.229, FRAME)
	var long := _clip_steps(_plan(&"Jog_Fwd", &"Front", 1.0), 1.834, 4.0)
	assert_float(long[1] - long[0]).is_equal_approx(0.917, FRAME)


func test_a_slot_change_starts_the_clip_s_phase_again() -> void:
	var cadence := FootstepCadence.new()
	var front := _plan(&"Jog_Fwd", &"Front", 1.0)
	# 0.4 s of Jog_Fwd: no step yet (its first contact after the start is at 0.458 s).
	for i: int in roundi(0.4 / FRAME):
		assert_bool(cadence.advance(_move(4.0), FRAME, WALK, SPRINT, front, 0.917)).is_false()
	# Backing off: Jog_Bwd from its start, its first contact 0.292 s in.
	var back := _plan(&"Jog_Bwd", &"Back", 1.0)
	var first := -1.0
	for i: int in roundi(1.0 / FRAME):
		if cadence.advance(_move(2.0), FRAME, WALK, SPRINT, back, 0.583):
			first = (i + 1) * FRAME
			break
	assert_float(first).is_equal_approx(0.292, FRAME)


func test_the_clip_mode_keeps_the_place_and_the_speed_and_resets_on_a_placement() -> void:
	var cadence := FootstepCadence.new()
	var plan := _plan(&"Jog_Fwd", &"Front", 1.0)
	for i: int in roundi(0.3 / FRAME):
		cadence.advance(_move(4.0), FRAME, WALK, SPRINT, plan, 0.917)
	# Still frames hold the phase: the step falls 0.158 s of moving later, not of time.
	for i: int in 30:
		assert_bool(cadence.advance(Vector3.ZERO, FRAME, WALK, SPRINT, plan, 0.917)).is_false()
	var count := 0
	for i: int in roundi(0.15 / FRAME):
		if cadence.advance(_move(4.0), FRAME, WALK, SPRINT, plan, 0.917):
			count += 1
	assert_int(count).is_equal(0)
	var stepped := false
	for i: int in 2:
		stepped = stepped or cadence.advance(_move(4.0), FRAME, WALK, SPRINT, plan, 0.917)
	assert_bool(stepped).is_true()
	assert_float(cadence.step_speed_mps).is_equal_approx(4.0, 0.01)
	# A placement: no step, and the phase starts again.
	assert_bool(cadence.advance(Vector3(50, 0, 0), FRAME, WALK, SPRINT, plan, 0.917)).is_false()
	var times := _clip_steps(plan, 0.917, 1.0, cadence)
	assert_float(times[0]).is_equal_approx(0.458, FRAME)


func test_a_plan_without_contacts_or_cycle_falls_back_to_the_speed() -> void:
	for case: Array in [[&"Idle", 0.917], [&"Jog_Fwd", 0.0], [&"Carry_Upper", 1.0]]:
		var cadence := FootstepCadence.new()
		var plan := _plan(case[0] as StringName, &"Front", 1.0)
		var count := 0
		for i: int in roundi(3.0 / FRAME):
			if cadence.advance(_move(WALK), FRAME, WALK, SPRINT, plan, case[1] as float):
				count += 1
		assert_int(count).is_equal(_expected(WALK, 3.0))


## The times (seconds from the start) of the steps `seconds` of moving at 4 m/s play in the clip
## mode with `plan` and `cycle_s`, frame by frame, on `cadence` (a new one when null).
func _clip_steps(
	plan: AvatarClips.Plan, cycle_s: float, seconds: float, cadence: FootstepCadence = null
) -> Array[float]:
	var on := cadence if cadence != null else FootstepCadence.new()
	var out: Array[float] = []
	for i: int in roundi(seconds / FRAME):
		if on.advance(_move(4.0), FRAME, WALK, SPRINT, plan, cycle_s):
			out.append((i + 1) * FRAME)
	return out


func _plan(base: StringName, slot: StringName, rate: float) -> AvatarClips.Plan:
	var out := AvatarClips.Plan.new()
	out.base = base
	out.slot = slot
	out.rate = rate
	return out


## One frame's move straight ahead at `speed`.
func _move(speed: float) -> Vector3:
	return Vector3(0, 0, -speed * FRAME)


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
