extends GdUnitTestSuite
## ToyPress and ToyRaised (#289; prime-game-ui spec §6). The tests call the handlers directly (a
## headless run has no pointer) and assert the target offsets from the theme, the base's
## visibility, the tween started only on a changed target, reduced motion, the raised toggle that
## stays on, and that a container's sort and a theme swap leave the visual offset alone.

var _stage: Control


func before_test() -> void:
	UiPrefs.reduced_motion = true
	_stage = auto_free(Control.new())
	_stage.theme = GameUi.THEME
	add_child(_stage)


func after_test() -> void:
	UiPrefs.reset()


func test_the_targets_follow_hover_held_and_disabled() -> void:
	var raised := _raised(&"ToyButtonSecondary")
	var face := raised.face as Button
	var press := _press(raised)
	assert_bool(face.offset_transform_enabled).is_true()
	assert_int(press.target_offset()).is_equal(0)
	press.on_mouse_entered()
	assert_int(press.target_offset()).is_equal(-1)
	assert_float(face.offset_transform_position.y).is_equal(-1.0)
	press.on_button_down()
	assert_int(press.target_offset()).is_equal(4)
	assert_float(face.offset_transform_position.y).is_equal(4.0)
	press.on_button_up()
	assert_int(press.target_offset()).is_equal(-1)
	press.on_mouse_exited()
	assert_int(press.target_offset()).is_equal(0)
	assert_float(face.offset_transform_position.y).is_equal(0.0)
	# Unplugged: no base, the disabled offset (0), whatever the pointer does.
	assert_bool(raised.base.visible).is_true()
	face.disabled = true
	press.on_button_down()
	assert_bool(raised.base.visible).is_false()
	assert_int(press.target_offset()).is_equal(0)
	face.disabled = false
	press.on_button_up()
	assert_bool(raised.base.visible).is_true()


func test_each_variation_reads_its_own_depths() -> void:
	var primary := _press(_raised(&"ToyButtonPrimary"))
	primary.on_button_down()
	assert_int(primary.target_offset()).is_equal(5)
	var card := _press(_raised(&"ToyPresetCard"))
	card.on_button_down()
	assert_int(card.target_offset()).is_equal(3)
	var flat := UiParts.toggle("Tab", Callable(), &"ToyTab")
	_stage.add_child(flat)
	var flat_press := flat.get_node(^"ToyPress") as ToyPress
	flat_press.on_mouse_entered()
	flat_press.on_button_down()
	assert_int(flat_press.target_offset()).is_equal(0)


func test_a_tween_starts_only_when_the_target_changes() -> void:
	UiPrefs.reduced_motion = false
	var raised := _raised(&"ToyButtonSecondary")
	var press := _press(raised)
	assert_int(press.duration_ms()).is_equal(70)
	press.on_mouse_entered()
	assert_int(press.tweens_started).is_equal(1)
	press.refresh()
	press.refresh()
	press.on_mouse_entered()
	assert_int(press.tweens_started).is_equal(1)
	await press.tween.finished
	assert_float(raised.face.offset_transform_position.y).is_equal(-1.0)
	press.on_button_down()
	assert_int(press.tweens_started).is_equal(2)


func test_reduced_motion_moves_at_once() -> void:
	var press := _press(_raised(&"ToyButtonSecondary"))
	assert_int(press.duration_ms()).is_equal(0)
	press.on_button_down()
	assert_int(press.tweens_started).is_equal(0)
	assert_float(press.face.offset_transform_position.y).is_equal(4.0)


func test_a_raised_toggle_that_is_on_rests_sunk() -> void:
	var raised := _raised(&"ToyPresetCard")
	var face := raised.face as Button
	var press := _press(raised)
	face.toggle_mode = true
	face.button_pressed = true
	assert_str(str(face.theme_type_variation)).is_equal("ToyPresetCardSelected")
	assert_int(press.target_offset()).is_equal(3)
	assert_float(face.offset_transform_position.y).is_equal(3.0)
	face.button_pressed = false
	assert_int(press.target_offset()).is_equal(0)


func test_a_sort_and_a_theme_swap_leave_the_offset_alone() -> void:
	var raised := _raised(&"ToyButtonSecondary")
	var face := raised.face as Button
	await get_tree().process_frame
	_press(raised).on_button_down()
	var rect := face.get_rect()
	raised.queue_sort()
	await get_tree().process_frame
	assert_float(face.offset_transform_position.y).is_equal(4.0)
	assert_that(face.get_rect()).is_equal(rect)
	_stage.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	assert_float(face.offset_transform_position.y).is_equal(4.0)
	# The base stays where the layout put it: only the face moves.
	assert_that(raised.base.get_rect()).is_equal(raised.face.get_rect())


func _raised(variation: StringName) -> ToyRaised:
	var raised := UiParts.button("Go", Callable(), variation)
	_stage.add_child(raised)
	return raised


func _press(raised: ToyRaised) -> ToyPress:
	return raised.face.get_node(^"ToyPress") as ToyPress
