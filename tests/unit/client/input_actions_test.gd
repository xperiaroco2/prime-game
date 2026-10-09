extends GdUnitTestSuite
## The input actions the controller reads, and the ones reserved for later issues, exist in
## `project.godot` with a binding each.

const ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"jump",
	&"interact",
	&"put_down",
	&"use",
	&"debug_overlay",
	&"give_up",
	&"spectate_next",
	&"spectate_previous",
	&"swap",
	&"map",
	&"ready",
	&"voice_talk",
	&"toggle_fullscreen",
]


func test_every_action_exists_with_a_binding() -> void:
	for action: StringName in ACTIONS:
		(
			assert_bool(InputMap.has_action(action))
			. override_failure_message("missing action %s" % action)
			. is_true()
		)
		assert_array(InputMap.action_get_events(action)).is_not_empty()


func test_put_down_is_q() -> void:
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"put_down"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains([KEY_Q])


func test_ready_is_f() -> void:
	# #169: F readies up in the lobby without the Esc menu (a placeholder, "not a decision").
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"ready"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains([KEY_F])


func test_the_debug_overlay_is_f3() -> void:
	# The M4 ADR's controls (D6): F3 shows the debug overlay in a debug build.
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"debug_overlay"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains([KEY_F3])


func test_give_up_is_f_and_the_mouse_buttons_cycle_the_spectate_target() -> void:
	# The M4 ADR's controls (D6), give-up moved from G to F (#211): hold F to give up; left and
	# right mouse buttons for the next and the previous spectate target.
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"give_up"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains_exactly([KEY_F])
	var next := InputMap.action_get_events(&"spectate_next")[0] as InputEventMouseButton
	var previous := InputMap.action_get_events(&"spectate_previous")[0] as InputEventMouseButton
	assert_int(next.button_index).is_equal(MOUSE_BUTTON_LEFT)
	assert_int(previous.button_index).is_equal(MOUSE_BUTTON_RIGHT)


func test_swap_is_x_and_the_map_is_m() -> void:
	# The M4 ADR's controls (D6, M4-8): X swaps the hand and the belt; M opens and closes the map
	# and tasks screen (#253, which replaced the hold-Tab task screen).
	for pair: Array in [[&"swap", KEY_X], [&"map", KEY_M]]:
		var keys: Array[Key] = []
		for event: InputEvent in InputMap.action_get_events(pair[0] as StringName):
			var key := event as InputEventKey
			if key != null:
				keys.append(key.physical_keycode)
		assert_array(keys).contains([pair[1]])


func test_tab_is_bound_to_no_action() -> void:
	# #253: Tab is kept for an inventory later; until then it does nothing.
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key != null:
				(
					assert_int(key.physical_keycode)
					. override_failure_message("%s is on Tab" % action)
					. is_not_equal(KEY_TAB)
				)
	assert_bool(InputMap.has_action(&"task_screen")).is_false()


func test_push_to_talk_is_held_on_v() -> void:
	# The M5 ADR's D11: push-to-talk, an option beside voice activity, is held on V.
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"voice_talk"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains([KEY_V])


func test_alt_enter_toggles_fullscreen_and_enter_alone_does_not() -> void:
	# #517: Windows games flip fullscreen on Alt+Enter; Godot 4.7.2 binds nothing to it.
	var events := InputMap.action_get_events(&"toggle_fullscreen")
	assert_int(events.size()).is_equal(1)
	var key := events[0] as InputEventKey
	assert_int(key.physical_keycode).is_equal(KEY_ENTER)
	assert_bool(key.alt_pressed).is_true()
	assert_bool(key.ctrl_pressed or key.shift_pressed or key.meta_pressed).is_false()
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	assert_bool(enter.is_action_pressed(&"toggle_fullscreen")).is_false()
	enter.alt_pressed = true
	assert_bool(enter.is_action_pressed(&"toggle_fullscreen")).is_true()


func test_the_microphone_input_is_enabled() -> void:
	# The M5 ADR §1.1 (E36): the 4.7 microphone API reads nothing unless input is enabled.
	assert_bool(ProjectSettings.get_setting("audio/driver/enable_input", false) as bool).is_true()


func test_the_downed_have_no_fly_down_action() -> void:
	# The downed (once ghosts) do not fly (the engineer's correction of 2026-09-30, #46).
	assert_bool(InputMap.has_action(&"fly_down")).is_false()


func test_ui_accept_is_enter_keypad_enter_and_the_gamepads_a_without_space() -> void:
	# #488 rule 1: the map keeps gameplay input while a «?» may have focus, so the jump key must
	# never press a focused control. Godot 4.7.2's own list is Enter, keypad Enter and Space
	# (probed): the project's list drops Space and adds the gamepad's A.
	var keys: Array[Key] = []
	var buttons: Array[JoyButton] = []
	for event: InputEvent in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventKey:
			var key := event as InputEventKey
			keys.append(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
		elif event is InputEventJoypadButton:
			buttons.append((event as InputEventJoypadButton).button_index)
	assert_array(keys).contains_exactly([KEY_ENTER, KEY_KP_ENTER])
	assert_array(buttons).contains_exactly([JOY_BUTTON_A])
	assert_bool(_key(KEY_SPACE).is_action_pressed(&"ui_accept")).is_false()
	assert_bool(_key(KEY_SPACE).is_action_pressed(&"jump")).is_true()
	assert_bool(_key(KEY_ENTER).is_action_pressed(&"ui_accept")).is_true()
	assert_bool(_key(KEY_KP_ENTER).is_action_pressed(&"ui_accept")).is_true()
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	assert_bool(a.is_action_pressed(&"ui_accept")).is_true()


func test_a_focused_button_is_pressed_by_enter_and_the_gamepads_a_and_not_by_space() -> void:
	var button: Button = auto_free(Button.new())
	add_child(button)
	button.grab_focus()
	var presses: Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	_send(_key(KEY_SPACE))
	assert_int(presses[0]).override_failure_message("Space pressed the button").is_equal(0)
	_send(_key(KEY_ENTER))
	assert_int(presses[0]).is_equal(1)
	_send(_key(KEY_KP_ENTER))
	assert_int(presses[0]).is_equal(2)
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	_send(a)
	assert_int(presses[0]).is_equal(3)
	button.release_focus()


func test_the_ui_focus_actions_move_with_no_movement_key() -> void:
	# #488 rule 4: the map's focus moves with the arrows and the d-pad only; WASD walks.
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
			assert_bool(_key(key).is_action_pressed(action)).is_false()


## A press of `key` (its keycode and its physical key, as a keyboard sends both).
func _key(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	return event


## Sends `press` and its release through Input, as the keyboard or the gamepad would.
func _send(press: InputEvent) -> void:
	for pressed: bool in [true, false]:
		var event := press.duplicate() as InputEvent
		if event is InputEventKey:
			(event as InputEventKey).pressed = pressed
		elif event is InputEventJoypadButton:
			(event as InputEventJoypadButton).pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
