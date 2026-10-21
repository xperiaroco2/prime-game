extends GdUnitTestSuite
## The saved window mode at the game's start (#1175): a runner launch (shot, playcheck,
## run --offscreen) sets PRIME_WINDOW and keeps its off-screen window, everything else applies.

const Offscreen := preload("res://tools/offscreen/offscreen.gd")


func test_a_runner_launch_does_not_restore_the_saved_window_mode() -> void:
	var restored := GameSettings.restores_window(UserSettings.WINDOW_FULLSCREEN, true, "1280x720")
	assert_bool(restored).is_false()


func test_without_a_runner_window_the_saved_mode_is_restored() -> void:
	assert_bool(GameSettings.restores_window(UserSettings.WINDOW_FULLSCREEN, true, "")).is_true()
	assert_bool(GameSettings.restores_window(UserSettings.WINDOW_WINDOWED, true, "")).is_true()


func test_no_saved_mode_or_no_command_line_restores_nothing() -> void:
	assert_bool(GameSettings.restores_window("", true, "")).is_false()
	assert_bool(GameSettings.restores_window(UserSettings.WINDOW_FULLSCREEN, false, "")).is_false()


func test_the_variable_is_the_one_the_runner_window_script_reads() -> void:
	assert_str(GameSettings.RUNNER_WINDOW).is_equal(Offscreen.ENV)
