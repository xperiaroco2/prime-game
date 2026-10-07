extends GdUnitTestSuite
## The game's window (#517): an exported game starts fullscreen, everything the editor's binary runs
## (the runner's windows, the tests, the editor) starts in a window, and Alt+Enter flips it.

const MODE := "display/window/size/mode"


func test_an_export_template_starts_fullscreen_and_not_exclusive() -> void:
	# Both presets of export_presets.cfg export on a template, which alone has `template`.
	var exported: int = ProjectSettings.get_setting_with_override_and_custom_features(
		MODE, PackedStringArray(["template", "template_release", "release", "windows", "pc"])
	)
	assert_int(exported).is_equal(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var exported_debug: int = ProjectSettings.get_setting_with_override_and_custom_features(
		MODE, PackedStringArray(["template", "template_debug", "debug", "windows", "pc"])
	)
	assert_int(exported_debug).is_equal(DisplayServer.WINDOW_MODE_FULLSCREEN)


func test_the_editors_binary_starts_in_a_window() -> void:
	# `shot`, `playcheck`, `host` and `join` place their windows with --position and --resolution,
	# which do not undo a fullscreen mode; Godot 4.7.2's --windowed does not either.
	assert_bool(OS.has_feature("template")).is_false()
	var here: int = ProjectSettings.get_setting_with_override(MODE)
	assert_int(here).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)
	var editor_run: int = ProjectSettings.get_setting_with_override_and_custom_features(
		MODE, PackedStringArray(["editor", "editor_runtime", "debug", "windows", "pc"])
	)
	assert_int(editor_run).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)


func test_alt_enter_flips_fullscreen_and_a_window() -> void:
	const W := DisplayServer.WINDOW_MODE_WINDOWED
	const F := DisplayServer.WINDOW_MODE_FULLSCREEN
	assert_int(GameWindow.toggled(F)).is_equal(W)
	assert_int(GameWindow.toggled(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)).is_equal(W)
	assert_int(GameWindow.toggled(W)).is_equal(F)
	assert_int(GameWindow.toggled(DisplayServer.WINDOW_MODE_MAXIMIZED)).is_equal(F)
