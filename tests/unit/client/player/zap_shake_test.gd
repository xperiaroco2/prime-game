extends GdUnitTestSuite
## The maths of the ship zap's camera shake (client/player/ZapShake, #1585): nothing before or after
## it, within the tuning's caps, fading to nothing, and the same answer for the same inputs.

const SECONDS := 0.4


func _tuning() -> PlayerTuning:
	var tuning := PlayerTuning.new()
	tuning.zap_shake_roll_deg = 2.5
	tuning.zap_shake_pitch_deg = 1.2
	tuning.zap_shake_hz = 14.0
	return tuning


func test_nothing_outside_the_shake() -> void:
	assert_vector(ZapShake.angles(0.0, SECONDS, _tuning())).is_equal(Vector2.ZERO)
	assert_vector(ZapShake.angles(-0.1, SECONDS, _tuning())).is_equal(Vector2.ZERO)
	assert_vector(ZapShake.angles(0.2, 0.0, _tuning())).is_equal(Vector2.ZERO)


func test_it_stays_within_the_caps_and_moves() -> void:
	var tuning := _tuning()
	var moved := false
	for step in 40:
		var angles := ZapShake.angles(SECONDS - step * 0.01, SECONDS, tuning)
		assert_float(absf(angles.x)).is_less_equal(deg_to_rad(tuning.zap_shake_roll_deg))
		assert_float(absf(angles.y)).is_less_equal(deg_to_rad(tuning.zap_shake_pitch_deg))
		moved = moved or angles.length() > 0.001
	assert_bool(moved).is_true()


func test_it_fades_towards_its_end() -> void:
	var tuning := _tuning()
	var early := 0.0
	var late := 0.0
	for step in 10:
		early = maxf(early, absf(ZapShake.angles(SECONDS - 0.05 - step * 0.01, SECONDS, tuning).x))
		late = maxf(late, absf(ZapShake.angles(0.1 - step * 0.01, SECONDS, tuning).x))
	assert_float(late).is_less(early)


func test_the_same_inputs_give_the_same_answer() -> void:
	var tuning := _tuning()
	var first := ZapShake.angles(0.3, SECONDS, tuning)
	assert_vector(ZapShake.angles(0.3, SECONDS, tuning)).is_equal(first)
