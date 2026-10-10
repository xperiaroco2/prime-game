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
	# #169: everyone sees the settings in the Esc menu's Lobby tab; only the host changes them
	# (#491: the host's steppers and preset cards; a player's values and "Preset: …").
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array = []
	panel.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	panel.refresh(Preview.fake_model(mode, false), -1, false)
	assert_bool(panel.settings_box.visible).is_true()
	assert_bool(panel.settings_editable()).is_false()
	assert_bool(panel.presets.visible).is_false()
	assert_bool(panel.preset_label.visible).is_true()
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	assert_bool(panel.settings_box.visible).is_true()
	assert_bool(panel.settings_editable()).is_true()
	assert_bool(panel.presets.visible).is_true()
	assert_bool(panel.preset_label.visible).is_false()
	assert_str(panel.shortfalls_label.text).contains("4 to 10")
	assert_str(LobbyPanel.countdown_text(Preview.fake_model(mode, true), -1)).is_equal(
		"Waiting for everyone"
	)
	var steppers := panel.settings_box.find_children("Stepper", "HBoxContainer", true, false)
	assert_int(steppers.size()).is_equal(5)
	# The task count is fixed (1 to 1): its row hides, nothing to choose.
	assert_bool((panel.settings_box.get_node(^"TaskCount") as Control).visible).is_false()
	var duration := steppers[0] as SettingStepper
	var spec := mode.find_setting(&"match_duration")
	duration.less.pressed.emit()
	assert_array(sent).is_equal([[&"match_duration", spec.default_value - 1]])


func test_a_read_only_lobby_tab_sends_no_setting() -> void:
	# A player's read-only controls that still change (a stepper's arrow, a task chip) send nothing.
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array = []
	panel.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	panel.settings_changed.connect(func(values: Dictionary) -> void: sent.append(values))
	panel.refresh(Preview.fake_model(mode, false), -1, false)
	var steppers := panel.settings_box.find_children("Stepper", "HBoxContainer", true, false)
	var first := steppers[0] as SettingStepper
	assert_bool(first.less.visible or first.more.visible).is_false()
	first.less.pressed.emit()
	var chips := panel.settings_box.find_children("Allowed", "HBoxContainer", true, false)
	assert_bool(chips.is_empty()).is_false()
	assert_bool((chips[0] as Control).visible).is_false()
	((chips[0] as Node).get_child(0) as Button).pressed.emit()
	panel.cards[LobbyPresets.QUICK].pressed.emit()
	assert_array(sent).is_empty()


func test_the_lobby_tab_lets_the_host_pick_the_map_and_shows_it_to_everyone() -> void:
	# #627: the mode's maps by name; the host's pick is sent, a guest's picker is read-only, and the
	# picker follows the map the host's settings name.
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array[String] = []
	panel.map_changed.connect(func(map: String) -> void: sent.append(map))
	var picker := panel.map_picker
	assert_int(picker.item_count).is_equal(mode.maps.size())
	for i in mode.maps.size():
		assert_str(picker.get_item_text(i)).is_equal(LobbyPanel.map_name(mode.maps[i]))
	assert_str(LobbyPanel.map_name("res://levels/house/house.tscn")).is_equal("House")
	var guest := Preview.fake_model(mode, false)
	guest.map = mode.maps[1]
	panel.refresh(guest, -1, false)
	assert_bool(picker.disabled).is_true()
	assert_int(picker.selected).is_equal(1)
	picker.item_selected.emit(0)
	assert_array(sent).is_empty()
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	assert_bool(picker.disabled).is_false()
	assert_int(picker.selected).is_equal(0)
	picker.item_selected.emit(1)
	assert_array(sent).is_equal([mode.maps[1]])


