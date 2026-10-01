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


func test_the_debug_overlay_is_f3() -> void:
	# The M4 ADR's controls (D6): F3 shows the debug overlay in a debug build.
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"debug_overlay"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_array(keys).contains([KEY_F3])


func test_the_downed_have_no_fly_down_action() -> void:
	# The downed (once ghosts) do not fly (the engineer's correction of 2026-09-30, #46).
	assert_bool(InputMap.has_action(&"fly_down")).is_false()
