extends GdUnitTestSuite
## Settings (client/ui/settings_page.gd, #491): one scene in the Esc menu and the main menu, its
## sub-pages in one ButtonGroup, the chips showing the bound values each time it shows, and what a
## chip says. GameSettings applies it (game_settings_test.gd).


class RecordingWindow:
	extends GameWindow
	var at := DisplayServer.WINDOW_MODE_WINDOWED

	func mode() -> DisplayServer.WindowMode:
		return at

	func set_mode(value: DisplayServer.WindowMode) -> void:
		at = value


var _got: Array = []


func before_test() -> void:
	_got.clear()


func after_test() -> void:
	UiPrefs.reset()


func test_both_menus_have_the_same_scene_opened_on_sound_and_voice() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	for page: SettingsPage in [ui.esc.settings, ui.menu.settings_page]:
		assert_int(page.shown).is_equal(SettingsPage.Page.SOUND)
		assert_bool(page.voice.visible).is_true()
		assert_bool(page.controls.visible).is_false()
		assert_bool((page.sub.get_node(^"Sound") as Button).button_pressed).is_true()
		assert_bool(page.scroll.follow_focus).is_true()
	assert_object(ui.esc.voice).is_same(ui.esc.settings.voice)
	assert_object(ui.menu.voice).is_same(ui.menu.settings_page.voice)


func test_a_sub_chip_shows_its_page_alone() -> void:
	var page: SettingsPage = auto_free(SettingsPage.new())
	var boxes: Array[Control] = [
		page.voice, page.controls, page.display, page.access, page.language
	]
	for chip_name: String in SettingsPage.SUB_KEYS:
		(page.sub.get_node(NodePath(chip_name)) as Button).pressed.emit()
		var at := SettingsPage.SUB_KEYS.keys().find(chip_name)
		assert_int(page.shown).is_equal(at)
		for index: int in boxes.size():
			assert_bool(boxes[index].visible).override_failure_message(chip_name).is_equal(
				index == at
			)
		assert_object(page.first_focus()).is_same(page.sub.get_node(NodePath(chip_name)))


func test_the_chips_show_the_bound_values_and_say_what_is_picked() -> void:
	var page: SettingsPage = auto_free(SettingsPage.new())
	var settings := UserSettings.new()
	settings.language = Languages.UKRAINIAN
	var window := RecordingWindow.new()
	window.at = DisplayServer.WINDOW_MODE_FULLSCREEN
	var large := [true]
	UiPrefs.reduced_motion = false
	page.bind(settings, window, func() -> bool: return large[0])
	assert_bool(_chip(page.window_chips, "Fullscreen").button_pressed).is_true()
	assert_bool(_chip(page.large_text_chips, "On").button_pressed).is_true()
	assert_bool(_chip(page.motion_chips, "Off").button_pressed).is_true()
	assert_bool(_chip(page.language_chips, "Ukrainian").button_pressed).is_true()
	# Each language is named in itself, untranslated.
	assert_str(_chip(page.language_chips, "English").text).is_equal("English")
	page.large_text_toggled.connect(func(on: bool) -> void: _got.append(["large", on]))
	page.reduced_motion_toggled.connect(func(on: bool) -> void: _got.append(["motion", on]))
	page.window_mode_picked.connect(func(on: bool) -> void: _got.append(["fullscreen", on]))
	page.language_chosen.connect(func(code: String) -> void: _got.append(["language", code]))
	_chip(page.large_text_chips, "Off").pressed.emit()
	_chip(page.motion_chips, "On").pressed.emit()
	_chip(page.window_chips, "Windowed").pressed.emit()
	_chip(page.language_chips, "English").pressed.emit()
	assert_array(_got).is_equal(
		[["large", false], ["motion", true], ["fullscreen", false], ["language", "en"]]
	)
	# Shown again, it reads the values of the moment (the other page may have changed them).
	window.at = DisplayServer.WINDOW_MODE_WINDOWED
	large[0] = false
	page.show_values()
	assert_bool(_chip(page.window_chips, "Windowed").button_pressed).is_true()
	assert_bool(_chip(page.large_text_chips, "Off").button_pressed).is_true()


func test_every_row_is_a_64_px_toy_setting_row() -> void:
	var page: SettingsPage = auto_free(SettingsPage.new())
	var rows := page.find_children("*", "PanelContainer", true, false)
	var count := 0
	for found: Node in rows:
		var row := found as PanelContainer
		if row.theme_type_variation != &"ToySettingRow":
			continue
		count += 1
		assert_float(row.custom_minimum_size.y).is_equal(SettingRows.ROW_HEIGHT)
		assert_str(String(SettingRows.name_of(row).theme_type_variation)).is_equal(
			"ToySettingRowText"
		)
	# Sound's 9 and its 2 debug rows, Controls' 16, Display's 1, Access' 2, Language's 1.
	assert_int(count).is_equal(31)
	for dropdown: OptionButton in [page.voice.device_button, page.voice.mode_button]:
		assert_str(String(dropdown.get_popup().theme_type_variation)).is_equal("ToyDropdownList")


func _chip(box: HBoxContainer, chip_name: String) -> Button:
	return box.get_node(NodePath(chip_name)) as Button
