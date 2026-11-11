extends GdUnitTestSuite
## The screens' texts and controls (client/ui/, ARCHITECTURE §4.7), from a ClientModel and the
## client's own mode only. How they look: the `shot`s of client/dev/*_preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const GREYBOX := "res://levels/greybox/greybox.tscn"
const HOUSE := "res://levels/house/house.tscn"

var _locale := ""


## The host's shortfalls are worded in the current language (#548): English here, whatever the
## machine's locale.
func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)


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
	assert_str(panel.shortfalls_label.text).is_equal("1 more player to start")
	var steppers := panel.settings_box.find_children("Stepper", "HBoxContainer", true, false)
	# match_duration, tasks, packages, switches (the Generator, #800), photos (the photo task,
	# #784), burgers (Cooking, #775), car_parts (car repair, #810), engine_stages (the ship's
	# engine, #1462), dissidents, knives.
	assert_int(steppers.size()).is_equal(10)
	# The engine's stages are fixed at 3 (#507): nothing to choose, so the row hides.
	assert_bool((panel.settings_box.get_node(^"EngineStages") as Control).visible).is_false()
	# The knives place nothing since #1497 (no part reads the setting): the row hides (#1525).
	assert_bool((panel.settings_box.get_node(^"Knives") as Control).visible).is_false()
	# On the Estate, the one map players play in M8, only the ship's engine plays (#1601): no
	# other task's own row, no task count (one type: nothing to choose), no map row (one map).
	var shown_model := panel.get(&"_model") as ClientModel
	assert_str(HowtoCards.shown_map(mode, shown_model.map)).is_equal(mode.default_map())
	for row: String in ["Packages", "Switches", "Photos", "Burgers", "CarParts", "TaskCount"]:
		var hidden := panel.settings_box.get_node(row) as Control
		assert_bool(hidden.visible).override_failure_message(row).is_false()
	assert_bool((panel.get(&"_map_row") as Control).visible).is_false()
	# On a map with more types (the House bench), their rows show again. The task count is 1 to 5
	# since the Generator, the photo task, Cooking and car repair (#800, #784, #775, #810; GD7:
	# every type the map plays). A fixed count's row hides: the zones test below checks that on
	# the Zones row.
	var house := Preview.fake_model(mode, true)
	house.map = HOUSE
	panel.refresh(house, -1, true)
	for row: String in ["Packages", "Switches", "Photos", "Burgers", "CarParts", "TaskCount"]:
		var shown := panel.settings_box.get_node(row) as Control
		assert_bool(shown.visible).override_failure_message(row).is_true()
	var duration := steppers[0] as SettingStepper
	var spec := mode.find_setting(&"match_duration")
	duration.less.pressed.emit()
	assert_array(sent).is_equal([[&"match_duration", spec.default_value - 1]])


func test_a_task_types_own_row_is_named_in_the_players_language() -> void:
	# #1601: a task type's own setting with no deck key of its own (the Generator's switches) reads
	# "<the task>: step count" from the deck, never the content's English name, and follows a
	# language switch.
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var house := Preview.fake_model(mode, true)
	house.map = HOUSE
	panel.refresh(house, -1, true)
	var label := SettingRows.name_of(panel.settings_box.get_node(^"Switches") as PanelContainer)
	var task := ContentNames.text(ContentNames.task(&"generator", mode))
	assert_str(label.text).is_equal(tr("lobby.setting.task_steps").format({"task": task}))
	assert_str(label.text).is_not_equal(mode.find_setting(&"switches").display_name)
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_str(label.text).is_equal("Рубильники: кількість кроків")


