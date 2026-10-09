extends GdUnitTestSuite
## The UI's base resolution (#287): the screens are laid out on a 1920x1080 canvas, the size the
## UI pack's mock-ups and Toy tokens are drawn at (one mock-up px is one Godot px), stretched to
## the window (`canvas_items`, `expand`). The window still opens at Godot's old default of
## 1152x648. Godot's default theme is not scaled: the generated theme covers the base controls the
## screens build (#576; base_controls_test.gd), so its scale went back to 1 from the 1920/1152 that
## #287 set to keep the default controls' apparent size.

const BASE := Vector2i(1920, 1080)
const START_WINDOW := Vector2i(1152, 648)


func test_the_base_is_1920_by_1080() -> void:
	assert_int(ProjectSettings.get_setting("display/window/size/viewport_width")).is_equal(BASE.x)
	assert_int(ProjectSettings.get_setting("display/window/size/viewport_height")).is_equal(BASE.y)
	# Read back from the running root: a misspelt key would leave Godot's default here.
	assert_vector(get_tree().root.content_scale_size).is_equal(BASE)


func test_the_canvas_stretches_to_the_window() -> void:
	var root := get_tree().root
	assert_int(root.content_scale_mode).is_equal(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_int(root.content_scale_aspect).is_equal(Window.CONTENT_SCALE_ASPECT_EXPAND)


func test_the_window_opens_at_its_old_size() -> void:
	var width: int = ProjectSettings.get_setting("display/window/size/window_width_override")
	var height: int = ProjectSettings.get_setting("display/window/size/window_height_override")
	assert_vector(Vector2i(width, height)).is_equal(START_WINDOW)


func test_the_default_theme_is_not_scaled() -> void:
	var setting: float = ProjectSettings.get_setting("gui/theme/default_theme_scale")
	assert_float(setting).is_equal_approx(1.0, 0.001)
	# Read back from the theme Godot built at startup.
	assert_float(ThemeDB.get_default_theme().default_base_scale).is_equal_approx(1.0, 0.001)