func test_the_map_pick_sits_under_the_lobby_name_and_a_new_mode_rebuilds_its_list() -> void:
	# #694: the map pick beside the lobby's name (#214), not among the settings; a set_mode with other
	# maps replaces the old ones, and one pick sends one map.
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	# #491: both are 64 px rows of SettingList (H, then the row), side by side down the list.
	var name_row := panel.name_edit.get_parent().get_parent()
	var map_row := panel.map_picker.get_parent().get_parent()
	var list := panel.get_node(^"Body/SettingList")
	assert_object(name_row.get_parent()).is_same(list)
	assert_object(map_row.get_parent()).is_same(list)
	assert_int(map_row.get_index()).is_equal(name_row.get_index() + 1)
	assert_bool(panel.settings_box.is_ancestor_of(panel.map_picker)).is_false()
	var one := mode.duplicate() as GameMode
	one.maps = PackedStringArray([mode.maps[1]])
	panel.set_mode(one)
	assert_int(panel.map_picker.item_count).is_equal(1)
	assert_str(panel.map_picker.get_item_text(0)).is_equal(LobbyPanel.map_name(mode.maps[1]))
	panel.set_mode(mode)
	assert_int(panel.map_picker.item_count).is_equal(mode.maps.size())
	var sent: Array[String] = []
	panel.map_changed.connect(func(map: String) -> void: sent.append(map))
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	panel.map_picker.item_selected.emit(1)
	assert_array(sent).is_equal([mode.maps[1]])


func test_a_mode_with_one_map_shows_it_with_nothing_to_pick() -> void:
	var mode := (load(MODE) as GameMode).duplicate() as GameMode
	mode.maps = PackedStringArray([mode.maps[0]])
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	assert_int(panel.map_picker.item_count).is_equal(1)
	assert_bool(panel.map_picker.disabled).is_true()
	assert_bool(panel.settings_editable()).is_true()


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
	assert_bool(menu.confirm_box.visible or menu.actions.visible).is_false()
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].button_pressed).is_true()
	assert_bool(menu.lobby.settings_editable()).is_true()
	assert_str(menu.title_label.text).is_equal("esc.tab.lobby")
	assert_bool(menu.host_note.visible).is_true()
	assert_bool(menu.host_only.visible).is_false()
	var marks := menu.lobby.player_rows.find_children("Ready", "TextureRect", true, false)
	assert_bool((marks[0] as Control).visible).is_true()
	assert_bool(menu.lobby.ready_button.is_visible_in_tree()).is_true()
	# The round starts under the open menu: the Lobby tab stays, read-only for everyone (#491:
	# "Lobby, a player (and everyone in a round)"): no host note, no Ready, no ready marks.
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": -1})
	menu.refresh(GameFlow.Screen.ROUND, model, -1, true)
	assert_object(menu.page()).is_same(menu.lobby)
	assert_bool(menu.lobby.settings_editable()).is_false()
	assert_bool(menu.host_note.visible or menu.host_only.visible).is_false()
	assert_bool(menu.lobby.ready_button.is_visible_in_tree()).is_false()
	marks = menu.lobby.player_rows.find_children("Ready", "TextureRect", true, false)
	for mark: Node in marks:
		assert_bool((mark as Control).visible).is_false()
	# The end screen has no Lobby tab: the Game page.
	menu.refresh(GameFlow.Screen.END, model, -1, true)
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].visible).is_false()
	assert_object(menu.page()).is_same(menu.actions)
	assert_bool(menu.lobby.visible).is_false()
	assert_str(menu.title_label.text).is_equal("esc.tab.game")


func test_the_pregame_screen_shows_the_own_role_and_no_word_on_the_microphone() -> void:
	# #213: black, "Your role" and the own role; nothing about the microphone (the engineer,
	# 2026-10-02). No player but a dissident's teammates (the engineer on #175, 2026-10-02, #496):
	# never the own name, never a player outside the own role's Teammates.
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
	assert_str(screen.role_label.text).is_equal("role.dissident")
	_assert_pregame_names(screen, ["mic", "voice", "hear", "player1", "player2"])
	model.fold(&"RoleAssigned", {"role": &"crew"})
	screen.refresh(model, mode)
	assert_str(screen.role_label.text).is_equal("role.engineer")
	assert_array(screen.find_children("*", "BaseButton", true, false)).is_empty()
	_assert_pregame_names(screen, ["mic", "voice", "hear", "player1", "player2", "player3"])