func test_the_lobby_tab_of_a_mode_with_zones_hides_the_fixed_zone_count() -> void:
	# The base mode with the zone task (#649's, now a fixture since #842): its task count is
	# 1 to 2, so its row shows, and the zone count, fixed at 1, hides: nothing to choose.
	var mode := FixtureBaseModeWithZones.mode()
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	var steppers := panel.settings_box.find_children("Stepper", "HBoxContainer", true, false)
	# match_duration, tasks, packages, zones (#649), dissidents, knives.
	assert_int(steppers.size()).is_equal(6)
	assert_bool((panel.settings_box.get_node(^"Zones") as Control).visible).is_false()
	assert_bool((panel.settings_box.get_node(^"TaskCount") as Control).visible).is_true()


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
	# picker follows the map the host's settings name. Two maps players play: the shipped mode's
	# with its test bench played too.
	var mode := _two_player_maps()
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array[String] = []
	panel.map_changed.connect(func(map: String) -> void: sent.append(map))
	var picker := panel.map_picker
	# Two maps to pick from: the Map row shows (#1601 hides it with one).
	assert_bool((panel.get(&"_map_row") as Control).visible).is_true()
	assert_int(picker.item_count).is_equal(mode.maps.size())
	for i in mode.maps.size():
		assert_str(picker.get_item_text(i)).is_equal(LobbyPanel.map_name(mode.maps[i]))
	assert_str(LobbyPanel.map_name("res://levels/house/house.tscn")).is_equal("House")
	var guest := Preview.fake_model(mode, false)
	guest.map = mode.maps[0]
	panel.refresh(guest, -1, false)
	assert_bool(picker.disabled).is_true()
	assert_int(picker.selected).is_equal(0)
	picker.item_selected.emit(1)
	assert_array(sent).is_empty()
	var host := Preview.fake_model(mode, true)
	host.map = mode.maps[1]
	panel.refresh(host, -1, true)
	assert_bool(picker.disabled).is_false()
	assert_int(picker.selected).is_equal(1)
	picker.item_selected.emit(0)
	assert_array(sent).is_equal([mode.maps[0]])


func test_the_map_pick_sits_under_the_lobby_name_and_a_new_mode_rebuilds_its_list() -> void:
	# #694: the map pick beside the lobby's name (#214), not among the settings; a set_mode with other
	# maps replaces the old ones, and one pick sends one map.
	var mode := _two_player_maps()
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


func test_the_shipped_lobby_offers_the_estate_alone_never_a_bench() -> void:
	# #767: the greybox is a test bench only, and since the M8 slice (#1496) the House too, so
	# players always play the estate: the lobby's picker lists the estate alone, on it from the
	# start (the host's Welcome names the mode's default map), with nothing to pick.
	var mode := load(MODE) as GameMode
	assert_bool(mode.maps.has(GREYBOX)).is_true()
	assert_bool(mode.maps.has(HOUSE)).is_true()
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	var model := Preview.fake_model(mode, true)
	model.map = mode.default_map()
	panel.refresh(model, -1, true)
	assert_int(panel.map_picker.item_count).is_equal(1)
	assert_str(panel.map_picker.get_item_text(0)).is_equal("Estate")
	assert_int(panel.map_picker.selected).is_equal(0)
	assert_bool(panel.map_picker.disabled).is_true()


func test_a_mode_with_one_map_shows_it_with_nothing_to_pick() -> void:
	var mode := (load(MODE) as GameMode).duplicate() as GameMode
	mode.maps = PackedStringArray([mode.default_map()])
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(mode)
	panel.refresh(Preview.fake_model(mode, true), -1, true)
	assert_int(panel.map_picker.item_count).is_equal(1)
	assert_bool(panel.map_picker.disabled).is_true()
	assert_bool(panel.settings_editable()).is_true()


