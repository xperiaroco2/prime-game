extends GdUnitTestSuite
## The screens' texts and controls (client/ui/, ARCHITECTURE §4.7), from a ClientModel and the
## client's own mode only. How they look: the `shot`s of client/dev/*_preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"


func test_the_roster_names_the_host_the_own_player_and_who_is_ready() -> void:
	var mode := load(MODE) as GameMode
	var model := Preview.fake_model(mode, false)
	assert_str(LobbyPanel.roster_text(model)).is_equal(
		"Player1 (host)  ready\nPlayer2 (you)  ready\nPlayer3  not ready"
	)


func test_the_lobby_tab_lets_the_host_change_the_settings_and_others_read_them() -> void:
	# #169: everyone sees the settings in the Esc menu's Lobby tab; only the host changes them.
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	# A Range emits value_changed only inside the tree.
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array = []
	panel.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	panel.refresh(Preview.fake_model(mode, false), -1, false)
	assert_bool(panel.settings_box.visible).is_true()
	assert_bool(panel.settings_editable()).is_false()
	assert_bool(panel.read_only_label.visible).is_true()
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	assert_bool(panel.settings_box.visible).is_true()
	assert_bool(panel.settings_editable()).is_true()
	assert_bool(panel.read_only_label.visible).is_false()
	assert_str(panel.shortfalls_label.text).contains("4 to 10")
	assert_str(panel.countdown_label.text).is_equal("Waiting for everyone")
	var boxes := panel.settings_box.find_children("*", "SpinBox", true, false)
	assert_int(boxes.size()).is_equal(5)
	(boxes[0] as SpinBox).value = 3
	assert_array(sent).is_equal([[&"match_duration", 3]])


func test_a_read_only_lobby_tab_sends_no_setting() -> void:
	# A guest's read-only control that still changes (a SpinBox's arrows or wheel) sends nothing.
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array = []
	panel.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	panel.refresh(Preview.fake_model(mode, false), -1, false)
	var boxes := panel.settings_box.find_children("*", "SpinBox", true, false)
	(boxes[0] as SpinBox).value = 3
	var checks := panel.settings_box.find_children("*", "CheckBox", true, false)
	assert_bool(checks.is_empty()).is_false()
	(checks[0] as CheckBox).button_pressed = not (checks[0] as CheckBox).button_pressed
	assert_array(sent).is_empty()


func test_the_esc_menu_shows_the_selected_tabs_page_alone() -> void:
	var mode := load(MODE) as GameMode
	var menu: EscMenu = auto_free(EscMenu.new())
	add_child(menu)
	menu.lobby.set_mode(mode)
	assert_bool(menu.visible).is_false()
	var model := Preview.fake_model(mode, true)
	menu.open(GameFlow.Screen.LOBBY, model, true)
	menu.refresh(GameFlow.Screen.LOBBY, model, -1, true)
	assert_bool(menu.visible).is_true()
	assert_object(menu.page()).is_same(menu.lobby)
	assert_bool(menu.lobby.is_visible_in_tree()).is_true()
	assert_bool(menu.confirm_box.visible or menu.resume_page.visible).is_false()
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].button_pressed).is_true()
	assert_bool(menu.lobby.settings_editable()).is_true()
	# The round starts under the open menu: no Lobby tab, the Resume page.
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": -1})
	menu.refresh(GameFlow.Screen.ROUND, model, -1, true)
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].visible).is_false()
	assert_object(menu.page()).is_same(menu.resume_page)
	assert_bool(menu.lobby.visible).is_false()


func test_the_pregame_screen_shows_the_own_role_alone_and_no_word_on_the_microphone() -> void:
	# #213: black, "Your role" and the own role's display name; nothing about the microphone (the
	# engineer, 2026-10-02), no other player (the Teammates a dissident holds stay off it).
	var mode := load(MODE) as GameMode
	var model := Preview.fake_model(mode, true)
	model.fold(&"PhaseChanged", {"phase": &"pregame", "end_tick": 160})
	var screen: PregameScreen = auto_free(PregameScreen.new())
	screen.refresh(model, mode)
	assert_str(screen.role_label.text).is_empty()
	model.fold(&"RoleAssigned", {"role": &"dissident"})
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([1, 3])})
	screen.refresh(model, mode)
	assert_str(screen.title_label.text).is_equal(PregameScreen.TITLE_KEY)
	assert_str(screen.role_label.text).is_equal(mode.find_role(&"dissident").display_name)
	model.fold(&"RoleAssigned", {"role": &"crew"})
	screen.refresh(model, mode)
	assert_str(screen.role_label.text).is_equal(mode.find_role(&"crew").display_name)
	assert_array(screen.find_children("*", "BaseButton", true, false)).is_empty()
	for found: Node in screen.find_children("*", "Label", true, false):
		var label := found as Label
		var shown := (label.text + " " + tr(label.text)).to_lower()
		for word: String in ["mic", "voice", "hear", "player1", "player2", "player3"]:
			assert_str(shown).override_failure_message("%s: %s" % [word, shown]).not_contains(word)


func test_the_ui_shows_the_pregame_screen_alone_in_the_pregame() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.PREGAME)
	assert_bool(ui.pregame.visible).is_true()
	for other: Control in [ui.connecting, ui.hud, ui.life, ui.end, ui.lobby_hud]:
		assert_bool(other.visible).override_failure_message(other.name).is_false()
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.pregame.visible).is_false()


func test_the_ui_opens_the_esc_menu_on_the_screen_it_is_given_else_the_one_drawn_last() -> void:
	# #204: the game passes its live screen, which may be ahead of the one drawn last.
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.CONNECTING)
	ui.open_esc(false, null, GameFlow.Screen.LOBBY)
	assert_bool(ui.esc.state.has_tab(EscMenuState.Tab.LOBBY)).is_true()
	assert_int(ui.esc.state.selected).is_equal(EscMenuState.Tab.LOBBY)
	ui.close_esc()
	ui.show_screen(GameFlow.Screen.LOBBY)
	ui.open_esc(false)
	assert_int(ui.esc.state.selected).is_equal(EscMenuState.Tab.LOBBY)
	ui.close_esc()
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.open_esc(false)
	assert_int(ui.esc.state.selected).is_equal(EscMenuState.Tab.RESUME)


func test_the_esc_menus_leave_asks_the_host_and_not_a_client() -> void:
	var menu: EscMenu = auto_free(EscMenu.new())
	add_child(menu)
	var said: Array[String] = []
	menu.resume_requested.connect(func() -> void: said.append("resume"))
	menu.leave_requested.connect(func() -> void: said.append("leave"))
	menu.quit_requested.connect(func() -> void: said.append("quit"))
	menu.open(GameFlow.Screen.ROUND, null, false)
	menu.tab_buttons[EscMenuState.Tab.LEAVE].pressed.emit()
	assert_array(said).is_equal(["leave"])
	menu.open(GameFlow.Screen.ROUND, null, true)
	menu.tab_buttons[EscMenuState.Tab.QUIT].pressed.emit()
	assert_array(said).is_equal(["leave"])
	assert_object(menu.page()).is_same(menu.confirm_box)
	assert_str(menu.confirm_label.text).is_equal("Quit, and end the session for every player?")
	menu.confirm()
	assert_array(said).is_equal(["leave", "quit"])
	menu.tab_buttons[EscMenuState.Tab.RESUME].pressed.emit()
	assert_array(said).is_equal(["leave", "quit", "resume"])
	assert_bool(menu.visible).is_false()