func test_the_ui_shows_the_pregame_screen_alone_in_the_pregame() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.PREGAME)
	assert_bool(ui.pregame.visible).is_true()
	for other: Control in [ui.connecting, ui.hud, ui.life, ui.end, ui.lobby_hud]:
		assert_bool(other.visible).override_failure_message(other.name).is_false()
	# Outside the tree nothing draws, so the round cuts it; its fade over the HUD in the tree:
	# pregame_screen_test.gd (#496).
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
	assert_int(ui.esc.state.selected).is_equal(EscMenuState.Tab.GAME)


func test_the_esc_menus_leave_asks_the_host_and_not_a_client() -> void:
	var menu: EscMenu = auto_free(EscMenu.new())
	add_child(menu)
	var said: Array[String] = []
	menu.resume_requested.connect(func() -> void: said.append("resume"))
	menu.leave_requested.connect(func() -> void: said.append("leave"))
	menu.quit_requested.connect(func() -> void: said.append("quit"))
	menu.open(GameFlow.Screen.ROUND, null, false)
	assert_str(String(menu.leave_button.theme_type_variation)).is_equal("ToyButtonSecondary")
	menu.leave_button.pressed.emit()
	assert_array(said).is_equal(["leave"])
	assert_bool(menu.confirm_box.visible).is_false()
	menu.open(GameFlow.Screen.ROUND, null, true)
	assert_str(String(menu.leave_button.theme_type_variation)).is_equal("ToyButtonDanger")
	menu.quit_button.pressed.emit()
	assert_array(said).is_equal(["leave"])
	assert_bool(menu.confirm_box.visible and menu.confirm_dim.visible).is_true()
	assert_str(menu.confirm_title.text).is_equal("esc.game.quit_confirm")
	assert_str(menu.confirm_button.text).is_equal("esc.game.quit")
	menu.confirm()
	assert_array(said).is_equal(["leave", "quit"])
	assert_bool(menu.confirm_box.visible).is_false()
	menu.resume_button.pressed.emit()
	assert_array(said).is_equal(["leave", "quit", "resume"])
	assert_bool(menu.visible).is_false()


## No label of `screen` shows any of `words`, as a key or translated.
func _assert_pregame_names(screen: PregameScreen, words: Array) -> void:
	for found: Node in screen.find_children("*", "Label", true, false):
		var label := found as Label
		var shown := (label.text + " " + tr(label.text)).to_lower()
		for word: String in words:
			assert_str(shown).override_failure_message("%s: %s" % [word, shown]).not_contains(word)


func test_the_confirm_dialog_takes_the_focus_and_shuts_the_menu_behind_it() -> void:
	# #491: while the host's question is open, focus cannot reach the menu behind (Menu's
	# focus_behavior_recursive), Cancel has it; closing restores both.
	var menu: EscMenu = auto_free(EscMenu.new())
	add_child(menu)
	menu.open(GameFlow.Screen.ROUND, null, true)
	await get_tree().process_frame
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.resume_button)
	menu.leave_button.pressed.emit()
	await get_tree().process_frame
	assert_str(menu.confirm_title.text).is_equal("esc.game.leave_confirm")
	assert_int(menu.menu.focus_behavior_recursive).is_equal(Control.FOCUS_BEHAVIOR_DISABLED)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.cancel_button)
	menu.cancel_button.pressed.emit()
	assert_bool(menu.confirm_box.visible).is_false()
	assert_bool(menu.is_open()).is_true()
	assert_int(menu.menu.focus_behavior_recursive).is_equal(Control.FOCUS_BEHAVIOR_INHERITED)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.leave_button)


func test_the_tutorials_menu_leaves_the_tutorial_at_once() -> void:
	var menu: EscMenu = auto_free(EscMenu.new())
	add_child(menu)
	menu.state.tutorial = true
	var said: Array[String] = []
	menu.leave_requested.connect(func() -> void: said.append("leave"))
	menu.open(GameFlow.Screen.ROUND, null, true)
	assert_bool(menu.tab_buttons[EscMenuState.Tab.ROLE].visible).is_false()
	assert_str(menu.leave_button.text).is_equal("esc.game.leave_tutorial")
	assert_str(String(menu.leave_button.theme_type_variation)).is_equal("ToyButtonSecondary")
	menu.leave_button.pressed.emit()
	assert_array(said).is_equal(["leave"])
	assert_bool(menu.confirm_box.visible).is_false()


