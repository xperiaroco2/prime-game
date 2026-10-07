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
	&"task_screen",
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


func test_give_up_is_g_and_the_mouse_buttons_cycle_the_spectate_target() -> void:
	# The M4 ADR's controls (D6): hold G to give up; left and right mouse buttons for the next
	# and the previous spectate target.
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"give_up"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains([KEY_G])
	var next := InputMap.action_get_events(&"spectate_next")[0] as InputEventMouseButton
	var previous := InputMap.action_get_events(&"spectate_previous")[0] as InputEventMouseButton
	assert_int(next.button_index).is_equal(MOUSE_BUTTON_LEFT)
	assert_int(previous.button_index).is_equal(MOUSE_BUTTON_RIGHT)


func test_swap_is_x_and_the_task_screen_is_tab() -> void:
	# The M4 ADR's controls (D6, M4-8): X swaps the hand and the belt; Tab held shows the tasks.
	for pair: Array in [[&"swap", KEY_X], [&"task_screen", KEY_TAB]]:
		var keys: Array[Key] = []
		for event: InputEvent in InputMap.action_get_events(pair[0] as StringName):
			var key := event as InputEventKey
			if key != null:
				keys.append(key.physical_keycode)
		assert_array(keys).contains([pair[1]])


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
