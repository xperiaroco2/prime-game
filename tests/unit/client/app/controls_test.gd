extends GdUnitTestSuite
## The player's controls (client/app/controls.gd, #211): the defaults from project.godot (give-up on
## F, beside Ready on F), the phases that keep the two apart, the same-key warning per phase,
## binding, reset, saving under user://, loading, and the default fallback for a missing, damaged
## or foreign file.

const PATH := "user://controls_test.cfg"

var _locale := ""


func before_test() -> void:
	# The row names are the deck's translations (#208): English here, whatever the machine's.
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_remove()


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	_remove()
	# The InputMap is global: every later suite reads the project's bindings.
	Controls.new().apply()


func test_the_defaults_are_the_projects_with_give_up_and_ready_both_on_f() -> void:
	var controls := Controls.new()
	assert_int(_key(controls.event_of(&"give_up"))).is_equal(KEY_F)
	assert_int(_key(controls.event_of(&"ready"))).is_equal(KEY_F)
	assert_int(_key(controls.event_of(&"move_forward"))).is_equal(KEY_W)
	assert_int(_key(controls.event_of(&"map"))).is_equal(KEY_M)
	var use := controls.event_of(&"use") as InputEventMouseButton
	assert_int(use.button_index).is_equal(MOUSE_BUTTON_LEFT)
	for action: StringName in Controls.ACTIONS:
		assert_bool(InputMap.has_action(action)).override_failure_message(action).is_true()
		assert_object(controls.event_of(action)).override_failure_message(action).is_not_null()
		assert_bool(controls.is_default(action)).is_true()


func test_there_are_the_sixteen_actions_of_settings_controls_each_with_its_phases() -> void:
	# #488's rule 5: 16 rows; rule 6: the implementer defines the phase of each action.
	assert_int(Controls.ACTIONS.size()).is_equal(16)
	assert_array(Controls.PHASES.keys()).contains_exactly(Controls.ACTIONS.keys())
	for action: StringName in Controls.ACTIONS:
		assert_int(Controls.PHASES[action]).override_failure_message(action).is_not_zero()
		assert_str(Controls.name_of(action)).is_not_empty()
	assert_str(Controls.name_of(&"give_up")).is_equal("Give up")
	assert_str(Controls.name_of(&"map")).is_equal("Map and tasks")
	TranslationServer.set_locale("uk")
	assert_str(Controls.name_of(&"give_up")).is_equal("Здатися")


func test_give_up_and_ready_never_act_in_the_same_phase() -> void:
	assert_int(Controls.PHASES[&"give_up"]).is_equal(Controls.Phase.DOWNED)
	assert_int(Controls.PHASES[&"ready"]).is_equal(Controls.Phase.LOBBY)
	assert_int(Controls.PHASES[&"give_up"] & Controls.PHASES[&"ready"]).is_zero()
	# So their shared F is no clash, and no default is one.
	var controls := Controls.new()
	for action: StringName in Controls.ACTIONS:
		assert_array(controls.clashes_of(action)).override_failure_message(action).is_empty()


func test_one_key_in_one_phase_is_a_clash_and_in_two_phases_is_none() -> void:
	var controls := Controls.new()
	# The review page's example: Map and Talk on one key, both while living.
	assert_bool(controls.bind(&"map", _press(KEY_V))).is_true()
	assert_array(controls.clashes_of(&"map")).contains_exactly([&"voice_talk"])
	assert_array(controls.clashes_of(&"voice_talk")).contains_exactly([&"map"])
	# Sprint on F clashes with Ready in the lobby, not with give-up (downed only).
	controls.bind(&"sprint", _press(KEY_F))
	assert_array(controls.clashes_of(&"sprint")).contains_exactly([&"ready"])
	assert_array(controls.clashes_of(&"give_up")).is_empty()
	# Use on the right mouse button: Previous player is the dead's alone.
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	controls.bind(&"use", right)
	assert_array(controls.clashes_of(&"use")).is_empty()
	assert_array(controls.clashes_of(&"spectate_previous")).is_empty()


