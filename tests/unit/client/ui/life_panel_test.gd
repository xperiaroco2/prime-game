extends GdUnitTestSuite
## The life panel (M4-9): it shows LifeHud's words and bar, nothing when there is no title, and
## it is styled only through the shared theme (the M4 manager's decision on #144 and #145): its
## source has no inline theme override, colour or font size, and every type variation it names is
## in the theme. M4-8's source test over client/ui/ covers every screen once it lands.

const SOURCE := "res://client/ui/life_panel.gd"
## An inline style in a screen's code: a theme override, a colour, a font size or a size.
const INLINE := ["add_theme_", "Color(", "font_size", "_override(", "custom_minimum_size"]


func test_it_shows_the_words_and_the_bar_and_hides_when_empty() -> void:
	var panel := auto_free(LifePanel.new()) as LifePanel
	assert_bool(panel.panel.visible).is_false()
	var shown := LifeHud.Shown.new()
	shown.title = "Knocked down"
	shown.lines = PackedStringArray(["Dying in 7 s", "Hold F to give up"])
	shown.progress = 0.25
	shown.progress_label = "Giving up"
	panel.show_hud(shown)
	assert_bool(panel.panel.visible).is_true()
	assert_str(panel.title_label.text).is_equal("Knocked down")
	assert_str(panel.lines_label.text).is_equal("Dying in 7 s\nHold F to give up")
	assert_bool(panel.bar.visible).is_true()
	assert_float(panel.bar.value).is_equal_approx(0.25, 1e-4)
	assert_str(panel.bar_label.text).is_equal("Giving up")
	panel.show_hud(LifeHud.Shown.new())
	assert_bool(panel.panel.visible).is_false()


func test_it_is_styled_only_through_the_shared_theme() -> void:
	var source := FileAccess.get_file_as_string(SOURCE)
	assert_str(source).is_not_empty()
	for line: String in source.split("\n"):
		var code := line.get_slice("#", 0)
		for inline: String in INLINE:
			assert_str(code).override_failure_message("inline style: %s" % line).not_contains(
				inline
			)
	var theme := GameUi.THEME
	var variations: Array[StringName] = [
		&"LifePanel", &"LifeTitle", &"LifeText", &"LifeBar", &"LifeMargin"
	]
	for variation: StringName in variations:
		var base := theme.get_type_variation_base(variation)
		assert_str(String(base)).is_not_empty()
		assert_bool(theme.get_type_variation_list(base).has(variation)).is_true()


func test_the_ui_gives_every_screen_the_theme() -> void:
	var ui := auto_free(GameUi.new()) as GameUi
	for each: Node in ui.get_children():
		var control := each as Control
		if control != null:
			assert_object(control.theme).is_same(GameUi.THEME)
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.life.visible).is_true()
	ui.show_screen(GameFlow.Screen.LOBBY)
	assert_bool(ui.life.visible).is_false()


func test_the_theme_sizes_the_bar_and_the_bottom_margin() -> void:
	var panel := LifePanel.new()
	panel.theme = GameUi.THEME
	add_child(panel)
	var bar := panel.bar.get_combined_minimum_size()
	assert_float(bar.x).is_equal(
		GameUi.THEME.get_stylebox(&"background", &"LifeBar").get_minimum_size().x
	)
	assert_float(bar.x).is_greater(100.0)
	assert_float(bar.y).is_greater(4.0)
	var margin := panel.get_child(0) as MarginContainer
	assert_object(margin).is_not_null()
	assert_int(margin.get_theme_constant(&"margin_bottom")).is_greater(0)
	panel.free()
