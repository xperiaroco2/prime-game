extends GdUnitTestSuite
## The main menu (client/ui/main_menu.gd, #493): prime-game-ui's s2 handoff at ui-0.4.0 node for
## node, its five states, the items' group and focus, Esc, the code field's alphabet and Join at
## six characters, the Direct panel's Join and Host, the name row bound to UserSettings, and the
## texts in both languages. The game's wiring is in tests/integration/client/app/ (Esc in
## esc_menu_input_test.gd, the Settings panel's voice in game_voice_test.gd). How it looks: the
## `shot`s of client/dev/screen_preview.gd per state (`menu_state`, `language`, `large_text`).

const DECK := "res://client/i18n/strings.csv"
const CODE_V := "Column/Body/CodePanelRaised/CodePanel/V"
const DIRECT_V := "Column/Body/DirectPanelRaised/DirectPanel/V"

var _menu: MainMenu


func before_test() -> void:
	_menu = auto_free(MainMenu.new())
	_menu.theme = GameUi.THEME
	add_child(_menu)


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_the_tree_matches_the_handoff_node_for_node() -> void:
	# [path, class, variation, minimum size] as the handoff's node lines give them.
	var nodes: Array = [
		["Backdrop", "Panel", &"ToyBackdrop", Vector2.ZERO],
		["Column", "VBoxContainer", &"ToyColumnTwentyFour", Vector2.ZERO],
		["Column/Logo", "Label", &"ToyLogo", Vector2.ZERO],
		["Column/NameRow", "HBoxContainer", &"ToyRowTwelve", Vector2(592, 0)],
		["Column/NameRow/NameLabel", "Label", &"ToyTextMutedOnDark", Vector2.ZERO],
		["Column/NameRow/Name", "LineEdit", &"ToyField", Vector2.ZERO],
		["Column/Body", "HBoxContainer", &"ToyRowThirtyTwo", Vector2.ZERO],
		["Column/Body/Items", "VBoxContainer", &"ToyColumnFour", Vector2(592, 0)],
		["Column/Body/Gap", "Control", &"", Vector2(64, 0)],
		["Column/Body/CodePanelRaised", "MarginContainer", &"", Vector2(784, 0)],
		["Column/Body/CodePanelRaised/CodePanel", "PanelContainer", &"ToyPanelMenu", Vector2.ZERO],
		[CODE_V, "VBoxContainer", &"ToyColumnSixteen", Vector2.ZERO],
		[CODE_V + "/Field", "VBoxContainer", &"ToyColumnEight", Vector2.ZERO],
		[CODE_V + "/Field/CodeLabel", "Label", &"ToyTextMutedOnLight", Vector2.ZERO],
		[CODE_V + "/Field/Code", "LineEdit", &"ToyField", Vector2.ZERO],
		[CODE_V + "/Buttons", "HBoxContainer", &"ToyRowSixteen", Vector2.ZERO],
		[CODE_V + "/Buttons/JoinRaised/Join", "Button", &"ToyButtonPrimary", Vector2.ZERO],
		[CODE_V + "/Buttons/Back", "Button", &"ToyButtonGhostOnLight", Vector2.ZERO],
		["Column/Body/DirectPanelRaised", "MarginContainer", &"", Vector2(784, 0)],
		[
			"Column/Body/DirectPanelRaised/DirectPanel",
			"PanelContainer",
			&"ToyPanelMenu",
			Vector2.ZERO
		],
		[DIRECT_V, "VBoxContainer", &"ToyColumnSixteen", Vector2.ZERO],
		[DIRECT_V + "/Field", "VBoxContainer", &"ToyColumnEight", Vector2.ZERO],
		[DIRECT_V + "/Field/AddressLabel", "Label", &"ToyTextMutedOnLight", Vector2.ZERO],
		[DIRECT_V + "/Field/Address", "LineEdit", &"ToyField", Vector2.ZERO],
		[DIRECT_V + "/Field/Port", "Label", &"ToyTextMutedOnLight", Vector2.ZERO],
		[DIRECT_V + "/Buttons", "HBoxContainer", &"ToyRowSixteen", Vector2.ZERO],
		[DIRECT_V + "/Buttons/JoinRaised/Join", "Button", &"ToyButtonPrimary", Vector2.ZERO],
		[DIRECT_V + "/Buttons/HostRaised/Host", "Button", &"ToyButtonSecondary", Vector2.ZERO],
		[DIRECT_V + "/Buttons/Back", "Button", &"ToyButtonGhostOnLight", Vector2.ZERO],
		["SettingsPanelRaised/SettingsPanel", "PanelContainer", &"ToyPanelMenu", Vector2.ZERO],
		["Version", "Label", &"ToyTextMutedOnDark", Vector2.ZERO],
	]
	for item: String in ["Host", "Join", "Direct", "Tutorial", "Settings", "Quit"]:
		nodes.append(["Column/Body/Items/" + item, "Button", &"ToyMenuItem", Vector2.ZERO])
	for each: Array in nodes:
		var path := str(each[0])
		var found := _menu.get_node_or_null(NodePath(path)) as Control
		assert_object(found).override_failure_message(path).is_not_null()
		if found == null:
			continue
		assert_str(found.get_class()).override_failure_message(path).is_equal(str(each[1]))
		assert_str(String(found.theme_type_variation)).override_failure_message(path).is_equal(
			String(each[2] as StringName)
		)
		assert_that(found.custom_minimum_size).override_failure_message(path).is_equal(each[3])
	# The roots in the handoff's order; the items in theirs, then the gap and the two panels.
	assert_array(_names(_menu)).contains_exactly(
		["Backdrop", "Column", "SettingsPanelRaised", "Version"]
	)
	assert_array(_names(_menu.items)).contains_exactly(
		["Host", "Join", "Direct", "Tutorial", "Settings", "Quit"]
	)
	assert_array(_names(_menu.body)).contains_exactly(
		["Items", "Gap", "CodePanelRaised", "DirectPanelRaised"]
	)
	# Anchors, offsets and grow as drawn.
	_assert_rect(_menu.backdrop, Control.PRESET_FULL_RECT, Rect2(), Control.GROW_DIRECTION_BOTH)
	assert_int(_menu.backdrop.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	_assert_rect(
		_menu.column, Control.PRESET_TOP_LEFT, Rect2(136, 256, 0, 0), Control.GROW_DIRECTION_END
	)
	_assert_rect(
		_menu.settings_panel,
		Control.PRESET_TOP_LEFT,
		Rect2(856, 96, 960, 888),
		Control.GROW_DIRECTION_END
	)
	_assert_rect(
		_menu.version_label,
		Control.PRESET_BOTTOM_RIGHT,
		Rect2(-40, -40, 0, 0),
		Control.GROW_DIRECTION_BEGIN
	)
	# Size flags as drawn; the panels raised on their light-context base, sized on the wrapper.
	assert_int(_menu.name_row.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_int(_menu.name_edit.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_int(_menu.items.size_flags_vertical).is_equal(Control.SIZE_SHRINK_BEGIN)
	var label := _menu.name_row.get_node(^"NameLabel") as Label
	assert_int(label.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	for panel: ToyRaised in [_menu.code_panel, _menu.direct_panel, _menu.settings_panel]:
		assert_str(String(panel.base.theme_type_variation)).is_equal("ToyBasePanel")
	for panel: ToyRaised in [_menu.code_panel, _menu.direct_panel]:
		assert_int(panel.size_flags_vertical).is_equal(Control.SIZE_SHRINK_BEGIN)
	for join: ToyRaised in [_menu.code_join, _menu.direct_join]:
		assert_int(join.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
		assert_str(String(join.base.theme_type_variation)).is_equal("ToyBasePrimaryOnLight")
		assert_object(join.face.get_node(^"ToyPress")).is_not_null()
	assert_str(String(_menu.direct_host.base.theme_type_variation)).is_equal("ToyBaseRaisedOnLight")
	assert_object(_menu.code_back.get_node(^"ToyPress")).is_not_null()
	assert_object(_menu.direct_back.get_node(^"ToyPress")).is_not_null()
	# The data texts are never translated; the logo is the working title.
	assert_str(_menu.logo.text).is_equal("prime-game")
	for data: Control in [
		_menu.logo,
		_menu.name_edit,
		_menu.code_edit,
		_menu.address_edit,
		_menu.port_label,
		_menu.version_label
	]:
		assert_int(data.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_the_items_are_menu_items_with_the_pointer_and_three_toggle_in_one_group() -> void:
	var keys := ["menu.host", "menu.join", "menu.direct", "menu.tutorial", "menu.settings"]
	keys.append("menu.quit")
	var items: Array[Button] = _items()
	for index in items.size():
		var item := items[index]
		assert_str(item.text).is_equal(keys[index])
		assert_object(item.icon).is_not_null()
		assert_that(item.icon.get_size()).is_equal(Vector2(24, 24))
		assert_int(item.alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
		assert_int(item.focus_mode).is_equal(Control.FOCUS_ALL)
	for item: Button in [_menu.join_item, _menu.direct_item, _menu.settings_item]:
		assert_bool(item.toggle_mode).is_true()
		assert_bool(item.button_pressed).is_false()
		assert_object(item.button_group).is_same(_menu.item_group)
	assert_bool(_menu.item_group.allow_unpress).is_true()
	for item: Button in [_menu.host_item, _menu.tutorial_item, _menu.quit_item]:
		assert_bool(item.toggle_mode).is_false()
	# No tutorial yet (#492): the item is drawn, unplugged.
	assert_bool(_menu.tutorial_item.disabled).is_true()
	# The pointer shows only on the focused, hovered or pressed item (ToyMenuItem's colours).
	assert_float(_menu.host_item.get_theme_color(&"icon_normal_color").a).is_equal(0.0)
	assert_float(_menu.host_item.get_theme_color(&"icon_focus_color").a).is_equal(1.0)
	assert_float(_menu.host_item.get_theme_color(&"icon_pressed_color").a).is_equal(1.0)


func test_host_and_quit_say_so() -> void:
	var said: Array[String] = []
	_menu.code_host_requested.connect(func() -> void: said.append("host"))
	_menu.quit_requested.connect(func() -> void: said.append("quit"))
	_menu.host_item.pressed.emit()
	_menu.quit_item.pressed.emit()
	assert_array(said).contains_exactly(["host", "quit"])


func test_every_state_is_reached_by_its_item_and_closed_by_it_back_or_another() -> void:
	assert_str(String(_menu.state())).is_equal("main")
	_assert_shown(MainMenu.Open.NONE)
	_menu.join_item.button_pressed = true
	assert_str(String(_menu.state())).is_equal("code")
	_assert_shown(MainMenu.Open.CODE)
	assert_bool((_menu.code_join.face as Button).disabled).is_true()
	_menu.code_edit.text = "K7Q2XR"
	_menu.code_edit.text_changed.emit(_menu.code_edit.text)
	assert_str(String(_menu.state())).is_equal("code-ready")
	assert_bool((_menu.code_join.face as Button).disabled).is_false()
	# Another item of the group: its panel instead, the first item unpressed.
	_menu.direct_item.button_pressed = true
	assert_str(String(_menu.state())).is_equal("direct")
	_assert_shown(MainMenu.Open.DIRECT)
	_menu.settings_item.button_pressed = true
	assert_str(String(_menu.state())).is_equal("settings")
	_assert_shown(MainMenu.Open.SETTINGS)
	assert_bool(_menu.settings_open()).is_true()
	assert_bool(_menu.voice.is_visible_in_tree()).is_true()
	# Pressing the pressed item again closes its panel (allow_unpress).
	_menu.settings_item.button_pressed = false
	assert_str(String(_menu.state())).is_equal("main")
	_assert_shown(MainMenu.Open.NONE)
	# Back closes the code and the Direct panels.
	_menu.join_item.button_pressed = true
	_menu.code_back.pressed.emit()
	_assert_shown(MainMenu.Open.NONE)
	_menu.direct_item.button_pressed = true
	_menu.direct_back.pressed.emit()
	_assert_shown(MainMenu.Open.NONE)


func test_the_focus_starts_on_host_goes_to_the_field_and_back_to_the_item() -> void:
	_menu.visible = false
	_menu.visible = true
	await _frames(2)
	assert_object(_focus()).is_same(_menu.host_item)
	# Up and down move through the items: each names the next as drawn.
	var items: Array[Button] = _items()
	for index in items.size() - 1:
		var below := items[index].find_valid_focus_neighbor(SIDE_BOTTOM)
		assert_object(below).override_failure_message(items[index].name).is_same(items[index + 1])
	_menu.join_item.button_pressed = true
	await _frames(1)
	assert_object(_focus()).is_same(_menu.code_edit)
	_menu.code_back.pressed.emit()
	assert_object(_focus()).is_same(_menu.join_item)
	_menu.direct_item.button_pressed = true
	await _frames(1)
	assert_object(_focus()).is_same(_menu.address_edit)
	_menu.close_panel()
	assert_object(_focus()).is_same(_menu.direct_item)
	_menu.settings_item.button_pressed = true
	await _frames(1)
	assert_object(_focus()).is_same(_menu.voice.device_button)
	_menu.settings_item.button_pressed = false
	assert_object(_focus()).is_same(_menu.settings_item)


func test_esc_closes_the_open_panel_and_gives_the_focus_back_to_its_item() -> void:
	for item: Button in [_menu.join_item, _menu.direct_item, _menu.settings_item]:
		item.button_pressed = true
		await _frames(1)
		_press(KEY_ESCAPE)
		assert_str(String(_menu.state())).override_failure_message(item.name).is_equal("main")
		assert_bool(item.button_pressed).is_false()
		assert_object(_focus()).is_same(item)
	# With no panel open Esc is not the menu's: it passes on.
	var seen: Array[bool] = []
	var probe := _EscProbe.new()
	probe.seen = seen
	add_child(probe)
	move_child(probe, 0)
	_press(KEY_ESCAPE)
	assert_array(seen).contains_exactly([true])
	probe.free()


## Seen in the large-text shot: follow_focus scrolled to the first row before the panel's first
## sort, with the sizes before it, and cut that row off.
func test_the_settings_open_at_their_top_also_under_large_text() -> void:
	_menu.theme = GameUi.THEME_LARGE
	await _frames(1)
	_menu.settings_item.button_pressed = true
	await _frames(3)
	var scroll := _menu.settings_page as ScrollContainer
	assert_bool(scroll.get_v_scroll_bar().max_value > scroll.size.y).is_true()
	assert_int(scroll.scroll_vertical).is_equal(0)
	assert_object(_focus()).is_same(_menu.voice.device_button)


func test_the_code_field_takes_only_the_alphabet_upper_case_and_six_at_most() -> void:
	assert_str(MainMenu.code_text("k7m-2qx")).is_equal("K7M2QX")
	assert_str(MainMenu.code_text(" k7 m2 qx ")).is_equal("K7M2QX")
	# 0, O, 1, I and L are not in the alphabet; the seventh character goes.
	assert_str(MainMenu.code_text("o0i1l2")).is_equal("2")
	assert_str(MainMenu.code_text("ABCDEFGH")).is_equal("ABCDEF")
	assert_int(_menu.code_edit.max_length).is_equal(6)
	assert_bool(_menu.code_edit.context_menu_enabled).is_false()
	_menu.open_panel(MainMenu.Open.CODE)
	await _frames(1)
	# Typed: upper-cased, a dash and a zero dropped as they come.
	for typed: String in ["k", "-", "7", "0", "m"]:
		_menu.code_edit.insert_text_at_caret(typed)
		_menu.code_edit.text_changed.emit(_menu.code_edit.text)
	assert_str(_menu.code_edit.text).is_equal("K7M")
	assert_int(_menu.code_edit.caret_column).is_equal(3)
	assert_bool((_menu.code_join.face as Button).disabled).is_true()
	# A paste longer than the room left: the dash goes and all six letters stay.
	_menu.code_edit.text = ""
	_menu.code_edit.insert_text_at_caret("k7m-2qx")
	await _frames(1)
	assert_str(_menu.code_edit.text).is_equal("K7M2QX")
	assert_bool((_menu.code_join.face as Button).disabled).is_false()


func test_join_takes_a_whole_code_and_enter_joins_only_then() -> void:
	var codes: Array[String] = []
	_menu.code_join_requested.connect(func(code: String) -> void: codes.append(code))
	_menu.open_panel(MainMenu.Open.CODE)
	_menu.code_edit.text = "K7Q2X"
	_menu.code_edit.text_changed.emit(_menu.code_edit.text)
	assert_bool((_menu.code_join.face as Button).disabled).is_true()
	_menu.code_edit.text_submitted.emit(_menu.code_edit.text)
	assert_array(codes).is_empty()
	_menu.code_edit.caret_column = _menu.code_edit.text.length()
	_menu.code_edit.insert_text_at_caret("r")
	_menu.code_edit.text_changed.emit(_menu.code_edit.text)
	assert_bool((_menu.code_join.face as Button).disabled).is_false()
	_menu.code_edit.text_submitted.emit(_menu.code_edit.text)
	(_menu.code_join.face as Button).pressed.emit()
	assert_array(codes).contains_exactly(["K7Q2XR", "K7Q2XR"])


func test_the_code_field_opens_empty_but_keeps_the_code_on_a_failures_return() -> void:
	_menu.open_panel(MainMenu.Open.CODE)
	_menu.code_edit.text = "K7Q2XR"
	_menu.close_panel()
	_menu.join_item.button_pressed = true
	assert_str(_menu.code_edit.text).is_empty()
	_menu.code_edit.text = "K7Q2XR"
	# Back from a failure: the menu shows again as it was, the code kept.
	_menu.visible = false
	_menu.visible = true
	await _frames(2)
	assert_str(_menu.code_edit.text).is_equal("K7Q2XR")
	assert_object(_focus()).is_same(_menu.code_edit)
	_menu.open_panel(MainMenu.Open.CODE, false)
	assert_str(_menu.code_edit.text).is_equal("K7Q2XR")


func test_direct_joins_an_address_that_parses_and_hosts_on_the_typed_port() -> void:
	var joins: Array = []
	var hosts: Array[int] = []
	_menu.join_requested.connect(
		func(address: String, port: int) -> void: joins.append([address, port])
	)
	_menu.host_requested.connect(func(port: int) -> void: hosts.append(port))
	_menu.set_default_port(7777)
	_menu.open_panel(MainMenu.Open.DIRECT)
	var join := _menu.direct_join.face as Button
	assert_bool(join.disabled).is_true()
	_menu.address_edit.text_submitted.emit("")
	assert_array(joins).is_empty()
	# A text that is not an address keeps Join unplugged too (JoinTarget's problems).
	for typed: String in ["bad name!", "192.168.0.12:99999", "[::1"]:
		_menu.address_edit.text = typed
		_menu.address_edit.text_changed.emit(typed)
		assert_bool(join.disabled).override_failure_message(typed).is_true()
	for typed: String in ["192.168.0.12", "play.example.org:24600", "[::1]:7000"]:
		_menu.address_edit.text = typed
		_menu.address_edit.text_changed.emit(typed)
		assert_bool(join.disabled).override_failure_message(typed).is_false()
	_menu.address_edit.text = " 192.168.0.12 "
	_menu.address_edit.text_changed.emit(_menu.address_edit.text)
	_menu.address_edit.text_submitted.emit(_menu.address_edit.text)
	join.pressed.emit()
	assert_array(joins).contains_exactly([["192.168.0.12", 7777], ["192.168.0.12", 7777]])
	# Host: the port typed after the address, else the default.
	var host := _menu.direct_host.face as Button
	host.pressed.emit()
	_menu.address_edit.text = ":7010"
	host.pressed.emit()
	_menu.address_edit.text = "192.168.0.12:7020"
	host.pressed.emit()
	_menu.address_edit.text = ""
	host.pressed.emit()
	assert_array(hosts).contains_exactly([7777, 7010, 7020, 7777])
	assert_bool(_menu.address_edit.context_menu_enabled).is_false()


func test_the_name_row_shows_and_keeps_the_own_name() -> void:
	var settings := UserSettings.new()
	settings.player_name = "Olena"
	_menu.bind_name(settings)
	assert_str(_menu.name_edit.text).is_equal("Olena")
	assert_int(_menu.name_edit.max_length).is_equal(16)
	assert_bool(_menu.name_edit.context_menu_enabled).is_false()
	_menu.name_edit.text = "Олена  "
	_menu.name_edit.text_changed.emit(_menu.name_edit.text)
	assert_str(settings.player_name).is_equal("Олена")
	# Emptied: the name kept stays, and the field shows it again once left.
	_menu.name_edit.text = ""
	_menu.name_edit.text_changed.emit("")
	assert_str(settings.player_name).is_equal("Олена")
	_menu.name_edit.focus_exited.emit()
	assert_str(_menu.name_edit.text).is_equal("Олена")


func test_the_name_is_saved_between_sessions() -> void:
	var path := "user://main_menu_test_settings.cfg"
	var settings := UserSettings.new(path)
	_menu.bind_name(settings)
	_menu.name_edit.text = "Taras"
	_menu.name_edit.text_changed.emit("Taras")
	var next := UserSettings.new(path)
	assert_int(next.read()).is_equal(OK)
	assert_str(next.player_name).is_equal("Taras")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_port_and_version_lines_follow_the_language() -> void:
	_menu.set_default_port(7777)
	assert_str(_menu.port_label.text).is_equal("Port 7777")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	_menu.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(_menu.port_label.text).is_equal("Порт 7777")
	# The version: shown with the project's, hidden while project.godot names none.
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_bool(_menu.version_label.visible).is_equal(not version.is_empty())
	if not version.is_empty():
		assert_str(_menu.version_label.text).is_equal("Версія %s" % version)


func test_every_key_the_menu_names_is_in_the_deck() -> void:
	var keys: Array[String] = [
		"common.back",
		"common.code",
		"join.address",
		"join.connect",
		"join.port",
		"menu.direct",
		"menu.host",
		"menu.join",
		"menu.quit",
		"menu.settings",
		"menu.tutorial",
		"menu.version",
		"player.name",
	]
	var deck := _deck_keys()
	for key: String in keys:
		assert_bool(deck.has(key)).override_failure_message(key).is_true()
	for item: Button in _items():
		assert_bool(deck.has(item.text)).override_failure_message(item.text).is_true()


## Esc reaching a node under the menu's parent once the menu let it pass.
class _EscProbe:
	extends Node
	var seen: Array[bool] = []

	func _input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_cancel"):
			seen.append(true)


func _items() -> Array[Button]:
	return [
		_menu.host_item,
		_menu.join_item,
		_menu.direct_item,
		_menu.tutorial_item,
		_menu.settings_item,
		_menu.quit_item
	]


func _assert_shown(which: MainMenu.Open) -> void:
	assert_bool(_menu.code_panel.visible).is_equal(which == MainMenu.Open.CODE)
	assert_bool(_menu.direct_panel.visible).is_equal(which == MainMenu.Open.DIRECT)
	assert_bool(_menu.settings_panel.visible).is_equal(which == MainMenu.Open.SETTINGS)
	var in_body := which == MainMenu.Open.CODE or which == MainMenu.Open.DIRECT
	assert_bool(_menu.gap.visible).is_equal(in_body)
	assert_bool(_menu.join_item.button_pressed).is_equal(which == MainMenu.Open.CODE)
	assert_bool(_menu.direct_item.button_pressed).is_equal(which == MainMenu.Open.DIRECT)
	assert_bool(_menu.settings_item.button_pressed).is_equal(which == MainMenu.Open.SETTINGS)


func _assert_rect(
	control: Control, preset: Control.LayoutPreset, offsets: Rect2, grow: Control.GrowDirection
) -> void:
	var probe := Control.new()
	probe.set_anchors_preset(preset)
	var why := String(control.name)
	assert_float(control.anchor_left).override_failure_message(why).is_equal(probe.anchor_left)
	assert_float(control.anchor_top).override_failure_message(why).is_equal(probe.anchor_top)
	assert_float(control.anchor_right).override_failure_message(why).is_equal(probe.anchor_right)
	assert_float(control.anchor_bottom).override_failure_message(why).is_equal(probe.anchor_bottom)
	probe.free()
	assert_float(control.offset_left).override_failure_message(why).is_equal(offsets.position.x)
	assert_float(control.offset_top).override_failure_message(why).is_equal(offsets.position.y)
	assert_float(control.offset_right).override_failure_message(why).is_equal(offsets.end.x)
	assert_float(control.offset_bottom).override_failure_message(why).is_equal(offsets.end.y)
	assert_int(control.grow_horizontal).override_failure_message(why).is_equal(grow)
	assert_int(control.grow_vertical).override_failure_message(why).is_equal(grow)


func _press(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _names(parent: Node) -> Array[String]:
	var found: Array[String] = []
	for child: Node in parent.get_children():
		found.append(String(child.name))
	return found


## The copy deck's keys (its first column; the plural rows have none).
func _deck_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(DECK, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if not row.is_empty() and not row[0].is_empty():
			keys.append(row[0])
	return keys


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