func test_the_esc_menu_shows_the_open_entrys_page_alone() -> void:
	# s05 at ui-2.5.4 (#1571): the side panel opens with no page (the handoff's `lobby` and
	# `round`); an entry opens its page beside the panel, a second press closes it.
	var mode := load(MODE) as GameMode
	var menu: EscMenu = auto_free(EscMenu.new())
	add_child(menu)
	menu.lobby.set_mode(mode)
	assert_bool(menu.visible).is_false()
	var model := Preview.fake_model(mode, true)
	menu.open(GameFlow.Screen.LOBBY, model, true)
	menu.refresh(GameFlow.Screen.LOBBY, model, -1, true)
	assert_bool(menu.visible).is_true()
	assert_object(menu.page()).is_null()
	assert_bool(menu.page_tile.visible).is_false()
	# No Lobby entry since #1604 (s05: the match settings are the ship's console, s04): its press
	# opens nothing.
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].visible).is_false()
	menu.press(EscMenuState.Tab.LOBBY)
	menu.refresh(GameFlow.Screen.LOBBY, model, -1, true)
	assert_object(menu.page()).is_null()
	assert_bool(menu.lobby.visible).is_false()
	assert_bool(menu.host_note.visible or menu.host_only.visible).is_false()
	menu.press(EscMenuState.Tab.GUIDE)
	menu.refresh(GameFlow.Screen.LOBBY, model, -1, true)
	assert_object(menu.page()).is_same(menu.guide)
	assert_bool(menu.page_tile.visible).is_true()
	assert_bool(menu.guide.is_visible_in_tree()).is_true()
	assert_bool(menu.confirm_box.visible).is_false()
	assert_bool(menu.tab_buttons[EscMenuState.Tab.GUIDE].button_pressed).is_true()
	# The round starts under the open menu: the Guide stays (s05 `round`), still no Lobby entry.
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": -1})
	menu.refresh(GameFlow.Screen.ROUND, model, -1, true)
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].visible).is_false()
	assert_object(menu.page()).is_same(menu.guide)
	assert_bool(menu.host_note.visible or menu.host_only.visible).is_false()
	# A second press closes an open page.
	menu.press(EscMenuState.Tab.SETTINGS)
	assert_object(menu.page()).is_same(menu.settings)
	menu.press(EscMenuState.Tab.SETTINGS)
	assert_object(menu.page()).is_null()


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
	# The lobby's panel, no page open (s05 `lobby`, #1571); no Lobby entry since #1604.
	assert_bool(ui.esc.state.has_tab(EscMenuState.Tab.GUIDE)).is_true()
	assert_bool(ui.esc.state.has_tab(EscMenuState.Tab.LOBBY)).is_false()
	assert_int(ui.esc.state.selected).is_equal(EscMenuState.Tab.GAME)
	ui.close_esc()
	ui.show_screen(GameFlow.Screen.LOBBY)
	ui.open_esc(false)
	# s05 at ui-2.5.4 (#1571): the side panel alone, no page open.
	assert_int(ui.esc.state.selected).is_equal(EscMenuState.Tab.GAME)
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
	# Leave is a panel entry like the others (s05); the host's confirm is the danger button.
	assert_str(String(menu.leave_button.theme_type_variation)).is_equal("ToyMenuItem")
	menu.leave_button.pressed.emit()
	assert_array(said).is_equal(["leave"])
	assert_bool(menu.confirm_box.visible).is_false()
	menu.open(GameFlow.Screen.ROUND, null, true)
	assert_str(String(menu.confirm_button.theme_type_variation)).is_equal("ToyButtonDanger")
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


## The shipped base mode with no test bench: both its maps are played, so the lobby has two to pick.
func _two_player_maps() -> GameMode:
	var mode := (load(MODE) as GameMode).duplicate() as GameMode
	mode.bench_maps = PackedStringArray()
	return mode


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
	assert_bool(menu.tab_buttons.has(EscMenuState.Tab.ROLE)).is_false()
	assert_bool(menu.tab_buttons[EscMenuState.Tab.LOBBY].visible).is_false()
	assert_str(menu.leave_button.text).is_equal("esc.game.leave_tutorial")
	menu.leave_button.pressed.emit()
	assert_array(said).is_equal(["leave"])
	assert_bool(menu.confirm_box.visible).is_false()


