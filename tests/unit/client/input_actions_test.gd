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
	&"fly_down",
	&"interact",
	&"put_down",
	&"use",
]


func test_every_action_exists_with_a_binding() -> void:
	for action: StringName in ACTIONS:
		(
			assert_bool(InputMap.has_action(action))
			. override_failure_message("missing action %s" % action)
			. is_true()
		)
		assert_array(InputMap.action_get_events(action)).is_not_empty()
