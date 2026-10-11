extends GdUnitTestSuite
## The lobby HUD's Controls (client/ui/LobbyHud, #495; ARCHITECTURE §4.7.42) under the shared
## theme: the UI handoff's tree node for node (prime-game-ui `ui-0.4.0` `docs/handoff/s04-lobby.md`:
## names, classes, variations, anchors, offsets, grow directions, size flags and minimum sizes),
## every node ignoring the mouse and focus, the names cut with an ellipsis, the tints, each state
## the handoff draws (wait, count, short, code-waiting, direct; the code gone), the rows rebuilt
## only when they change, a language change and large text.

const MODE := "res://content/modes/base_mode.tres"
const NOW := 100
const CODE := "K7Q2XR"

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
	# [path, class, variation] of every node the handoff lists in `wait` (VoiceHint: M5-6's, kept).
	var nodes: Array[Array] = [
		["Cross", "Panel", &"ToyCrosshair"],
		["Status", "PanelContainer", &"ToyPlate"],
		["Status/Text", "Label", &"ToyPlateText"],
		["Players", "PanelContainer", &"ToyPlate"],
		["Players/V", "VBoxContainer", &"ToyColumnSixteen"],
		["Players/V/Info", "VBoxContainer", &"ToyColumnEight"],
		["Players/V/Info/LobbyName", "Label", &"ToyTextMutedOnDark"],
		["Players/V/Info/CodeRow", "HBoxContainer", &"ToyRowEight"],
		["Players/V/Info/CodeRow/Label", "Label", &"ToyTextMutedOnDark"],
		["Players/V/Info/CodeRow/Code", "PanelContainer", &"ToyKeyOnDark"],
		["Players/V/Info/CodeRow/Code/Text", "Label", &"ToyKeyText"],
		["Players/V/List", "VBoxContainer", &"ToyColumnEight"],
		["Players/V/List/Head", "Label", &"ToyTextOnDark"],
		["Players/V/List/Rows", "VBoxContainer", &"ToyColumnEight"],
		["Bottom", "VBoxContainer", &"ToyColumnTwelve"],
		["Bottom/VoiceHint", "PanelContainer", &"ToyChipPlate"],
		["Bottom/VoiceHint/Text", "Label", &"ToyChipPlateText"],
		["Bottom/ReadyChip", "PanelContainer", &"ToyChipPlate"],
		["Bottom/ReadyChip/Text", "Label", &"ToyChipPlateText"],
		["Bottom/Mic", "PanelContainer", &"ToyMic"],
		["Bottom/Mic/Icon", "TextureRect", &""],
	]
	for row_name: String in ["HostRow", "Row2", "OwnRow", "Row4"]:
		var path := "Players/V/List/Rows/%s" % row_name
		nodes.append([path, "HBoxContainer", &"ToyRowTwelve"])
		nodes.append([path + "/Name", "Label", &"ToyTextOnDark"])
		nodes.append([path + "/Ready", "TextureRect", &""])
	for node: Array in nodes:
		var found := hud.get_node_or_null(node[0] as String) as Control
		assert_object(found).override_failure_message(node[0] as String).is_not_null()
		assert_str(found.get_class()).override_failure_message(node[0] as String).is_equal(node[1])
		assert_str(found.theme_type_variation).is_equal(node[2])
	assert_array(_names(hud)).is_equal(["Cross", "Status", "Players", "Bottom"])
	assert_array(_names(hud.rows)).is_equal(["HostRow", "Row2", "OwnRow", "Row4"])
	assert_array(_names(hud.bottom)).is_equal(["VoiceHint", "ReadyChip", "Mic"])
	# Texts: the deck's keys; data never translated (#208).
	assert_str(_label(hud, "Players/V/Info/CodeRow/Label").text).is_equal("common.code")
	assert_str(hud.ready_label.text).is_equal("lobby.ready_no")
	var own := _label(hud, "Players/V/List/Rows/OwnRow/Name")
	assert_str(own.text).is_equal("player.you")
	assert_int(own.auto_translate_mode).is_not_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	var data: Array[Label] = [
		hud.status_label, hud.lobby_name_label, hud.code_label, hud.head_label
	]
	for path: String in ["HostRow", "Row2", "Row4"]:
		data.append(_label(hud, "Players/V/List/Rows/%s/Name" % path))
	for label: Label in data:
		assert_int(label.auto_translate_mode).override_failure_message(label.name).is_equal(
			Node.AUTO_TRANSLATE_MODE_DISABLED
		)
	assert_str(hud.status_label.text).is_equal("3 of 4 ready")
	assert_str(hud.lobby_name_label.text).is_equal("Olena's lobby")
	assert_str(hud.code_label.text).is_equal(CODE)
	assert_str(hud.head_label.text).is_equal("Players 4 / 10")
	assert_array(hud.row_texts()).is_equal(
		PackedStringArray(["Olena · host", "Taras", "You", "Marko"])
	)
	assert_array(hud.row_checks()).is_equal([true, true, false, true])


