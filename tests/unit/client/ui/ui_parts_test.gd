extends GdUnitTestSuite
## UiParts' Toy builders (#289): button() is a ToyRaised whose face is the Button with the text and
## the callable; toggle() a flat toggle with ToyPress and ToyToggle; sized() reads the size
## constants, again on a theme change (the large-text keycap); scroll() sets the ToyScrollBar.

var _stage: Control


func before_test() -> void:
	_stage = auto_free(Control.new())
	_stage.theme = GameUi.THEME
	add_child(_stage)


func test_button_wraps_a_pressable_face() -> void:
	var pressed: Array[int] = []
	var raised := UiParts.button("Host", func() -> void: pressed.append(1))
	_stage.add_child(raised)
	var face := raised.face as Button
	assert_str(face.text).is_equal("Host")
	assert_str(str(face.theme_type_variation)).is_equal("ToyButtonSecondary")
	assert_that(raised.custom_minimum_size).is_equal(UiParts.BUTTON_SIZE)
	assert_object(face.get_node(^"ToyPress")).is_not_null()
	assert_bool(face.has_node(^"ToyToggle")).is_false()
	face.pressed.emit()
	assert_array(pressed).is_equal([1])
	# The press and toggle nodes are internal: a screen's children are its own.
	assert_int(face.get_child_count()).is_equal(0)


func test_toggle_is_a_flat_toggle() -> void:
	var pressed: Array[int] = []
	var chip := UiParts.toggle("Wires", func() -> void: pressed.append(1))
	_stage.add_child(chip)
	assert_bool(chip.toggle_mode).is_true()
	assert_object(chip.get_node(^"ToyPress")).is_not_null()
	chip.pressed.emit()
	assert_array(pressed).is_equal([1])
	chip.button_pressed = true
	assert_str(str(chip.theme_type_variation)).is_equal("ToyChipToggleOnDarkSelected")


func test_sized_reads_the_size_constants() -> void:
	var slot := _panel(&"ToySlot")
	assert_that(UiParts.sized(slot).custom_minimum_size).is_equal(Vector2(88, 88))
	var wide_slot := _panel(&"ToySlot")
	assert_that(UiParts.sized(wide_slot, true).custom_minimum_size).is_equal(Vector2(180, 88))
	var key := Button.new()
	key.theme_type_variation = &"ToyKeyButton"
	_stage.add_child(key)
	UiParts.sized(key)
	assert_float(key.custom_minimum_size.x).is_equal(36.0)
	var wide_key := Button.new()
	wide_key.theme_type_variation = &"ToyKeyButton"
	_stage.add_child(wide_key)
	UiParts.sized(wide_key, true)
	assert_float(wide_key.custom_minimum_size.x).is_equal(96.0)
	# Large text widens a plain keycap; the size follows the theme change.
	_stage.theme = GameUi.THEME_LARGE
	assert_float(UiParts.size_of(key).x).is_equal(42.0)
	await get_tree().process_frame
	assert_float(key.custom_minimum_size.x).is_equal(42.0)
	assert_that(slot.custom_minimum_size).is_equal(Vector2(88, 88))


func test_sized_waits_for_the_tree() -> void:
	var slot := Panel.new()
	slot.theme_type_variation = &"ToySlot"
	UiParts.sized(slot)
	assert_that(slot.custom_minimum_size).is_equal(Vector2.ZERO)
	_stage.add_child(slot)
	await get_tree().process_frame
	assert_that(slot.custom_minimum_size).is_equal(Vector2(88, 88))


func test_scroll_uses_the_toy_scroll_bar() -> void:
	var list := UiParts.scroll()
	_stage.add_child(list)
	assert_str(str(list.theme_type_variation)).is_equal("ToyScroll")
	assert_str(str(list.get_v_scroll_bar().theme_type_variation)).is_equal("ToyScrollBar")


func _panel(variation: StringName) -> Panel:
	var panel := Panel.new()
	panel.theme_type_variation = variation
	_stage.add_child(panel)
	return panel
