extends GdUnitTestSuite
## The lobby HUD's Controls (client/ui/LobbyHud, #495; ARCHITECTURE §4.7.47) under the shared
## theme: the UI handoff's tree node for node (prime-game-ui `ui-2.5.4` `docs/handoff/s04-lobby.md`:
## names, classes, variations, anchors, offsets, grow directions, size flags and minimum sizes),
## every node ignoring the mouse and focus, the names cut with an ellipsis, the tints, each state
## the handoff draws (boot's hint, wait, count, short), the rows rebuilt
## only when they change, a language change and large text.

const MODE := "res://content/modes/base_mode.tres"
const NOW := 100

var _mode: GameMode
var _locale := ""


func before() -> void:
	_mode = load(MODE) as GameMode


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_the_tree_is_the_handoffs_node_for_node() -> void:
	var hud := await _hud()
	# [path, class, variation] of every node the handoff lists in `wait` and `boot` (VoiceHint:
	# M5-6's, kept; Aim: the round HUD's chip, #1408, with the hand-over's cue, #1411).
	var nodes: Array[Array] = [
		["Cross", "Panel", &"ToyCrosshair"],
		["Aim", "PanelContainer", &"ToyChipPlate"],
		["Aim/Text", "Label", &"ToyChipPlateText"],
		["Status", "PanelContainer", &"ToyPlate"],
		["Status/Row", "HBoxContainer", &"ToyRowTwentyFour"],
		["Status/Row/Text", "Label", &"ToyPlateText"],
		["Status/Row/Pips", "HBoxContainer", &"ToyRowFour"],
		["Status/Row/Pips/P1", "Panel", &"ToyPipHealth"],
		["Status/Row/Pips/P3", "Panel", &"ToyPipHealth"],
		["Status/Row/Pips/P4", "Panel", &"ToyPip"],
		["Players", "PanelContainer", &"ToyRoster"],
		["Players/Rows", "VBoxContainer", &"ToyColumnEight"],
		["Players/Rows/Head", "Label", &"ToyKicker"],
		["Players/Rows/Host/HostTag", "PanelContainer", &"ToyRosterTagHost"],
		["Players/Rows/Host/HostTag/Text", "Label", &"ToyRosterTagHostText"],
		["Bottom", "HBoxContainer", &"ToyRowSixteen"],
		["Bottom/Hint", "PanelContainer", &"ToyPlate"],
		["Bottom/Hint/Row", "HBoxContainer", &"ToyRowTwelve"],
		["Bottom/Hint/Row/Key", "PanelContainer", &"ToyKeyOnDark"],
		["Bottom/Hint/Row/Key/Text", "Label", &"ToyKeyText"],
		["Bottom/Hint/Row/Text", "Label", &"ToyPlateTextMuted"],
		["Bottom/Ready", "PanelContainer", &"ToyPlate"],
		["Bottom/Ready/Row", "HBoxContainer", &"ToyRowTwelve"],
		["Bottom/Ready/Row/Pip", "Panel", &"ToyPip"],
		["Bottom/Ready/Row/Text", "Label", &"ToyPlateText"],
		["Bottom/Mic", "PanelContainer", &"ToyMic"],
		["Bottom/Mic/Icon", "TextureRect", &""],
		["VoiceHint", "PanelContainer", &"ToyChipPlate"],
		["VoiceHint/Text", "Label", &"ToyChipPlateText"],
	]
	for row_name: String in ["Host", "Row2", "Self", "Row4"]:
		var path := "Players/Rows/%s" % row_name
		nodes.append([path, "HBoxContainer", &"ToyRowTwelve"])
		nodes.append([path + "/Dot", "Panel", &"ToyRosterDot"])
		var own := row_name == "Self"
		nodes.append([path + "/Name", "Label", &"ToyRosterNameSelf" if own else &"ToyRosterName"])
		var pip := &"ToyPip" if own else &"ToyPipHealth"
		nodes.append([path + "/Ready", "Panel", pip])
	for node: Array in nodes:
		var found := hud.get_node_or_null(node[0] as String) as Control
		assert_object(found).override_failure_message(node[0] as String).is_not_null()
		assert_str(found.get_class()).override_failure_message(node[0] as String).is_equal(node[1])
		assert_str(found.theme_type_variation).override_failure_message(node[0] as String).is_equal(
			node[2]
		)
	assert_array(_names(hud)).is_equal(["Cross", "Aim", "Status", "Players", "Bottom", "VoiceHint"])
	assert_array(_names(hud.rows)).is_equal(["Head", "Host", "Row2", "Self", "Row4"])
	assert_array(_names(hud.bottom)).is_equal(["Hint", "Ready", "Mic"])
	# Only the host's row has the tag.
	for row_name: String in ["Row2", "Self", "Row4"]:
		assert_bool(hud.rows.has_node("%s/HostTag" % row_name)).is_false()
	# Texts: the deck's keys; data never translated (#208).
	assert_str(hud.ready_label.text).is_equal("lobby.ready_no")
	assert_str(_label(hud, "Bottom/Hint/Row/Text").text).is_equal("tutorial.list.menu")
	assert_str(_label(hud, "Players/Rows/Host/HostTag/Text").text).is_equal("hud.roster.host")
	assert_bool(hud.head_label.uppercase).is_true()
	var data: Array[Label] = [hud.status_label, hud.head_label, hud.hint_key_label]
	for path: String in ["Host", "Row2", "Self", "Row4"]:
		data.append(_label(hud, "Players/Rows/%s/Name" % path))
	for label: Label in data:
		assert_int(label.auto_translate_mode).override_failure_message(label.name).is_equal(
			Node.AUTO_TRANSLATE_MODE_DISABLED
		)
	assert_str(hud.status_label.text).is_equal("3 of 4 ready")
	assert_str(hud.head_label.text).is_equal("Players 4 / 10")
	assert_array(hud.row_texts()).is_equal(
		PackedStringArray(["Olena", "Taras", "Ivan (you)", "Marko"])
	)
	assert_array(hud.row_checks()).is_equal([true, true, false, true])
	# The body colours on the dots (data, as the round's roster).
	var dot := hud.get_node("Players/Rows/Row2/Dot") as Panel
	assert_object(dot.self_modulate).is_equal(BodyColours.of(1))
	# No session yet in these tests: the boot's hint hides.
	assert_bool(hud.hint.visible).is_false()