func test_the_esc_menu_is_built_as_the_handoff_names_it() -> void:
	# #491: prime-game-ui's s05 at ui-0.4.0, node for node (the differences are in the PR).
	var menu: EscMenu = auto_free(EscMenu.new())
	var paths: Dictionary[String, String] = {
		"Dim": "ToyBackdropDeep",
		"MenuRaised/Menu": "ToyPanelMenu",
		"MenuRaised/Menu/H": "ToyRowTwentyFour",
		"MenuRaised/Menu/H/Tabs": "ToyColumnEight",
		"MenuRaised/Menu/H/Tabs/Game": "ToyTab",
		"MenuRaised/Menu/H/Page": "ToyColumnSixteen",
		"MenuRaised/Menu/H/Page/TitleRow/Title": "ToyTitleOnLight",
		"MenuRaised/Menu/H/Page/TitleRow/HostNote": "ToyTextMutedOnLight",
		"MenuRaised/Menu/H/Page/TitleRow/HostOnly": "ToyRowEight",
		"MenuRaised/Menu/H/Page/Actions": "ToyColumnSixteen",
		"MenuRaised/Menu/H/Page/Actions/ResumeRaised/Resume": "ToyButtonPrimary",
		"MenuRaised/Menu/H/Page/Actions/Quit": "ToyButtonGhostOnLight",
		"MenuRaised/Menu/H/Page/Role/Team/Scroll/Grid": "ToyGridList",
		"MenuRaised/Menu/H/Page/Settings/Sub/Sound": "ToyChipToggleOnLight",
		"MenuRaised/Menu/H/Page/Settings/Scroll/Rows/Sound/Mic": "ToySettingRow",
		"MenuRaised/Menu/H/Page/Settings/Scroll/Rows/Controls/Talk/H/Bind": "ToyKeyButton",
		"MenuRaised/Menu/H/Page/Settings/Scroll/Rows/Controls/Talk/H/Same": "ToyChipAlert",
		"ConfirmDim": "ToyBackdrop",
		"ConfirmRaised/Confirm": "ToyPanelDialog",
		"ConfirmRaised/Confirm/V/Buttons/ConfirmButtonRaised/ConfirmButton": "ToyButtonDanger",
		"ConfirmRaised/Confirm/V/Buttons/Cancel": "ToyButtonGhostOnLight",
	}
	for path: String in paths:
		var node := menu.get_node_or_null(NodePath(path)) as Control
		assert_object(node).override_failure_message(path).is_not_null()
		var variation := String(node.theme_type_variation)
		assert_str(variation).override_failure_message(path).starts_with(paths[path])
	assert_vector(menu.menu.custom_minimum_size).is_equal(EscMenu.MENU_SIZE)
	(
		assert_vector((menu.get_node(^"MenuRaised/Menu/H/Tabs") as Control).custom_minimum_size)
		. is_equal(Vector2(288, 0))
	)
	assert_vector(menu.role.scroll.custom_minimum_size).is_equal(Vector2(0, 250))


func test_the_lobby_tab_shows_the_code_to_whoever_knows_it_and_the_service_gone_in_its_place(
) -> void:
	# #491 (s05 lobby-host, lobby-no-code): the keycap and Copy with a code; the code service's
	# absence instead when it closed (even with the old code still known); neither for Direct.
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	panel.show_code(JoinProgress.code_text("K7M2QX", false), "K7M2QX")
	assert_bool(panel.code_row.visible).is_true()
	assert_bool(panel.code_gone.visible).is_false()
	assert_str(panel.code_label.text).is_equal("K7M2QX")
	panel.show_code(JoinProgress.code_text("K7M2QX", true), "K7M2QX")
	assert_bool(panel.code_row.visible).is_false()
	assert_bool(panel.code_gone.visible).is_true()
	panel.show_code("", "")
	assert_bool(panel.code_row.visible or panel.code_gone.visible).is_false()
