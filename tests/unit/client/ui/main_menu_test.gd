extends GdUnitTestSuite
## The main menu's Voice entry (client/ui/main_menu.gd, #301): it swaps the menu's rows for the
## Voice page, the same VoicePanel class as the Esc menu's Voice tab, and Back returns. The game's
## wiring (a pick saved, the meter with no session) is game_voice_test.gd's. How it looks:
## `shot client/dev/menu_voice_preview.tscn`.


func test_the_voice_entry_opens_the_voice_panel_and_back_returns() -> void:
	var menu: MainMenu = auto_free(MainMenu.new())
	add_child(menu)
	assert_bool(menu.main_page.is_visible_in_tree()).is_true()
	assert_bool(menu.voice.is_visible_in_tree()).is_false()
	assert_bool(menu.voice_open()).is_false()
	(menu.voice_button.face as Button).pressed.emit()
	assert_bool(menu.voice_open()).is_true()
	assert_bool(menu.voice.is_visible_in_tree()).is_true()
	assert_bool(menu.main_page.visible).is_false()
	assert_object(menu.voice).is_instanceof(VoicePanel)
	(menu.back_button.face as Button).pressed.emit()
	assert_bool(menu.voice_open()).is_false()
	assert_bool(menu.main_page.is_visible_in_tree()).is_true()


func test_the_voice_page_says_voice_is_unavailable_without_the_addon() -> void:
	var menu: MainMenu = auto_free(MainMenu.new())
	add_child(menu)
	menu.open_voice()
	var shown := VoicePanel.Shown.new()
	shown.available = false
	shown.devices = PackedStringArray([VoiceMicrophone.DEFAULT_DEVICE])
	menu.voice.show_facts(shown)
	assert_bool(menu.voice.unavailable_label.is_visible_in_tree()).is_true()
	assert_str(menu.voice.unavailable_label.text).is_equal(VoicePanel.UNAVAILABLE)
	assert_bool(menu.voice.microphone_box.visible).is_false()
