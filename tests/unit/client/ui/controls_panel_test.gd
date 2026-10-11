extends GdUnitTestSuite
## Settings › Controls (client/ui/controls_panel.gd, #211): a row per rebindable action with the
## bound key's label; a capture that binds the next key or mouse button press (applied to the
## InputMap and saved), ignores releases and echoes, and cancels on Esc; the same-key mark per
## phase; Reset to defaults. Through real key events in the Esc menu:
## tests/integration/client/app/esc_menu_input_test.gd.

const PATH := "user://controls_panel_test.cfg"

var _panel: ControlsPanel
var _changes := 0
var _locale := ""


func before_test() -> void:
	# The panel's words are the deck's translations (#208): English here, whatever the machine's.
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_remove()
	_panel = auto_free(ControlsPanel.new()) as ControlsPanel
	_panel.setup(Controls.new(PATH))
	_changes = 0
	_panel.changed.connect(func() -> void: _changes += 1)


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	_remove()
	Controls.new().apply()


func test_a_row_per_action_with_the_bound_keys_and_no_clash_by_default() -> void:
	assert_array(_panel.key_buttons.keys()).contains_exactly(Controls.ACTIONS.keys())
	assert_str(_panel.key_buttons[&"give_up"].text).is_equal("F")
	assert_str(_panel.key_buttons[&"ready"].text).is_equal("F")
	assert_str(_panel.key_buttons[&"jump"].text).is_equal("Space")
	assert_str(_panel.key_buttons[&"spectate_previous"].text).is_equal("RMB")
	for action: StringName in Controls.ACTIONS:
		assert_bool(_panel.clash_chips[action].visible).override_failure_message(action).is_false()
	assert_str(_panel.reset_button.text).is_equal("Reset to defaults")
	# The Toy rows (#491, s05 settings-controls): the flat ghost Reset after ResetGap, and each row
	# a ToySettingRow with its name, the ToyChipAlert and the wide ToyKeyButton.
	assert_str(String(_panel.reset_button.theme_type_variation)).is_equal("ToyButtonGhostOnLight")
	assert_object(_panel.reset_button.get_parent()).is_same(_panel)
	var gap := _panel.get_child(_panel.reset_button.get_index() - 1)
	assert_str(String(gap.name)).is_equal("ResetGap")
	assert_vector((gap as Control).custom_minimum_size).is_equal(Vector2(0, 12))
	assert_str(String(_panel.theme_type_variation)).is_equal("ToyColumnEight")
	var row := _panel.get_node(^"Talk") as PanelContainer
	assert_str(String(row.theme_type_variation)).is_equal("ToySettingRow")
	assert_object(row.get_node(^"H/Bind")).is_same(_panel.key_buttons[&"voice_talk"])
	var alert := String(_panel.clash_chips[&"voice_talk"].theme_type_variation)
	assert_str(alert).is_equal("ToyChipAlert")


func test_a_capture_binds_the_next_key_press_applies_and_saves_it() -> void:
	_panel.key_buttons[&"give_up"].pressed.emit()
	assert_bool(_panel.is_capturing()).is_true()
	var button := _panel.key_buttons[&"give_up"]
	assert_str(button.text).is_equal("Press a key…")
	assert_bool(button.button_pressed).is_true()
	# The release of what started it, and an echo, bind nothing.
	assert_bool(_panel.capture(_key(KEY_ENTER, false))).is_true()
	var echo := _key(KEY_J, true)
	echo.echo = true
	assert_bool(_panel.capture(echo)).is_true()
	assert_bool(_panel.is_capturing()).is_true()
	assert_bool(_panel.capture(_key(KEY_G, true))).is_true()
	assert_bool(_panel.is_capturing()).is_false()
	assert_str(button.text).is_equal("G")
	assert_bool(button.button_pressed).is_false()
	assert_int(_changes).is_equal(1)
	assert_bool(_key(KEY_G, true).is_action_pressed(&"give_up")).is_true()
	var back := Controls.new(PATH)
	assert_int(back.read()).is_equal(OK)
	assert_int((back.event_of(&"give_up") as InputEventKey).physical_keycode).is_equal(KEY_G)


func test_a_capture_binds_a_mouse_button_press_but_not_a_release() -> void:
	_panel.start_capture(&"interact")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	assert_bool(_panel.capture(release)).is_true()
	assert_bool(_panel.is_capturing()).is_true()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	assert_bool(_panel.capture(press)).is_true()
	assert_str(_panel.key_buttons[&"interact"].text).is_equal("RMB")


func test_esc_cancels_a_capture_and_binds_nothing() -> void:
	_panel.start_capture(&"jump")
	assert_bool(_panel.capture(_key(KEY_ESCAPE, true))).is_true()
	assert_bool(_panel.is_capturing()).is_false()
	assert_str(_panel.key_buttons[&"jump"].text).is_equal("Space")
	assert_int(_changes).is_equal(0)
	assert_bool(FileAccess.file_exists(PATH)).is_false()
	# With no capture the panel takes nothing.
	assert_bool(_panel.capture(_key(KEY_K, true))).is_false()


