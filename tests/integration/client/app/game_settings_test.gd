extends GdUnitTestSuite
## Game's wiring of both Settings pages (client/app/game_settings.gd, #491): what either page
## picks is applied and saved, the other page shows it when it shows, a key capture on either page
## keeps the talk key shut, and Alt+Enter keeps the window mode chips and the file in step.

const GAME := preload("res://client/app/game.tscn")


class RecordingWindow:
	extends GameWindow
	var now := DisplayServer.WINDOW_MODE_FULLSCREEN

	func mode() -> DisplayServer.WindowMode:
		return now

	func set_mode(value: DisplayServer.WindowMode) -> void:
		now = value


var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	UiPrefs.reset()
	Controls.new().apply()


func test_both_pages_share_the_controls_and_a_capture_on_either_shuts_the_talk_key() -> void:
	var game := await _game()
	var esc := game.ui.esc.settings
	var menu := game.ui.menu.settings_page
	assert_object(esc.controls.controls).is_same(game.controls)
	assert_object(menu.controls.controls).is_same(game.controls)
	# The main menu's page captures (its Settings panel open): the talk key must not speak.
	game.ui.menu.open_panel(MainMenu.Open.SETTINGS)
	menu.show_page(SettingsPage.Page.CONTROLS)
	menu.controls.start_capture(&"interact")
	assert_bool(GameSettings.capturing(game)).is_true()
	await _frames(2)
	assert_bool(game.sender().listening).is_false()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	menu.controls.capture(key)
	assert_bool(GameSettings.capturing(game)).is_false()
	# The Esc menu's page shows the new key as it shows.
	game.ui.menu.close_panel()
	game.ui.open_esc(false)
	game.ui.esc.press(EscMenuState.Tab.SETTINGS)
	esc.show_page(SettingsPage.Page.CONTROLS)
	assert_bool(esc.controls.is_visible_in_tree()).is_true()
	assert_str(esc.controls.key_buttons[&"interact"].text).is_equal(KeyLabel.of_action(&"interact"))
	assert_str(menu.controls.key_buttons[&"interact"].text).is_equal(
		KeyLabel.of_action(&"interact")
	)


func test_a_pick_is_applied_saved_and_shown_by_the_other_page() -> void:
	var game := await _game()
	var esc := game.ui.esc.settings
	var menu := game.ui.menu.settings_page
	esc.large_text_toggled.emit(true)
	assert_bool(game.ui.large_text).is_true()
	assert_bool(game.settings.large_text).is_true()
	esc.reduced_motion_toggled.emit(true)
	assert_bool(UiPrefs.reduced_motion).is_true()
	assert_int(game.settings.reduced_motion).is_equal(1)
	menu.language_chosen.emit(Languages.UKRAINIAN)
	assert_str(game.settings.language).is_equal(Languages.UKRAINIAN)
	assert_str(TranslationServer.get_locale()).is_equal(Languages.UKRAINIAN)
	menu.show_values()
	assert_bool((menu.large_text_chips.get_node(^"On") as Button).button_pressed).is_true()
	assert_bool((menu.motion_chips.get_node(^"On") as Button).button_pressed).is_true()
	esc.show_values()
	assert_bool((esc.language_chips.get_node(^"Ukrainian") as Button).button_pressed).is_true()


func test_the_window_chips_and_alt_enter_keep_the_mode_and_the_file_in_step() -> void:
	var game := await _game()
	var window := game.window as RecordingWindow
	var esc := game.ui.esc.settings
	esc.window_mode_picked.emit(false)
	assert_int(window.now).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)
	assert_str(game.settings.window_mode).is_equal(UserSettings.WINDOW_WINDOWED)
	GameSettings.toggle_window(game)
	assert_int(window.now).is_equal(DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert_str(game.settings.window_mode).is_equal(UserSettings.WINDOW_FULLSCREEN)
	assert_bool((esc.window_chips.get_node(^"Fullscreen") as Button).button_pressed).is_true()


func _game() -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray()
	game.window = RecordingWindow.new()
	add_child(game)
	auto_free(game)
	await _frames(1)
	return game


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame
