extends GdUnitTestSuite
## Large text (#289): GameUi swaps every screen's shared theme to game_theme_large.tres live and
## back; a screen with its own theme keeps it; a screen added later gets the theme of the moment;
## a Toy button's text grows with it.


func test_large_text_swaps_the_shared_theme_live() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	var own := Theme.new()
	var themed := Label.new()
	themed.theme = own
	ui.add_child(themed)
	var raised := UiParts.button("Go")
	ui.esc.add_child(raised)
	assert_int(raised.face.get_theme_font_size(&"font_size")).is_equal(24)
	ui.set_large_text(true)
	assert_bool(ui.large_text).is_true()
	assert_object(ui.shared_theme()).is_same(GameUi.THEME_LARGE)
	var screens := 0
	for control: Control in ui.screens():
		if control != themed:
			screens += 1
			assert_object(control.theme).is_same(GameUi.THEME_LARGE)
	assert_int(screens).is_greater(8)
	assert_object(themed.theme).is_same(own)
	assert_int(raised.face.get_theme_font_size(&"font_size")).is_equal(30)
	var later := Label.new()
	ui.add_child(later)
	assert_object(later.theme).is_same(GameUi.THEME_LARGE)
	ui.set_large_text(false)
	assert_object(later.theme).is_same(GameUi.THEME)
	assert_object(ui.esc.theme).is_same(GameUi.THEME)
	assert_object(themed.theme).is_same(own)
	assert_int(raised.face.get_theme_font_size(&"font_size")).is_equal(24)