func test_a_binding_is_a_bare_physical_key_or_mouse_button() -> void:
	var controls := Controls.new()
	var shifted := _press(KEY_K)
	shifted.shift_pressed = true
	shifted.keycode = KEY_L
	assert_bool(controls.bind(&"give_up", shifted)).is_true()
	var bound := controls.event_of(&"give_up") as InputEventKey
	assert_int(bound.physical_keycode).is_equal(KEY_K)
	assert_int(bound.keycode).is_equal(KEY_NONE)
	assert_bool(bound.shift_pressed or bound.pressed).is_false()
	# Esc is fixed, a joypad is out of scope, and only the 16 actions rebind.
	assert_bool(controls.bind(&"jump", _press(KEY_ESCAPE))).is_false()
	assert_bool(controls.bind(&"jump", InputEventJoypadButton.new())).is_false()
	assert_bool(controls.bind(&"debug_overlay", _press(KEY_K))).is_false()
	assert_bool(controls.bind(&"ui_cancel", _press(KEY_K))).is_false()
	assert_int(_key(controls.event_of(&"jump"))).is_equal(KEY_SPACE)


func test_binding_the_default_again_is_the_default() -> void:
	var controls := Controls.new()
	controls.bind(&"give_up", _press(KEY_G))
	assert_bool(controls.is_default(&"give_up")).is_false()
	controls.bind(&"give_up", _press(KEY_F))
	assert_bool(controls.is_default(&"give_up")).is_true()


func test_it_saves_only_what_was_rebound_and_loads_it_back() -> void:
	var controls := Controls.new(PATH)
	controls.bind(&"give_up", _press(KEY_G))
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	controls.bind(&"interact", middle)
	assert_int(controls.write()).is_equal(OK)
	var file := ConfigFile.new()
	assert_int(file.load(PATH)).is_equal(OK)
	assert_array(Array(file.get_section_keys(Controls.SECTION))).contains_exactly(
		["interact", "give_up"]
	)
	assert_str(str(file.get_value(Controls.SECTION, "give_up"))).is_equal("key:%d" % KEY_G)
	var back := Controls.new(PATH)
	assert_int(back.read()).is_equal(OK)
	assert_int(_key(back.event_of(&"give_up"))).is_equal(KEY_G)
	var button := back.event_of(&"interact") as InputEventMouseButton
	assert_int(button.button_index).is_equal(MOUSE_BUTTON_MIDDLE)
	assert_bool(back.is_default(&"ready")).is_true()
	assert_int(_key(back.event_of(&"ready"))).is_equal(KEY_F)


func test_reset_restores_every_default_and_saves_an_empty_file() -> void:
	var controls := Controls.new(PATH)
	controls.bind(&"give_up", _press(KEY_G))
	controls.bind(&"jump", _press(KEY_J))
	controls.write()
	controls.reset()
	assert_int(_key(controls.event_of(&"give_up"))).is_equal(KEY_F)
	assert_int(_key(controls.event_of(&"jump"))).is_equal(KEY_SPACE)
	controls.write()
	var back := Controls.new(PATH)
	back.read()
	for action: StringName in Controls.ACTIONS:
		assert_bool(back.is_default(action)).override_failure_message(action).is_true()


func test_a_missing_file_keeps_the_defaults() -> void:
	var controls := Controls.new(PATH)
	assert_int(controls.read()).is_not_equal(OK)
	assert_int(_key(controls.event_of(&"give_up"))).is_equal(KEY_F)
	# In memory only: nothing is read or written.
	var memory := Controls.new()
	assert_int(memory.read()).is_not_equal(OK)
	memory.bind(&"jump", _press(KEY_J))
	assert_int(memory.write()).is_equal(OK)
	assert_bool(FileAccess.file_exists(PATH)).is_false()


func test_a_damaged_file_keeps_the_defaults() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('[bindings\ngive_up = "key:\n%%% not a config')
	file.close()
	var controls := Controls.new(PATH)
	# The engine prints its ConfigFile parse error here; the read fails and nothing is bound.
	assert_int(controls.read()).is_not_equal(OK)
	for action: StringName in Controls.ACTIONS:
		assert_bool(controls.is_default(action)).override_failure_message(action).is_true()