func test_anchors_offsets_grow_sizes_and_flags_are_the_handoffs() -> void:
	var hud := await _hud()
	var both := Control.GROW_DIRECTION_BOTH
	var begin := Control.GROW_DIRECTION_BEGIN
	var end := Control.GROW_DIRECTION_END
	# [node, anchors (left, top, right, bottom), offsets, grow h, grow v]
	var placed: Array[Array] = [
		[hud.cross, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 0, 0, 0), both, both],
		[hud.status, Vector4(0.5, 0, 0.5, 0), Vector4(0, 40, 0, 40), both, end],
		[hud.players, Vector4(1, 0, 1, 0), Vector4(-40, 40, -40, 40), begin, end],
		[hud.bottom, Vector4(0, 1, 0, 1), Vector4(40, -40, 40, -40), end, begin],
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
	assert_vector(hud.cross.custom_minimum_size).is_equal(Vector2(8, 8))
	assert_vector(hud.players.custom_minimum_size).is_equal(Vector2(400, 0))
	assert_vector(hud.code_key.custom_minimum_size).is_equal(Vector2(36, 0))
	assert_vector(hud.mic.custom_minimum_size).is_equal(Vector2(46, 46))
	assert_vector(hud.mic_icon.custom_minimum_size).is_equal(Vector2(28, 28))
	var shrink_center := Control.SIZE_SHRINK_CENTER
	var caption := hud.get_node("Players/V/Info/CodeRow/Label") as Control
	assert_int(caption.size_flags_vertical).is_equal(shrink_center)
	assert_int(hud.code_key.size_flags_vertical).is_equal(shrink_center)
	assert_int(hud.code_label.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_int(hud.status_label.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_int(hud.ready_chip.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_int(hud.mic.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_int(hud.mic_icon.size_flags_horizontal).is_equal(shrink_center)
	assert_int(hud.mic_icon.size_flags_vertical).is_equal(shrink_center)
	for line: Node in hud.rows.get_children():
		var name_label := line.get_node("Name") as Label
		var check := line.get_node("Ready") as TextureRect
		assert_int(name_label.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
		assert_int(check.size_flags_vertical).is_equal(shrink_center)
		assert_vector(check.custom_minimum_size).is_equal(Vector2(24, 24))
		assert_int(check.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
		assert_int(check.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		assert_object(check.texture).is_same(ToyIcons.texture(&"check"))
	assert_int(hud.mic_icon.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(hud.mic_icon.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)


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
	var cut: Array[Label] = [hud.lobby_name_label]
	for line: Node in hud.rows.get_children():
		cut.append(line.get_node("Name") as Label)
	for label: Label in cut:
		assert_bool(label.clip_text).override_failure_message(label.name).is_true()
		assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	# A long name stays inside the 400 px plate.
	var model := _lobby(3, ["Olena", "Taras", "Ivan", "Marko"])
	model.roster[2].name = "Taras".repeat(12)
	model.lobby_name = "A very long lobby name".repeat(4)
	hud.refresh(model, _mode, NOW)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(hud.players.size.x).is_equal(400.0)


func test_the_icons_take_their_tints() -> void:
	var hud := await _hud()
	await get_tree().process_frame
	var ink := GameUi.THEME.get_color(&"font_color", &"ToyTextOnDark")
	for line: Node in hud.rows.get_children():
		assert_object((line.get_node("Ready") as TextureRect).self_modulate).is_equal(ink)
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


func test_count_lights_the_chip_and_titles_the_countdown() -> void:
	var hud := await _hud()
	var model := _lobby(3, ["Olena", "Taras", "Ivan", "Marko"], true)
	model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": NOW + 5 * Ticks.RATE})
	hud.refresh(model, _mode, NOW)
	assert_str(hud.status_label.theme_type_variation).is_equal(&"ToyTitleOnDark")
	assert_str(hud.status_label.text).is_equal("Starting in 5")
	assert_str(hud.ready_chip.theme_type_variation).is_equal(&"ToyChipLight")
	assert_str(hud.ready_label.theme_type_variation).is_equal(&"ToyChipLightText")
	assert_str(hud.ready_label.text).is_equal("lobby.ready_yes")
	assert_array(hud.row_checks()).is_equal([true, true, true, true])
	# An un-ready stops it: back to the plate's text and the plain chip.
	model.fold(&"ReadyChanged", {"peer": 3, "ready": false})
	model.fold(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	hud.refresh(model, _mode, NOW)
	assert_str(hud.status_label.theme_type_variation).is_equal(&"ToyPlateText")
	assert_str(hud.ready_chip.theme_type_variation).is_equal(&"ToyChipPlate")
	assert_str(hud.ready_label.text).is_equal("lobby.ready_no")


func test_short_code_waiting_direct_and_a_gone_code() -> void:
	var hud := await _hud()
	# The host's players_few (#548): one more of the four the handoff's sample needs.
	hud.refresh(_short(_lobby(3, ["Olena", "Taras", "Ivan"]), 1), _mode, NOW)
	assert_str(hud.status_label.text).is_equal("1 more player to start")
	assert_str(hud.head_label.text).is_equal("Players 3 / 10")
	assert_array(_names(hud.rows)).is_equal(["HostRow", "Row2", "OwnRow"])
	# code-waiting: the host alone, its row `player.you` with no check, the code "…".
	hud.refresh(_short(_lobby(1, ["Olena"]), 3), _mode, NOW)
	hud.show_code("", false, true)
	assert_str(hud.status_label.text).is_equal("3 more players to start")
	assert_array(_names(hud.rows)).is_equal(["HostRow"])
	assert_array(hud.row_texts()).is_equal(PackedStringArray(["You"]))
	assert_array(hud.row_checks()).is_equal([false])
	assert_bool(hud.code_row.visible).is_true()
	assert_str(hud.code_label.text).is_equal(LobbyHud.CODE_WAITING)
	# The service gone: "—" (the Esc Lobby tab explains it).
	hud.show_code("", true, true)
	assert_str(hud.code_label.text).is_equal(LobbyHud.CODE_GONE)
	hud.show_code(CODE, true, false)
	assert_str(hud.code_label.text).is_equal(LobbyHud.CODE_GONE)
	# direct: no code row.
	hud.show_code("", false, false)
	assert_bool(hud.code_row.visible).is_false()


func test_the_rows_are_built_again_only_when_they_change() -> void:
	var hud := await _hud()
	var model := _lobby(3, ["Olena", "Taras", "Ivan", "Marko"])
	var first := hud.rows.get_child(1)
	hud.refresh(model, _mode, NOW + 7)
	assert_object(hud.rows.get_child(1)).is_same(first)
	model.roster[2].name = "Taras K"
	hud.refresh(model, _mode, NOW)
	assert_array(hud.row_texts()).is_equal(
		PackedStringArray(["Olena · host", "Taras K", "You", "Marko"])
	)
	model.fold(&"PlayerLeft", {"peer": 4})
	hud.refresh(model, _mode, NOW)
	assert_array(_names(hud.rows)).is_equal(["HostRow", "Row2", "OwnRow"])
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
	assert_str(hud.lobby_name_label.text).is_equal("Лобі: Olena")
	assert_str(hud.head_label.text).is_equal("Гравці 4 / 10")
	assert_array(hud.row_texts()).is_equal(
		PackedStringArray(["Olena · хост", "Taras", "Ти", "Marko"])
	)


func test_large_text_widens_the_code_key_and_back() -> void:
	var hud := await _hud()
	var holder := hud.get_parent() as Control
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(hud.code_key.custom_minimum_size).is_equal(Vector2(42, 0))
	assert_vector(hud.players.custom_minimum_size).is_equal(Vector2(400, 0))
	holder.theme = GameUi.THEME
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(hud.code_key.custom_minimum_size).is_equal(Vector2(36, 0))


func test_the_voice_hint_shows_only_with_a_text() -> void:
	var hud := await _hud()
	assert_bool(hud.voice_hint.visible).is_false()
	hud.show_voice_hint(VoicePanel.LOBBY_HINT)
	assert_bool(hud.voice_hint.visible).is_true()
	hud.show_voice_hint("")
	assert_bool(hud.voice_hint.visible).is_false()


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
	welcome.map = "res://levels/greybox/greybox.tscn"
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
	hud.show_code(CODE, false, false)
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
