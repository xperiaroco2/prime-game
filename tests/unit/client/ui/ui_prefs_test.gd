extends GdUnitTestSuite
## UiPrefs (#289): reduced motion is a bool, on only when the system answers 1. DisplayServer's
## -1 (unknown: Linux, the Steam Deck, a headless run) must read as off, not as a truthy int.


func after_test() -> void:
	UiPrefs.reset()


func test_only_a_system_answer_of_one_turns_it_on() -> void:
	assert_bool(UiPrefs.from_system_answer(1)).is_true()
	assert_bool(UiPrefs.from_system_answer(0)).is_false()
	assert_bool(UiPrefs.from_system_answer(-1)).is_false()


func test_reset_leaves_a_bool_from_the_system() -> void:
	UiPrefs.reduced_motion = true
	UiPrefs.reset()
	var value: Variant = UiPrefs.reduced_motion
	assert_bool(value is bool).is_true()
	assert_bool(UiPrefs.reduced_motion).is_equal(UiPrefs.system_reduced_motion())
	var answer := DisplayServer.accessibility_should_reduce_animation()
	assert_bool(UiPrefs.reduced_motion).is_equal(answer == 1)