func test_foreign_and_unreadable_entries_keep_their_defaults_and_the_rest_loads() -> void:
	var file := ConfigFile.new()
	file.set_value(Controls.SECTION, "give_up", "key:%d" % KEY_G)
	file.set_value(Controls.SECTION, "jump", "key:")
	file.set_value(Controls.SECTION, "sprint", "key:-4")
	file.set_value(Controls.SECTION, "interact", "pad:3")
	file.set_value(Controls.SECTION, "use", 7)
	file.set_value(Controls.SECTION, "put_down", "key:%d" % KEY_ESCAPE)
	file.set_value(Controls.SECTION, "debug_overlay", "key:%d" % KEY_K)
	file.set_value(Controls.SECTION, "no_such_action", "key:%d" % KEY_K)
	file.save(PATH)
	var controls := Controls.new(PATH)
	assert_int(controls.read()).is_equal(OK)
	assert_int(_key(controls.event_of(&"give_up"))).is_equal(KEY_G)
	for action: StringName in [&"jump", &"sprint", &"interact", &"use", &"put_down"]:
		assert_bool(controls.is_default(action)).override_failure_message(action).is_true()
	assert_object(controls.event_of(&"no_such_action")).is_null()


func test_apply_rebinds_the_input_map_and_the_key_labels_follow() -> void:
	var controls := Controls.new()
	controls.bind(&"give_up", _press(KEY_G))
	controls.apply()
	var events := InputMap.action_get_events(&"give_up")
	assert_int(events.size()).is_equal(1)
	assert_int(_key(events[0])).is_equal(KEY_G)
	assert_str(KeyLabel.of_action(&"give_up")).is_equal("G")
	var held := _press(KEY_G)
	assert_bool(held.is_action_pressed(&"give_up")).is_true()
	assert_bool(_press(KEY_F).is_action_pressed(&"give_up")).is_false()
	# Ready keeps F; a reset brings give-up back to it.
	assert_bool(_press(KEY_F).is_action_pressed(&"ready")).is_true()
	controls.reset()
	controls.apply()
	assert_str(KeyLabel.of_action(&"give_up")).is_equal("F")
	assert_bool(_press(KEY_F).is_action_pressed(&"give_up")).is_true()


func test_applied_bindings_match_a_real_keyboard_and_mouse() -> void:
	# A window's key and mouse events carry DEVICE_ID_KEYBOARD and DEVICE_ID_MOUSE; the bindings
	# keep project.godot's all-devices id (-1), so after apply() the defaults and a rebind still act.
	var controls := Controls.new()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	controls.bind(&"interact", middle)
	controls.bind(&"give_up", _press(KEY_G))
	controls.apply()
	for action: StringName in Controls.ACTIONS:
		assert_int(controls.event_of(action).device).override_failure_message(action).is_equal(-1)
	var forward := _press(KEY_W)
	forward.device = InputEvent.DEVICE_ID_KEYBOARD
	assert_bool(forward.is_action_pressed(&"move_forward")).is_true()
	var give_up := _press(KEY_G)
	give_up.device = InputEvent.DEVICE_ID_KEYBOARD
	assert_bool(give_up.is_action_pressed(&"give_up")).is_true()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.device = InputEvent.DEVICE_ID_MOUSE
	assert_bool(click.is_action_pressed(&"use")).is_true()
	var wheel_click := InputEventMouseButton.new()
	wheel_click.button_index = MOUSE_BUTTON_MIDDLE
	wheel_click.pressed = true
	wheel_click.device = InputEvent.DEVICE_ID_MOUSE
	assert_bool(wheel_click.is_action_pressed(&"interact")).is_true()


func test_a_key_of_a_fixed_action_and_the_wheel_never_bind() -> void:
	# F3 (the debug overlay) and Enter (Alt+Enter: fullscreen) are fixed like Esc: on one of those
	# keys both would act. The wheel only clicks, so a held action could never be held on it.
	var controls := Controls.new()
	assert_bool(controls.bind(&"ready", _press(KEY_F3))).is_false()
	assert_bool(controls.bind(&"jump", _press(KEY_ENTER))).is_false()
	for wheel: MouseButton in [
		MOUSE_BUTTON_WHEEL_UP,
		MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT,
		MOUSE_BUTTON_WHEEL_RIGHT
	]:
		var button := InputEventMouseButton.new()
		button.button_index = wheel
		(
			assert_bool(controls.bind(&"give_up", button))
			. override_failure_message(str(wheel))
			. is_false()
		)
	assert_bool(controls.is_default(&"ready")).is_true()
	assert_bool(controls.is_default(&"jump")).is_true()
	assert_bool(controls.is_default(&"give_up")).is_true()


func _press(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event


func _key(event: InputEvent) -> int:
	var key := event as InputEventKey
	return key.physical_keycode if key != null else -1


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
