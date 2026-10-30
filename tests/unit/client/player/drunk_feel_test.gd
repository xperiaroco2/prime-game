extends GdUnitTestSuite
## DrunkFeel (#1391; ARCHITECTURE §4.7.6 "Drunk"): the strength follows the drunk value up to the
## mode's drunk_too_much_at and is 0 in a mode with no bar; the ease crosses 0..1 in the tuning's
## seconds without overshoot; the sway and the drift stay within their caps times the strength, are
## 0 when sober, are the same for the same clock and seed and differ between seeds; the drift's turn
## keeps a direction's length (a drifting walk is never faster). The tuning is the shipped `.tres`.

const TUNING := preload("res://client/player/player_tuning.tres")
## A clock long enough for both waves of each pair to peak, sampled every SAMPLE_S.
const LONG_S := 120.0
const SAMPLE_S := 0.05


func test_the_strength_follows_the_value_up_to_too_much_and_is_0_without_a_bar() -> void:
	assert_float(DrunkFeel.strength(0, 90, 1.0)).is_equal(0.0)
	assert_float(DrunkFeel.strength(45, 90, 1.0)).is_equal_approx(0.5, 0.0001)
	assert_float(DrunkFeel.strength(90, 90, 1.0)).is_equal(1.0)
	assert_float(DrunkFeel.strength(100, 90, 1.0)).is_equal(1.0)
	assert_float(DrunkFeel.strength(45, 90, 2.0)).is_equal_approx(0.25, 0.0001)
	# A mode with no bar (drunk_too_much_at 0): nothing, never a division by 0.
	assert_float(DrunkFeel.strength(50, 0, 1.0)).is_equal(0.0)
	# A curve of 0 (the script's default) is linear, not "everything at full".
	assert_float(DrunkFeel.strength(45, 90, 0.0)).is_equal_approx(0.5, 0.0001)
	var last := 0.0
	for drunk: int in range(0, 101):
		var now := DrunkFeel.strength(drunk, 90, TUNING.drunk_curve)
		assert_float(now).is_greater_equal(last)
		last = now


func test_the_ease_crosses_the_range_in_its_seconds_without_overshoot() -> void:
	var delta := 1.0 / 60.0
	var now := 1.0
	var steps := 0
	while now > 0.0 and steps < 1000:
		now = DrunkFeel.eased(now, 0.0, delta, 1.0)
		assert_float(now).is_greater_equal(0.0)
		steps += 1
	assert_int(steps).is_between(59, 61)
	assert_float(DrunkFeel.eased(0.2, 0.25, 0.5, 1.0)).is_equal(0.25)
	assert_float(DrunkFeel.eased(0.9, 0.1, delta, 0.0)).is_equal(0.1)


func test_sober_neither_sways_nor_drifts() -> void:
	assert_vector(DrunkFeel.sway(0.0, 3.0, 2, TUNING)).is_equal(Vector2.ZERO)
	assert_float(DrunkFeel.drift_angle(0.0, 3.0, 2, TUNING)).is_equal(0.0)
	var walk := Vector3(0.3, 0.0, -0.9)
	assert_vector(DrunkFeel.drifted(walk, 0.0)).is_equal(walk)


func test_the_sway_and_the_drift_stay_within_their_caps_times_the_strength() -> void:
	var roll_cap := deg_to_rad(TUNING.sway_roll_max_deg)
	var pitch_cap := deg_to_rad(TUNING.sway_pitch_max_deg)
	var drift_cap := DrunkFeel.max_drift_angle(TUNING)
	assert_float(roll_cap).is_greater(0.0)
	assert_float(drift_cap).is_greater(0.0)
	for strength: float in [0.5, 1.0]:
		var top := Vector3.ZERO
		var clock := 0.0
		while clock < LONG_S:
			var sway := DrunkFeel.sway(strength, clock, 2, TUNING)
			var drift := DrunkFeel.drift_angle(strength, clock, 2, TUNING)
			assert_float(absf(sway.x)).is_less_equal(roll_cap * strength + 0.000001)
			assert_float(absf(sway.y)).is_less_equal(pitch_cap * strength + 0.000001)
			assert_float(absf(drift)).is_less_equal(drift_cap * strength + 0.000001)
			top = top.max(Vector3(absf(sway.x), absf(sway.y), absf(drift)))
			clock += SAMPLE_S
		# It does sway and drift, to most of its cap.
		assert_float(top.x).is_greater(roll_cap * strength * 0.7)
		assert_float(top.y).is_greater(pitch_cap * strength * 0.7)
		assert_float(top.z).is_greater(drift_cap * strength * 0.7)


func test_the_same_clock_and_seed_give_the_same_and_seeds_differ() -> void:
	assert_vector(DrunkFeel.sway(0.8, 7.25, 2, TUNING)).is_equal(
		DrunkFeel.sway(0.8, 7.25, 2, TUNING)
	)
	assert_float(DrunkFeel.drift_angle(0.8, 7.25, 2, TUNING)).is_equal(
		DrunkFeel.drift_angle(0.8, 7.25, 2, TUNING)
	)
	# At the onset (clock 0) two players do not sway alike.
	(
		assert_bool(
			DrunkFeel.sway(1.0, 0.0, 2, TUNING).is_equal_approx(DrunkFeel.sway(1.0, 0.0, 3, TUNING))
		)
		. is_false()
	)
	(
		assert_bool(
			is_equal_approx(
				DrunkFeel.drift_angle(1.0, 0.0, 2, TUNING),
				DrunkFeel.drift_angle(1.0, 0.0, 3, TUNING)
			)
		)
		. is_false()
	)


func test_a_lean_turns_each_seed_to_its_own_side() -> void:
	var leaning: PlayerTuning = TUNING.duplicate()
	leaning.drift_wander_deg = 0.0
	leaning.drift_lean_deg = 10.0
	assert_float(DrunkFeel.drift_angle(1.0, 5.0, 2, leaning)).is_equal_approx(
		deg_to_rad(10.0), 0.0001
	)
	assert_float(DrunkFeel.drift_angle(0.5, 5.0, 3, leaning)).is_equal_approx(
		-deg_to_rad(5.0), 0.0001
	)
	assert_float(DrunkFeel.max_drift_angle(leaning)).is_equal_approx(deg_to_rad(10.0), 0.0001)


func test_the_drift_turns_the_walk_about_up_and_keeps_its_length() -> void:
	var walk := Vector3(0.0, 0.0, -4.5)
	for degrees: int in range(-30, 31, 5):
		var turned := DrunkFeel.drifted(walk, deg_to_rad(float(degrees)))
		assert_float(turned.length()).is_equal_approx(walk.length(), 0.0001)
		assert_float(turned.y).is_equal_approx(0.0, 0.0001)
		assert_float(rad_to_deg(walk.signed_angle_to(turned, Vector3.UP))).is_equal_approx(
			float(degrees), 0.001
		)
