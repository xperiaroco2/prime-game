extends GdUnitTestSuite
## KeyLabel (client/ui/key_label.gd, #211): the label of an action's binding now, a key by its name
## (headless Godot has no keyboard layout: the physical key's own name), Space and the two mouse
## buttons by the deck's words in the current language (#208's translations), and "" for nothing
## bound. The screens (#488's rule 7, #491, #495, #497) show keys only through it.

var _locale := ""


func before_test() -> void:
	# The deck's words are translated: English here, whatever the machine's language is.
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	# The InputMap is global: every later suite reads the project's bindings.
	Controls.new().apply()


func test_the_default_keys_read_as_their_names() -> void:
	assert_str(KeyLabel.of_action(&"give_up")).is_equal("F")
	assert_str(KeyLabel.of_action(&"ready")).is_equal("F")
	assert_str(KeyLabel.of_action(&"interact")).is_equal("E")
	assert_str(KeyLabel.of_action(&"sprint")).is_equal("Shift")
	assert_str(KeyLabel.of_action(&"map")).is_equal("M")
	assert_str(KeyLabel.of_action(&"voice_talk")).is_equal("V")


func test_space_and_the_mouse_buttons_read_as_the_decks_words() -> void:
	assert_str(KeyLabel.of_action(&"jump")).is_equal("Space")
	assert_str(KeyLabel.of_action(&"use")).is_equal("LMB")
	assert_str(KeyLabel.of_action(&"spectate_next")).is_equal("LMB")
	assert_str(KeyLabel.of_action(&"spectate_previous")).is_equal("RMB")
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	assert_str(KeyLabel.of_event(middle)).is_equal("Mouse 3")


func test_a_key_with_no_physical_code_reads_its_keycode_and_nothing_reads_empty() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	assert_str(KeyLabel.of_event(key)).is_equal("Q")
	assert_str(KeyLabel.of_event(InputEventKey.new())).is_empty()
	assert_str(KeyLabel.of_event(InputEventJoypadButton.new())).is_empty()
	assert_str(KeyLabel.of_action(&"no_such_action")).is_empty()


func test_the_label_follows_a_rebind() -> void:
	var controls := Controls.new()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	controls.bind(&"give_up", key)
	controls.apply()
	assert_str(KeyLabel.of_action(&"give_up")).is_equal("K")
	# The downed screen's keycap (#497) reads the binding now.
	var life := LifeHud.Local.new()
	life.read_keys()
	assert_str(life.give_up_key).is_equal("K")
	assert_str(LobbyHud.hint()).contains("F: ready")
	controls.bind(&"ready", key)
	controls.apply()
	assert_str(LobbyHud.hint()).contains("K: ready")


func test_space_shift_tab_and_esc_keycaps_are_wide_and_a_rebind_decides() -> void:
	# #488 rule 7: exactly the four keys of the issue are wide; the binding decides.
	for key: Key in [KEY_SPACE, KEY_SHIFT, KEY_TAB, KEY_ESCAPE]:
		(
			assert_bool(KeyLabel.is_wide(key))
			. override_failure_message(OS.get_keycode_string(key))
			. is_true()
		)
	for key: Key in [KEY_F, KEY_M, KEY_E, KEY_1, KEY_CTRL, KEY_ENTER, KEY_F5]:
		(
			assert_bool(KeyLabel.is_wide(key))
			. override_failure_message(OS.get_keycode_string(key))
			. is_false()
		)
	assert_bool(KeyLabel.is_wide_action(&"jump")).is_true()
	assert_bool(KeyLabel.is_wide_action(&"sprint")).is_true()
	assert_bool(KeyLabel.is_wide_action(&"use")).is_false()
	assert_bool(KeyLabel.is_wide_action(&"interact")).is_false()
	assert_bool(KeyLabel.is_wide_action(&"no_such_action")).is_false()
	var controls := Controls.new()
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	controls.bind(&"jump", k)
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	controls.bind(&"interact", tab)
	var ctrl := InputEventKey.new()
	ctrl.physical_keycode = KEY_CTRL
	controls.bind(&"sprint", ctrl)
	controls.apply()
	assert_bool(KeyLabel.is_wide_action(&"jump")).is_false()
	assert_bool(KeyLabel.is_wide_action(&"interact")).is_true()
	assert_bool(KeyLabel.is_wide_action(&"sprint")).is_false()
	TranslationServer.set_locale("uk")
	assert_bool(KeyLabel.is_wide(KEY_SPACE)).is_true()


func test_a_layouts_latin_label_shows_and_another_scripts_label_gives_way_to_the_us_name() -> void:
	# Real layouts (probed on Windows, 4.7.2): Ukrainian labels the physical F "А" (U+0410), W "Ц".
	assert_int(KeyLabel.shown(KEY_F, 0x0410 as Key)).is_equal(KEY_F)
	assert_int(KeyLabel.shown(KEY_W, 0x0426 as Key)).is_equal(KEY_W)
	# AZERTY's physical Q is labelled A; QWERTZ's physical Y is Z and its semicolon key Ö.
	assert_int(KeyLabel.shown(KEY_Q, KEY_A)).is_equal(KEY_A)
	assert_int(KeyLabel.shown(KEY_Y, KEY_Z)).is_equal(KEY_Z)
	assert_int(KeyLabel.shown(KEY_SEMICOLON, 0x00D6 as Key)).is_equal(0x00D6)
	assert_str(OS.get_keycode_string(KeyLabel.shown(KEY_SEMICOLON, 0x00D6 as Key))).is_equal("Ö")
	# Special keys keep their label; no label is the physical key.
	assert_int(KeyLabel.shown(KEY_SHIFT, KEY_SHIFT)).is_equal(KEY_SHIFT)
	assert_int(KeyLabel.shown(KEY_F, KEY_NONE)).is_equal(KEY_F)


func test_a_deck_word_is_its_translation_in_the_current_language() -> void:
	assert_str(KeyLabel.word(&"key.space")).is_equal("Space")
	assert_str(KeyLabel.word(&"key.mouse_right")).is_equal("RMB")
	TranslationServer.set_locale("uk")
	assert_str(KeyLabel.word(&"key.space")).is_equal("Пробіл")
	assert_str(KeyLabel.of_action(&"jump")).is_equal("Пробіл")
	assert_str(KeyLabel.of_action(&"use")).is_equal("ЛКМ")
	assert_str(KeyLabel.of_action(&"spectate_previous")).is_equal("ПКМ")
	# A letter key keeps its Latin name in every language (the engineer's answer (c) on #571).
	assert_str(KeyLabel.of_action(&"give_up")).is_equal("F")