func test_a_key_shared_in_one_phase_is_marked_on_both_rows() -> void:
	_panel.start_capture(&"map")
	_panel.capture(_key(KEY_V, true))
	assert_bool(_panel.clash_chips[&"map"].visible).is_true()
	assert_bool(_panel.clash_chips[&"voice_talk"].visible).is_true()
	assert_str(_panel.clash_labels[&"voice_talk"].text).is_equal("Same key")
	assert_bool(_panel.clash_chips[&"give_up"].visible).is_false()
	assert_bool(_panel.clash_chips[&"ready"].visible).is_false()


func test_reset_restores_every_default() -> void:
	_panel.start_capture(&"give_up")
	_panel.capture(_key(KEY_G, true))
	_panel.start_capture(&"jump")
	_panel.reset_button.pressed.emit()
	assert_bool(_panel.is_capturing()).is_false()
	assert_str(_panel.key_buttons[&"give_up"].text).is_equal("F")
	assert_str(_panel.key_buttons[&"jump"].text).is_equal("Space")
	assert_bool(_key(KEY_F, true).is_action_pressed(&"give_up")).is_true()
	var back := Controls.new(PATH)
	back.read()
	assert_bool(back.is_default(&"give_up")).is_true()
	assert_int(_changes).is_equal(2)


func test_the_wheel_scrolls_on_through_a_capture_and_binds_nothing() -> void:
	_panel.start_capture(&"give_up")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	# Not taken: it reaches the page's scroll bar, and the capture still waits for a key.
	assert_bool(_panel.capture(wheel)).is_false()
	assert_bool(_panel.is_capturing()).is_true()
	assert_bool(_panel.capture(_key(KEY_G, true))).is_true()
	assert_str(_panel.key_buttons[&"give_up"].text).is_equal("G")


func test_a_click_on_another_button_cancels_the_capture_and_reaches_that_button() -> void:
	await _laid_out()
	_panel.start_capture(&"move_forward")
	# A click on another row's key, or on Reset, is no binding: it reaches the button it is on.
	for other: Button in [_panel.key_buttons[&"move_back"], _panel.reset_button]:
		_panel.start_capture(&"move_forward")
		(
			assert_bool(_panel.capture(_click_on(other)))
			. override_failure_message(other.name)
			. is_false()
		)
		assert_bool(_panel.is_capturing()).is_false()
		assert_str(_panel.key_buttons[&"move_forward"].text).is_equal("W")
	assert_int(_changes).is_equal(0)
	# A click on the capturing button itself binds the left mouse button.
	_panel.start_capture(&"move_forward")
	assert_bool(_panel.capture(_click_on(_panel.key_buttons[&"move_forward"]))).is_true()
	assert_str(_panel.key_buttons[&"move_forward"].text).is_equal("LMB")


func test_a_key_of_a_fixed_action_ends_the_capture_and_binds_nothing() -> void:
	_panel.start_capture(&"ready")
	assert_bool(_panel.capture(_key(KEY_F3, true))).is_true()
	assert_bool(_panel.is_capturing()).is_false()
	assert_str(_panel.key_buttons[&"ready"].text).is_equal("F")
	assert_int(_changes).is_equal(0)


func test_the_words_follow_a_language_switch_after_the_panel_was_built() -> void:
	# GameUi builds the panel before Game applies the player's language (Languages.apply), and
	# Languages.choose() switches it live: the words follow NOTIFICATION_TRANSLATION_CHANGED.
	TranslationServer.set_locale("uk")
	var panel := auto_free(ControlsPanel.new()) as ControlsPanel
	panel.setup(Controls.new(PATH))
	add_child(panel)
	assert_str(panel.reset_button.text).is_equal("Скинути до стандартних")
	assert_str(panel.name_labels[&"give_up"].text).is_equal("Здатися")
	assert_str(panel.key_buttons[&"jump"].text).is_equal("Пробіл")
	TranslationServer.set_locale("en")
	assert_str(panel.reset_button.text).is_equal("Reset to defaults")
	assert_str(panel.name_labels[&"give_up"].text).is_equal("Give up")
	assert_str(panel.clash_labels[&"give_up"].text).is_equal("Same key")
	assert_str(panel.key_buttons[&"jump"].text).is_equal("Space")


func _laid_out() -> void:
	_panel.size = Vector2(1200, 1000)
	add_child(_panel)
	await get_tree().process_frame
	await get_tree().process_frame


func _click_on(button: Button) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = button.get_global_rect().get_center()
	click.global_position = click.position
	return click


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
