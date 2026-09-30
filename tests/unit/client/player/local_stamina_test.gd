extends GdUnitTestSuite
## The local stamina stand-in follows §7.1 and Q7: walking is always free, a sprint and a jump need
## their full cost, a started sprint lasts until 0. Numbers come from the tuning resource.

var _tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")


func test_starts_full() -> void:
	var stamina := LocalStamina.new(_tuning)
	assert_float(stamina.get_stamina()).is_equal(_tuning.max_stamina)


func test_sprint_needs_the_start_threshold_to_start() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = _tuning.sprint_start_stamina
	assert_bool(stamina.can_sprint(false)).is_true()
	stamina.stamina = _tuning.sprint_start_stamina - 0.01
	assert_bool(stamina.can_sprint(false)).is_false()


func test_a_started_sprint_lasts_until_zero() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = 0.01
	assert_bool(stamina.can_sprint(true)).is_true()
	stamina.stamina = 0.0
	assert_bool(stamina.can_sprint(true)).is_false()


func test_jump_needs_its_full_cost() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = _tuning.jump_cost
	assert_bool(stamina.can_jump()).is_true()
	stamina.stamina = _tuning.jump_cost - 0.01
	assert_bool(stamina.can_jump()).is_false()


func test_sprinting_while_moving_spends_per_second() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.report(0.5, true, false)
	var expected := _tuning.max_stamina - _tuning.sprint_cost_per_second * 0.5
	assert_float(stamina.get_stamina()).is_equal_approx(expected, 0.0001)


func test_a_jump_spends_its_cost_at_once() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = 50.0
	stamina.report(0.0, false, true)
	assert_float(stamina.get_stamina()).is_equal_approx(50.0 - _tuning.jump_cost, 0.0001)


func test_other_steps_regenerate_up_to_the_maximum() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = 0.0
	stamina.report(1.0, false, false)
	assert_float(stamina.get_stamina()).is_equal_approx(_tuning.regen_per_second, 0.0001)
	stamina.report(1000.0, false, false)
	assert_float(stamina.get_stamina()).is_equal(_tuning.max_stamina)


func test_never_below_zero() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = 1.0
	stamina.report(1.0, true, false)
	assert_float(stamina.get_stamina()).is_equal(0.0)


func test_walking_is_always_free() -> void:
	var stamina := LocalStamina.new(_tuning)
	stamina.stamina = 0.0
	# A step that walked (not in the sprint state) is not a spending step: it regenerates.
	stamina.report(0.1, false, false)
	assert_float(stamina.get_stamina()).is_greater(0.0)
