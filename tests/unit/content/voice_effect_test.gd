extends GdUnitTestSuite
## VoiceEffect (#1392; ARCHITECTURE §9.4.5): its class defaults change nothing, value_at scales the
## swing by the strength (0 to 255, clamped) around `rest`, steady or as a sine of `wobble_hz`,
## and its check names an empty class or parameter and numbers out of bounds. Built in code: a
## part's unit test never loads content/ (§9.6).


func test_the_class_defaults_change_nothing() -> void:
	var effect := VoiceEffect.new()
	assert_float(effect.swing).is_equal(0.0)
	assert_float(effect.wobble_hz).is_equal(0.0)
	for strength: int in [0, 128, 255]:
		assert_float(effect.value_at(strength, 0.3)).is_equal(effect.rest)


func test_a_steady_effect_scales_its_swing_by_the_strength() -> void:
	var effect := _effect(1.0, 0.2, 0.0)
	assert_float(effect.value_at(0, 0.0)).is_equal(1.0)
	assert_float(effect.value_at(255, 0.0)).is_equal_approx(1.2, 1e-6)
	assert_float(effect.value_at(51, 7.0)).is_equal_approx(1.04, 1e-6)
	# Out of the wire's range: clamped.
	assert_float(effect.value_at(400, 0.0)).is_equal_approx(1.2, 1e-6)
	assert_float(effect.value_at(-3, 0.0)).is_equal(1.0)


func test_a_wobble_swings_around_rest_at_its_rate() -> void:
	var effect := _effect(1.0, 0.2, 0.5)
	# Period 2 s: rest at the zeros, the full swing at the peaks.
	assert_float(effect.value_at(255, 0.0)).is_equal_approx(1.0, 1e-6)
	assert_float(effect.value_at(255, 0.5)).is_equal_approx(1.2, 1e-6)
	assert_float(effect.value_at(255, 1.0)).is_equal_approx(1.0, 1e-6)
	assert_float(effect.value_at(255, 1.5)).is_equal_approx(0.8, 1e-6)
	# Half the strength, half the swing.
	assert_float(effect.value_at(255 / 2, 0.5)).is_equal_approx(1.0 + 0.2 * 127 / 255.0, 1e-6)
	# Sober: rest whatever the clock.
	assert_float(effect.value_at(0, 0.5)).is_equal(1.0)


func test_a_whole_effect_passes_its_check() -> void:
	var effect := _effect(1.0, 0.2, 0.5)
	effect.settings = {"fft_size": 2}
	assert_array(Array(effect.check(null))).is_empty()


func test_the_check_names_each_problem() -> void:
	var effect := VoiceEffect.new()
	effect.wobble_hz = 6.0
	effect.swing = -30000.0
	effect.settings = {3: 1}
	(
		assert_array(Array(effect.check(null)))
		. contains_exactly_in_any_order(
			[
				"bus_effect is empty",
				"parameter is empty",
				"settings has the key 3, which is not a property name",
				"swing is -30000, outside -20000 to 20000",
				"wobble_hz is 6, outside 0 to 5",
			]
		)
	)


static func _effect(rest: float, swing: float, wobble_hz: float) -> VoiceEffect:
	var effect := VoiceEffect.new()
	effect.id = &"wobble"
	effect.bus_effect = &"FixtureBusEffect"
	effect.parameter = &"depth"
	effect.rest = rest
	effect.swing = swing
	effect.wobble_hz = wobble_hz
	return effect
