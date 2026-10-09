extends GdUnitTestSuite
## GameUi's overlays (#488 rule 2 and 3): what each Esc closes, the main menu's page only on the
## main menu, and the map key. The game's keys through Input: esc_menu_input_test.gd and
## map_input_test.gd.

const S := GameFlow.Screen


func test_the_main_menus_page_is_an_overlay_only_on_the_main_menu() -> void:
	var ui := _ui()
	ui.menu.open_voice()
	assert_str(String(ui.overlays.top())).is_equal("menu_panel")
	# A session's screen hides the menu with its page still set: no overlay Esc would close.
	ui.show_screen(S.LOBBY)
	assert_str(String(ui.overlays.top())).is_empty()
	ui.show_screen(S.MENU)
	assert_str(String(ui.overlays.close_top())).is_equal("menu_panel")
	assert_bool(ui.menu.voice_open()).is_false()
	assert_bool(ui.overlays.is_any_open()).is_false()


func test_the_hosts_question_closes_before_the_menu_and_the_menu_closes_as_resume() -> void:
	var ui := _ui()
	ui.show_screen(S.ROUND)
	var resumed: Array[int] = [0]
	ui.esc.resume_requested.connect(func() -> void: resumed[0] += 1)
	ui.open_esc(true)
	ui.esc.press(EscMenuState.Tab.QUIT)
	assert_str(String(ui.overlays.top())).is_equal("esc_dialog")
	assert_str(String(ui.overlays.close_top())).is_equal("esc_dialog")
	assert_bool(ui.esc_open()).is_true()
	assert_bool(ui.esc.state.asking()).is_false()
	assert_int(resumed[0]).is_equal(0)
	assert_str(String(ui.overlays.close_top())).is_equal("esc_menu")
	assert_bool(ui.esc_open()).is_false()
	assert_int(resumed[0]).is_equal(1)


func test_the_map_key_toggles_the_map_and_is_ignored_under_the_esc_menu() -> void:
	var ui := _ui()
	ui.show_screen(S.ROUND)
	assert_bool(ui.press_map_key()).is_true()
	assert_bool(ui.map_is_open()).is_true()
	assert_str(String(ui.overlays.top())).is_equal("map")
	assert_bool(ui.press_map_key()).is_true()
	assert_bool(ui.map_is_open()).is_false()
	ui.open_esc(false)
	assert_bool(ui.press_map_key()).is_false()
	assert_bool(ui.map_is_open()).is_false()


func _ui() -> GameUi:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	return ui