func test_anchors_offsets_grow_sizes_and_flags_are_the_handoffs() -> void:
	var hud := await _hud()
	var both := Control.GROW_DIRECTION_BOTH
	var begin := Control.GROW_DIRECTION_BEGIN
	var end := Control.GROW_DIRECTION_END
	# [node, anchors (left, top, right, bottom), offsets, grow h, grow v]
	var placed: Array[Array] = [
		[hud.cross, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 0, 0, 0), both, both],
		[hud.aim, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 64, 0, 64), both, both],
		[hud.status, Vector4(0.5, 0, 0.5, 0), Vector4(0, 36, 0, 36), both, end],
		[hud.players, Vector4(1, 0, 1, 0), Vector4(-36, 36, -36, 36), begin, end],
		[hud.bottom, Vector4(0, 1, 0, 1), Vector4(36, -36, 36, -36), end, begin],
	]
	for row: Array in placed:
		var node: Control = row[0]
		var anchors := Vector4(
			node.anchor_left, node.anchor_top, node.anchor_right, node.anchor_bottom
		)
		var offsets := Vector4(
			node.offset_left, node.offset_top, node.offset_right, node.offset_bottom
		)
		assert_vector(anchors).override_failure_message(node.name).is_equal(row[1])
		assert_vector(offsets).override_failure_message(node.name).is_equal(row[2])
		assert_int(node.grow_horizontal).is_equal(row[3])
		assert_int(node.grow_vertical).is_equal(row[4])
	assert_vector(hud.cross.custom_minimum_size).is_equal(Vector2(12, 12))
	assert_vector(hud.status.custom_minimum_size).is_equal(Vector2(360, 66))
	assert_vector(hud.players.custom_minimum_size).is_equal(Vector2(330, 0))
	assert_vector(hud.hint_key.custom_minimum_size).is_equal(Vector2(42, 0))
	assert_vector(hud.mic.custom_minimum_size).is_equal(Vector2(75, 75))
	assert_vector(hud.mic_icon.custom_minimum_size).is_equal(Vector2(42, 42))
	assert_vector(hud.ready_pip.custom_minimum_size).is_equal(Vector2(23, 15))
	var shrink_center := Control.SIZE_SHRINK_CENTER
	var shrink_end := Control.SIZE_SHRINK_END
	assert_int(hud.status_label.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_int(hud.status_label.size_flags_vertical).is_equal(shrink_center)
	assert_int(hud.status_pips.size_flags_vertical).is_equal(shrink_center)
	for tile: Control in [hud.hint, hud.ready_tile, hud.mic]:
		assert_int(tile.size_flags_vertical).override_failure_message(tile.name).is_equal(
			shrink_end
		)
	assert_int(hud.mic_icon.size_flags_horizontal).is_equal(shrink_center)
	assert_int(hud.mic_icon.size_flags_vertical).is_equal(shrink_center)
	assert_int(hud.mic_icon.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(hud.mic_icon.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	for line: Node in hud.rows.get_children():
		if line == hud.head_label:
			continue
		var name_label := line.get_node("Name") as Label
		var dot := line.get_node("Dot") as Panel
		var pip := line.get_node("Ready") as Panel
		assert_int(name_label.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
		assert_int(name_label.size_flags_vertical).is_equal(shrink_center)
		assert_vector(dot.custom_minimum_size).is_equal(Vector2(15, 15))
		assert_vector(pip.custom_minimum_size).is_equal(Vector2(23, 15))
		assert_int(pip.size_flags_vertical).is_equal(shrink_center)
	# The voice hint sits over the bottom row, never on it.
	hud.show_voice_hint(VoicePanel.LOBBY_HINT)
	await get_tree().process_frame
	await get_tree().process_frame
	var hint_bottom := hud.voice_hint.get_global_rect().end.y
	assert_float(hint_bottom).is_less_equal(hud.bottom.get_global_rect().position.y)


func test_no_node_takes_the_mouse_or_focus_and_names_cut_with_an_ellipsis() -> void:
	var hud := await _hud()
	var all: Array[Node] = hud.find_children("*", "Control", true, false)
	all.append(hud)
	for node: Node in all:
		var control := node as Control
		assert_int(control.mouse_filter).override_failure_message(str(control.get_path())).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).is_equal(Control.FOCUS_NONE)
	for line: Node in hud.rows.get_children():
		if line == hud.head_label:
			continue
		var label := line.get_node("Name") as Label
		assert_bool(label.clip_text).override_failure_message(label.name).is_true()
		assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	# A long name stays inside the 330 px tile.
	var model := _lobby(3, ["Olena", "Taras", "Ivan", "Marko"])
	model.roster[2].name = "Taras".repeat(12)
	hud.refresh(model, _mode, NOW)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(hud.players.size.x).is_equal(330.0)


func test_the_mic_takes_its_tints() -> void:
	var hud := await _hud()
	await get_tree().process_frame
	hud.show_mic(true)
	assert_object(hud.mic_icon.texture).is_same(ToyIcons.texture(&"mic"))
	assert_object(hud.mic_icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"icon_on", &"ToyMic")
	)
	assert_bool(hud.shows_mic_on()).is_true()
	hud.show_mic(false)
	assert_object(hud.mic_icon.texture).is_same(ToyIcons.texture(&"mic-off"))
	assert_object(hud.mic_icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"icon_off", &"ToyMic")
	)


func test_count_fills_every_pip_in_the_same_calm_text() -> void:
	var hud := await _hud()
	var model := _lobby(3, ["Olena", "Taras", "Ivan", "Marko"], true)
	model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": NOW + 5 * Ticks.RATE})
	hud.refresh(model, _mode, NOW)
	assert_str(hud.status_label.theme_type_variation).is_equal(&"ToyPlateText")
	assert_str(hud.status_label.text).is_equal("Starting in 5")
	assert_bool(hud.status_pips.visible).is_true()
	for pip: Node in hud.status_pips.get_children():
		assert_str((pip as Panel).theme_type_variation).is_equal(&"ToyPipHealth")
	assert_str(hud.ready_pip.theme_type_variation).is_equal(&"ToyPipHealth")
	assert_str(hud.ready_label.text).is_equal("lobby.ready_yes")
	assert_array(hud.row_checks()).is_equal([true, true, true, true])
	# An un-ready stops it: the own pip empties, the plate counts again.
	model.fold(&"ReadyChanged", {"peer": 3, "ready": false})
	model.fold(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	hud.refresh(model, _mode, NOW)
	assert_str(hud.ready_pip.theme_type_variation).is_equal(&"ToyPip")
	assert_str(hud.ready_label.text).is_equal("lobby.ready_no")
	assert_str(hud.status_label.text).is_equal("3 of 4 ready")


func test_short_hides_the_pips_and_says_how_many_more() -> void:
	var hud := await _hud()
	# The host's players_few (#548): one more of the four the handoff's sample needs.
	hud.refresh(_short(_lobby(3, ["Olena", "Taras", "Ivan"]), 1), _mode, NOW)
	assert_str(hud.status_label.text).is_equal("1 more player to start")
	assert_bool(hud.status_pips.visible).is_false()
	assert_str(hud.head_label.text).is_equal("Players 3 / 10")
	assert_array(_names(hud.rows)).is_equal(["Head", "Host", "Row2", "Self"])
	# The host alone: its own row "(you)" with the host's tag, no pip full.
	hud.refresh(_short(_lobby(1, ["Olena"]), 3), _mode, NOW)
	assert_str(hud.status_label.text).is_equal("3 more players to start")
	assert_array(_names(hud.rows)).is_equal(["Head", "Host"])
	assert_array(hud.row_texts()).is_equal(PackedStringArray(["Olena (you)"]))
	assert_str((hud.get_node("Players/Rows/Host/Name") as Label).theme_type_variation).is_equal(
		&"ToyRosterNameSelf"
	)
	assert_bool(hud.has_node("Players/Rows/Host/HostTag")).is_true()
	assert_array(hud.row_checks()).is_equal([false])


func test_the_boots_hint_shows_the_menu_key_only_when_given_one() -> void:
	var hud := await _hud()
	hud.show_hint("Esc")
	assert_bool(hud.hint.visible).is_true()
	assert_str(hud.hint_key_label.text).is_equal("Esc")
	hud.show_hint("")
	assert_bool(hud.hint.visible).is_false()


func test_the_rows_are_built_again_only_when_they_change() -> void:
	var hud := await _hud()
	var model := _lobby(3, ["Olena", "Taras", "Ivan", "Marko"])
	var first := hud.rows.get_child(2)
	hud.refresh(model, _mode, NOW + 7)
	assert_object(hud.rows.get_child(2)).is_same(first)
	model.roster[2].name = "Taras K"
	hud.refresh(model, _mode, NOW)
	assert_array(hud.row_texts()).is_equal(
		PackedStringArray(["Olena", "Taras K", "Ivan (you)", "Marko"])
	)
	model.fold(&"PlayerLeft", {"peer": 4})
	hud.refresh(model, _mode, NOW)
	assert_array(_names(hud.rows)).is_equal(["Head", "Host", "Row2", "Self"])
	assert_int(hud.status_pips.get_child_count()).is_equal(3)
	await get_tree().process_frame
	# Every row built later ignores the mouse and the focus too.
	for node: Node in hud.rows.find_children("*", "Control", true, false):
		assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		assert_int((node as Control).focus_mode).is_equal(Control.FOCUS_NONE)


func test_a_language_change_writes_the_texts_again() -> void:
	var hud := await _hud()
	TranslationServer.set_locale("uk")
	await get_tree().process_frame
	assert_str(hud.status_label.text).is_equal("Готові 3 з 4")
	assert_str(hud.head_label.text).is_equal("Гравці 4 / 10")
	assert_array(hud.row_texts()).is_equal(
		PackedStringArray(["Olena", "Taras", "Ivan (ти)", "Marko"])
	)


func test_large_text_keeps_the_tiles_sizes_and_widens_the_key() -> void:
	var hud := await _hud()
	var holder := hud.get_parent() as Control
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(hud.hint_key.custom_minimum_size).is_equal(Vector2(50, 0))
	assert_vector(hud.players.custom_minimum_size).is_equal(Vector2(330, 0))
	holder.theme = GameUi.THEME
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(hud.hint_key.custom_minimum_size).is_equal(Vector2(42, 0))


func test_the_voice_hint_shows_only_with_a_text() -> void:
	var hud := await _hud()
	assert_bool(hud.voice_hint.visible).is_false()
	hud.show_voice_hint(VoicePanel.LOBBY_HINT)
	assert_bool(hud.voice_hint.visible).is_true()
	hud.show_voice_hint("")
	assert_bool(hud.voice_hint.visible).is_false()


func test_aim_shows_only_with_a_text_its_key_translated() -> void:
	# The round HUD's Aim under the crosshair (#1408): the tap or a hall item E would use.
	var hud := await _hud()
	assert_bool(hud.aim.visible).is_false()
	hud.show_aim(ContentNames.station(&"tap"))
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal(ContentNames.station(&"tap"))
	assert_int(hud.aim_label.auto_translate_mode).is_not_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	hud.show_aim("")
	assert_bool(hud.aim.visible).is_false()


func test_the_bars_aim_names_read_the_deck_in_both_languages() -> void:
	# #1430 (ui-2.5.2): the tap and the two mugs are the deck's `station.tap`, `item.mug`,
	# `item.mug_empty`, never a raw id; Aim translates them, so a switch rewrites the chip.
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale(Languages.ENGLISH)
	var hud := await _hud()
	hud.show_aim(ContentNames.station(&"tap"))
	assert_str(ContentNames.text(hud.aim_label.text)).is_equal("Beer tap")
	hud.show_aim(ContentNames.item(&"mug", _mode))
	assert_str(ContentNames.text(hud.aim_label.text)).is_equal("Mug of beer")
	hud.show_aim(ContentNames.item(&"mug_empty", _mode))
	assert_str(ContentNames.text(hud.aim_label.text)).is_equal("Empty mug")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_str(ContentNames.text(hud.aim_label.text)).is_equal("Порожній кухоль")
	hud.show_aim(ContentNames.item(&"mug", _mode))
	assert_str(ContentNames.text(hud.aim_label.text)).is_equal("Кухоль пива")
	hud.show_aim(ContentNames.station(&"tap"))
	assert_str(ContentNames.text(hud.aim_label.text)).is_equal("Пивний кран")
	TranslationServer.set_locale(locale)


func test_the_hand_over_cue_shows_only_with_a_key_and_keeps_it_on_a_language_change() -> void:
	# #1411: Aim under the crosshair holds the hand-over's cue while E would hand over.
	var hud := await _hud()
	assert_bool(hud.aim.visible).is_false()
	hud.show_hand_over("E")
	assert_bool(hud.aim.visible).is_true()
	assert_int(hud.aim_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_str(hud.aim_label.text).is_equal(HudText.hand_over_cue("E"))
	assert_str(hud.aim_label.text).is_equal("Press E to hand it over")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_str(hud.aim_label.text).is_equal("Натисни E, щоб передати")
	TranslationServer.set_locale(Languages.ENGLISH)
	hud.show_hand_over("")
	assert_bool(hud.aim.visible).is_false()


func test_the_take_and_the_cancel_cues_are_worded_by_their_deck_keys() -> void:
	# #1434: the same chip, worded by HandOverUse.cue_key(); the rows are in the deck since
	# ui-2.5.3 (#1446).
	var hud := await _hud()
	var texts: Dictionary[String, String] = {
		HudText.TAKE_OFFER_CUE: "Press E to take it",
		HudText.OFFERING_CUE: "Press E to take it back",
	}
	for cue_key: String in texts:
		hud.show_hand_over("E", cue_key)
		assert_bool(hud.aim.visible).is_true()
		assert_str(hud.aim_label.text).is_equal(HudText.hand_over_cue("E", cue_key))
		assert_str(hud.aim_label.text).is_equal(texts[cue_key])
	hud.show_hand_over("E")
	assert_str(hud.aim_label.text).is_equal("Press E to hand it over")
	hud.show_hand_over("")
	assert_bool(hud.aim.visible).is_false()


func test_the_hand_over_cue_takes_aim_from_the_taps_text_and_gives_it_back() -> void:
	# #1408 and #1411 share the chip: the cue wins while there is one, the text returns after it.
	var hud := await _hud()
	hud.show_aim(ContentNames.station(&"tap"))
	hud.show_hand_over("E")
	assert_str(hud.aim_label.text).is_equal("Press E to hand it over")
	assert_int(hud.aim_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	hud.show_hand_over("")
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal(ContentNames.station(&"tap"))
	assert_int(hud.aim_label.auto_translate_mode).is_not_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	hud.show_aim("")
	assert_bool(hud.aim.visible).is_false()


## The handoff's lobby: Olena hosts (peer 1), the own player is `own`; everyone but the own player
## ready, or everyone with `all_ready`.
func _lobby(own: int, names: Array, all_ready := false) -> ClientModel:
	var model := ClientModel.new(_mode)
	var welcome := WelcomeEvent.new(own, Vector3.ZERO, 1)
	for index in names.size():
		var peer := index + 1
		var ready_now := all_ready or peer != own
		welcome.roster.append(
			{"peer": peer, "name": names[index], "ready": ready_now, "colour": index}
		)
	welcome.settings = _mode.default_settings()
	welcome.map = _mode.default_map()
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	return model


static func _names(parent: Node) -> Array[String]:
	var names: Array[String] = []
	for child: Node in parent.get_children():
		names.append(String(child.name))
	return names


static func _label(hud: LobbyHud, path: String) -> Label:
	return hud.get_node(path) as Label


## A LobbyHud under the shared theme at the 1920x1080 base in the handoff's `wait`, after its sizes
## were read.
func _hud() -> LobbyHud:
	var holder: Control = auto_free(Control.new())
	holder.theme = GameUi.THEME
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var hud := LobbyHud.new()
	holder.add_child(hud)
	hud.refresh(_lobby(3, ["Olena", "Taras", "Ivan", "Marko"]), _mode, NOW)
	await get_tree().process_frame
	return hud


## `model` with the host's SettingsChanged saying `missing` more players are needed (FitCheck's
## players_few against four, the handoff's sample).
static func _short(model: ClientModel, missing: int) -> ClientModel:
	var players_few := {
		"id": &"players_few",
		"ids": PackedStringArray(),
		"numbers": {&"count": missing, &"min": 4, &"max": 10},
	}
	var fields := {
		"settings": model.settings,
		"id_sets": model.id_sets,
		"map": model.map,
		"shortfalls": [players_few],
		"lobby_name": model.lobby_name,
	}
	model.fold(&"SettingsChanged", fields)
	return model
