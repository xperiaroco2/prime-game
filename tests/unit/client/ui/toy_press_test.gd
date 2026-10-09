extends GdUnitTestSuite
## ToyPress and ToyRaised (#289; prime-game-ui spec §6). The tests call the handlers directly (a
## headless run has no pointer) and assert the target offsets from the theme, the base's
## visibility, the tween started only on a changed target, reduced motion, the raised toggle that
## stays on, that a container's sort and a theme swap leave the visual offset alone, and the
## click of a press (UiSounds, #525): on the UI bus, none on hover, release or toggle, kept past
## its button.

var _stage: Control


func before_test() -> void:
	UiPrefs.reduced_motion = true
	_stage = auto_free(Control.new())
	_stage.theme = GameUi.THEME
	add_child(_stage)


func after_test() -> void:
	UiPrefs.reset()
	var clicker := UiSounds.player_in(get_tree())
	if clicker != null:
		clicker.free()


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


func test_a_face_disabled_while_held_is_not_held_once_enabled() -> void:
	# Disabling a held button sends no button_up, and the release on a disabled button is dropped.
	var raised := _raised(&"ToyButtonSecondary")
	var face := raised.face as Button
	var press := _press(raised)
	press.on_button_down()
	assert_int(press.target_offset()).is_equal(4)
	face.disabled = true
	press.refresh()
	face.disabled = false
	press.refresh()
	assert_int(press.target_offset()).is_equal(0)
	assert_float(face.offset_transform_position.y).is_equal(0.0)


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


func test_a_press_clicks_on_the_ui_bus_and_hover_release_and_toggle_do_not() -> void:
	# #525: the click is the press's, from a raised button and a flat toggle alike.
	AudioBuses.ensure()
	var raised := _raised(&"ToyButtonSecondary")
	var press := _press(raised)
	var before := UiSounds.clicks
	press.on_mouse_entered()
	press.on_mouse_exited()
	assert_int(UiSounds.clicks).is_equal(before)
	assert_object(UiSounds.player_in(get_tree())).is_null()
	press.on_button_down()
	assert_int(UiSounds.clicks).is_equal(before + 1)
	var clicker := UiSounds.player_in(get_tree())
	assert_object(clicker).is_not_null()
	assert_str(String(clicker.bus)).is_equal(String(AudioBuses.UI))
	var stream := clicker.stream as AudioStreamRandomizer
	assert_int(stream.streams_count).is_equal(SfxSet.paths_for(SfxSet.UI_CLICK).size())
	assert_bool(clicker.playing).is_true()
	press.on_button_up()
	press.on_toggled(true)
	assert_int(UiSounds.clicks).is_equal(before + 1)
	var chip := UiParts.toggle("Chip")
	_stage.add_child(chip)
	(chip.get_node(^"ToyPress") as ToyPress).on_button_down()
	assert_int(UiSounds.clicks).is_equal(before + 2)
	# One player for every click: the second press made none.
	assert_object(UiSounds.player_in(get_tree())).is_same(clicker)


func test_the_click_outlives_its_button() -> void:
	# A press that frees its screen (Back, Leave) frees the button, not the click.
	var raised := _raised(&"ToyButtonSecondary")
	_press(raised).on_button_down()
	raised.free()
	var clicker := UiSounds.player_in(get_tree())
	assert_object(clicker).is_not_null()
	assert_bool(clicker.playing).is_true()


func test_a_button_outside_the_tree_clicks_nothing() -> void:
	var raised: ToyRaised = auto_free(UiParts.button("Go"))
	var before := UiSounds.clicks
	_press(raised).on_button_down()
	assert_int(UiSounds.clicks).is_equal(before)
	assert_object(UiSounds.player_in(get_tree())).is_null()


func _raised(variation: StringName) -> ToyRaised:
	var raised := UiParts.button("Go", Callable(), variation)
	_stage.add_child(raised)
	return raised


func _press(raised: ToyRaised) -> ToyPress:
	return raised.face.get_node(^"ToyPress") as ToyPress