func test_the_esc_menu_is_built_as_the_handoff_names_it() -> void:
	# prime-game-ui's s05 at ui-2.5.4 (#1571), node for node: the side panel and the page beside it.
	var menu: EscMenu = auto_free(EscMenu.new())
	var paths: Dictionary[String, String] = {
		"Menu": "",
		"Menu/Side": "ToyPanelMenu",
		"Menu/Side/V": "ToyColumnSixteen",
		"Menu/Side/V/Head": "ToySettingRow",
		"Menu/Side/V/Head/V": "ToyColumnEight",
		"Menu/Side/V/Head/V/Label": "ToyKicker",
		"Menu/Side/V/Head/V/Row": "ToyRowTwelve",
		"Menu/Side/V/Head/V/Row/Value": "ToyTextOnLight",
		"Menu/Side/V/Head/V/Row/Copy": "ToyButtonSecondary",
		"Menu/Side/V/Entries": "ToyColumnFour",
		"Menu/Side/V/Entries/Resume": "ToyMenuItem",
		"Menu/Side/V/Entries/Guide": "ToyMenuItem",
		"Menu/Side/V/Entries/Lobby": "ToyMenuItem",
		"Menu/Side/V/Entries/Settings": "ToyMenuItem",
		"Menu/Side/V/Gap": "",
		"Menu/Side/V/Rule": "ToySettingRow",
		"Menu/Side/V/Bottom": "ToyColumnFour",
		"Menu/Side/V/Bottom/Leave": "ToyMenuItem",
		"Menu/Side/V/Bottom/Quit": "ToyMenuItem",
		"Menu/Page": "ToyPanelMenu",
		"Menu/Page/V/Settings": "ToyRowTwentyFour",
		"Menu/Page/V/Settings/Nav": "ToyColumnFour",
		"Menu/Page/V/Settings/Nav/Sound": "ToyMenuItem",
		"Menu/Page/V/Settings/Scroll/Rows/Sound/Mic": "ToySettingRow",
		"Menu/Page/V/Settings/Scroll/Rows/Controls/Talk/H/Bind": "ToyKeyButton",
		"Menu/Page/V/Settings/Scroll/Rows/Controls/Talk/H/Same": "ToyChipAlert",
		"Menu/Page/V/Guide": "ToyRowThirtyTwo",
		"ConfirmDim": "ToyBackdrop",
		"Confirm": "ToyPanelDialog",
		"Confirm/V": "ToyColumnThirtyTwo",
		"Confirm/V/Text": "ToyColumnSixteen",
		"Confirm/V/Buttons": "ToyRowTwentyFour",
		"Confirm/V/Buttons/ConfirmButton": "ToyButtonDanger",
		"Confirm/V/Buttons/Cancel": "ToyButtonGhostOnLight",
	}
	for path: String in paths:
		var node := menu.get_node_or_null(NodePath(path)) as Control
		assert_object(node).override_failure_message(path).is_not_null()
		var variation := String(node.theme_type_variation)
		assert_str(variation).override_failure_message(path).is_equal(paths[path])
	# No dim: the world stays visible beside the panel; the mouse passes Menu.
	assert_bool(menu.has_node(^"Dim")).is_false()
	assert_int(menu.menu.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# The panel at the left, full height; the page 24 px right of it, 1120 wide.
	var side := menu.side
	(
		assert_vector(
			Vector4(side.anchor_left, side.anchor_top, side.anchor_right, side.anchor_bottom)
		)
		. is_equal(Vector4(0, 0, 0, 1))
	)
	(
		assert_vector(
			Vector4(side.offset_left, side.offset_top, side.offset_right, side.offset_bottom)
		)
		. is_equal(Vector4(36, 36, 556, -36))
	)
	assert_vector(Vector2(menu.page_tile.offset_left, menu.page_tile.offset_top)).is_equal(
		Vector2(580, 36)
	)
	assert_float(menu.page_tile.custom_minimum_size.x).is_equal(1120.0)
	assert_vector(menu.confirm_box.custom_minimum_size).is_equal(Vector2(1080, 0))
	(
		assert_bool(
			(
				(menu.get_node(^"Menu/Side/V/Gap") as Control).size_flags_vertical
				== Control.SIZE_EXPAND_FILL
			)
		)
		. is_true()
	)
	for button: Button in [menu.resume_button, menu.leave_button, menu.quit_button]:
		assert_int(button.alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)


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


func test_a_later_copy_press_keeps_copied_showing_for_its_own_full_time() -> void:
	# The first press's timer firing must not end the second press's "Copied" early.
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.show_code(JoinProgress.code_text("K7M2QX", false), "K7M2QX")
	panel.copy_button.pressed.emit()
	var first := panel._copied_timer
	panel.copy_button.pressed.emit()
	assert_str(panel.copy_button.text).is_equal("esc.lobby.copied")
	panel._end_copied(first)
	assert_str(panel.copy_button.text).is_equal("esc.lobby.copied")
	panel._end_copied(panel._copied_timer)
	assert_str(panel.copy_button.text).is_equal("esc.lobby.copy")
