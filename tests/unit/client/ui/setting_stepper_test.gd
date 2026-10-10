extends GdUnitTestSuite
## A setting's stepper (client/ui/setting_stepper.gd, #491): it steps within its bounds, says each
## step, and at a bound hands the focus to the other arrow before its own is disabled.


func test_it_steps_within_its_bounds_and_disables_the_arrow_at_a_bound() -> void:
	var stepper: SettingStepper = auto_free(SettingStepper.new())
	stepper.set_bounds(1, 3)
	stepper.show_value(2)
	var got: Array[int] = []
	stepper.stepped.connect(func(value: int) -> void: got.append(value))
	stepper.more.pressed.emit()
	stepper.more.pressed.emit()
	assert_array(got).contains_exactly([3])
	assert_bool(stepper.more.disabled).is_true()
	assert_bool(stepper.less.disabled).is_false()
	assert_str(stepper.value_label.text).is_equal("3")


func test_focus_never_rests_on_an_unplugged_arrow() -> void:
	var stepper: SettingStepper = auto_free(SettingStepper.new())
	add_child(stepper)
	stepper.set_bounds(0, 2)
	stepper.show_value(1)
	stepper.more.grab_focus()
	stepper.more.pressed.emit()
	assert_bool(stepper.more.disabled).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(stepper.less)
	stepper.less.pressed.emit()
	stepper.less.pressed.emit()
	assert_bool(stepper.less.disabled).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(stepper.more)


func test_a_minutes_value_reads_with_its_key_and_a_player_sees_no_arrows() -> void:
	var stepper: SettingStepper = auto_free(SettingStepper.new())
	stepper.format_key = "unit.minutes"
	stepper.set_bounds(1, 60)
	stepper.show_value(10)
	assert_str(stepper.value_label.text).is_equal(tr("unit.minutes").format({"count": 10}))
	assert_float(stepper.value_label.custom_minimum_size.x).is_equal(104.0)
	stepper.set_editable(false)
	assert_bool(stepper.less.visible or stepper.more.visible).is_false()
