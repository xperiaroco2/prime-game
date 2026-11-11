extends GdUnitTestSuite
## The round HUD's Controls (client/ui/Hud, HudSlot and ToyPips, #489, #1570; ARCHITECTURE
## §4.7.37) under the shared theme: the UI handoff's tree node for node (prime-game-ui `ui-2.5.4`
## `docs/handoff/s07-hud.md`: names, classes, variations, anchors, offsets, grow directions, size
## flags and minimum sizes), every node ignoring the mouse and focus, and each state the handoff
## draws: empty, carry, human, hurt, raising and cops (the human state's name plate:
## name_plate_test.gd), large text; and s09's: the downed see the mic alone, the dead nothing
## (#497). The roster and the cops' minute: hud_roster_test.gd.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_the_tree_is_the_handoffs_node_for_node() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"human"))
	# [path, class, variation] of every node the handoff lists (the human state: the roster's
	# tags; the anger meter shown by a test value).
	var nodes: Array[Array] = [
		["Role", "PanelContainer", &"ToyStickerAlert"],
		["Role/Text", "Label", &"ToyStickerText"],
		["Time", "PanelContainer", &"ToyPlate"],
		["Time/Row", "HBoxContainer", &"ToyRowTwentyFour"],
		["Time/Row/Timer", "Label", &"ToyTimer"],
		["Time/Row/Divider", "Panel", &"ToyTileDivider"],
		["Time/Row/AngerColumn", "VBoxContainer", &"ToyColumnFour"],
		["Time/Row/AngerColumn/Caption", "Label", &"ToyHudCaption"],
		["Time/Row/AngerColumn/Anger", "HBoxContainer", &"ToyRowEight"],
		["Time/Row/AngerColumn/Anger/Bar", "ProgressBar", &"ToyBarAngerCalm"],
		["Time/Row/AngerColumn/Anger/Siren", "TextureRect", &""],
		["Roster", "PanelContainer", &"ToyRoster"],
		["Roster/Rows", "VBoxContainer", &"ToyColumnEight"],
		["Roster/Rows/Row1", "HBoxContainer", &"ToyRowTwelve"],
		["Roster/Rows/Row1/Dot", "Panel", &"ToyRosterDot"],
		["Roster/Rows/Row1/Name", "Label", &"ToyRosterNameSelf"],
		["Roster/Rows/Row1/Tag", "PanelContainer", &"ToyRosterTag"],
		["Roster/Rows/Row1/Tag/Text", "Label", &"ToyRosterTagText"],
		["Roster/Rows/Row2/Name", "Label", &"ToyRosterName"],
		["Roster/Rows/Row3/Name", "Label", &"ToyRosterNameDead"],
		["Cross", "Panel", &"ToyCrosshair"],
		["Aim", "PanelContainer", &"ToyChipPlate"],
		["Aim/Text", "Label", &"ToyChipPlateText"],
		["Notice", "PanelContainer", &"ToyChipPlate"],
		["Notice/Text", "Label", &"ToyChipPlateText"],
		["Vitals", "HBoxContainer", &"ToyRowTwentyFour"],
		["Vitals/Suit", "PanelContainer", &"ToyPlate"],
		["Vitals/Suit/Rows", "VBoxContainer", &"ToyColumnEight"],
		["Vitals/Suit/Rows/Title", "Label", &"ToyKicker"],
		["Vitals/Suit/Rows/Health", "HBoxContainer", &"ToyRowSixteen"],
		["Vitals/Suit/Rows/Health/Label", "Label", &"ToyHudCaption"],
		["Vitals/Suit/Rows/Health/Pips", "HBoxContainer", &"ToyRowFour"],
		["Vitals/Suit/Rows/Health/Pips/P1", "Panel", &"ToyPipHealth"],
		["Vitals/Suit/Rows/Health/Pips/P8", "Panel", &"ToyPipHealth"],
		["Vitals/Suit/Rows/Health/Pips/P9", "Panel", &"ToyPip"],
		["Vitals/Suit/Rows/Health/Pips/P10", "Panel", &"ToyPip"],
		["Vitals/Suit/Rows/Stamina", "HBoxContainer", &"ToyRowSixteen"],
		["Vitals/Suit/Rows/Stamina/Label", "Label", &"ToyHudCaption"],
		["Vitals/Suit/Rows/Stamina/Pips", "HBoxContainer", &"ToyRowFour"],
		["Vitals/Suit/Rows/Stamina/Pips/P9", "Panel", &"ToyPipStamina"],
		["Vitals/Suit/Rows/Stamina/Pips/P10", "Panel", &"ToyPip"],
		["Vitals/Mic", "PanelContainer", &"ToyMic"],
		["Vitals/Mic/Icon", "TextureRect", &""],
		["Vitals/Others", "PanelContainer", &"ToyChipPlate"],
		["Vitals/Others/Text", "Label", &"ToyChipPlateText"],
		["Slots", "HBoxContainer", &"ToyRowSixteen"],
		["Slots/Place1", "PanelContainer", &"ToySlotHand"],
		["Slots/Place1/V", "VBoxContainer", &"ToyColumnFour"],
		["Slots/Place1/V/Head", "Label", &"ToyKicker"],
		["Slots/Place1/V/Picture", "TextureRect", &""],
		["Slots/Place1/V/Name", "Label", &"ToySlotTagText"],
		["Slots/Place1/Number", "Label", &"ToySlotTextEmpty"],
		["Slots/Place2", "PanelContainer", &"ToySlotBelt"],
		["Slots/Place2/V/Head", "Label", &"ToyKicker"],
		["Slots/Place3", "PanelContainer", &"ToySlotBelt"],
		["Slots/Place3/Number", "Label", &"ToySlotTextEmpty"],
		["Raising", "PanelContainer", &"ToyPlate"],
		["Raising/Bar", "ProgressBar", &"ToyBarProgress"],
		["Edge", "Panel", &"ToyScreenEdgeAlert"],
		["Cops", "PanelContainer", &"ToyPlateBanner"],
		["Cops/V", "VBoxContainer", &"ToyColumnFour"],
		["Cops/V/Title", "Label", &"ToyPlateAlertTitle"],
		["Cops/V/In", "Label", &"ToyPlateAlertText"],
		["Cops/V/Count", "Label", &"ToyPlateAlertCountdown"],
	]
	for node: Array in nodes:
		var found := hud.get_node_or_null(node[0] as String) as Control
		assert_object(found).override_failure_message(node[0] as String).is_not_null()
		assert_str(found.get_class()).override_failure_message(node[0] as String).is_equal(node[1])
		assert_str(found.theme_type_variation).override_failure_message(node[0] as String).is_equal(
			node[2]
		)
	assert_int(hud.health.get_child_count()).is_equal(10)
	assert_array(hud.slots.get_children()).is_equal(hud.places)
	# The edge lies under every tile: the HUD's first child.
	assert_object(hud.get_child(0)).is_same(hud.edge)
	# The places by number (GDD §6), the first in the hand, lit, until an event selects another.
	(
		assert_array(hud.places.map(func(slot: HudSlot) -> String: return slot.number_label.text))
		. is_equal(["1", "2", "3"])
	)
	assert_object(hud.hand).is_same(hud.places[0])
	# Texts: the deck's keys; the kickers uppercase (the game sets it); data never translated.
	assert_str(_label(hud, "Vitals/Suit/Rows/Title").text).is_equal("hud.suit")
	assert_bool(_label(hud, "Vitals/Suit/Rows/Title").uppercase).is_true()
	assert_str(_label(hud, "Vitals/Suit/Rows/Health/Label").text).is_equal("hud.health")
	assert_str(_label(hud, "Vitals/Suit/Rows/Stamina/Label").text).is_equal("hud.stamina")
	assert_str(_label(hud, "Time/Row/AngerColumn/Caption").text).is_equal("hud.anger")
	assert_str(_label(hud, "Slots/Place1/V/Head").text).is_equal("hud.slot.hand")
	assert_bool(_label(hud, "Slots/Place1/V/Head").uppercase).is_true()
	assert_str(_label(hud, "Slots/Place2/V/Head").text).is_equal("hud.slot.belt")
	assert_str(_label(hud, "Cops/V/Title").text).is_equal("hud.cops.title")
	assert_str(_label(hud, "Cops/V/In").text).is_equal("hud.cops.in")
	assert_bool(_label(hud, "Roster/Rows/Row1/Tag/Text").uppercase).is_true()
	for data: Label in [hud.time_label, hud.cops_count, _label(hud, "Roster/Rows/Row2/Name")]:
		assert_int(data.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_anchors_offsets_grow_and_sizes_are_the_handoffs() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"human"))
	await get_tree().process_frame
	var both := Control.GROW_DIRECTION_BOTH
	var begin := Control.GROW_DIRECTION_BEGIN
	var end := Control.GROW_DIRECTION_END
	# [node, anchors (left, top, right, bottom), offsets, grow h, grow v]
	var placed: Array[Array] = [
		[hud.role, Vector4(0, 0, 0, 0), Vector4(39, 39, 39, 39), end, end],
		[hud.timer, Vector4(0.5, 0, 0.5, 0), Vector4(0, 36, 0, 36), both, end],
		[hud.roster, Vector4(1, 0, 1, 0), Vector4(-39, 39, -39, 39), begin, end],
		[hud.cross, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 0, 0, 0), both, both],
		[hud.aim, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 64, 0, 64), both, both],
		[hud.raising, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 64, 0, 64), both, both],
		[hud.vitals, Vector4(0, 1, 0, 1), Vector4(39, -39, 39, -39), end, begin],
		[hud.slots, Vector4(1, 1, 1, 1), Vector4(-36, -36, -36, -36), begin, begin],
		[hud.edge, Vector4(0, 0, 1, 1), Vector4(0, 0, 0, 0), end, end],
		[hud.cops, Vector4(0.5, 0, 0.5, 0), Vector4(0, 168, 0, 168), both, end],
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
		if node != hud.edge:
			assert_int(node.grow_horizontal).override_failure_message(node.name).is_equal(row[3])
			assert_int(node.grow_vertical).override_failure_message(node.name).is_equal(row[4])
	# The handoff's 120 px at least, wider when the theme's widest m:ss needs it (Unbounded).
	assert_float(hud.time_label.custom_minimum_size.x).is_greater_equal(120.0)
	assert_vector(hud.divider.custom_minimum_size).is_equal(Vector2(3, 48))
	assert_vector(hud.anger_bar.custom_minimum_size).is_equal(Vector2(240, 16))
	assert_vector(hud.siren.custom_minimum_size).is_equal(Vector2(36, 36))
	assert_vector(hud.roster.custom_minimum_size).is_equal(Vector2(276, 0))
	var dot := hud.roster_row(0).get_node(^"Dot") as Control
	assert_vector(dot.custom_minimum_size).is_equal(Vector2(15, 15))
	assert_vector(hud.cross.custom_minimum_size).is_equal(Vector2(12, 12))
	assert_vector(_label(hud, "Vitals/Suit/Rows/Health/Label").custom_minimum_size).is_equal(
		Vector2(150, 0)
	)
	for pip: Panel in hud.health.pips + hud.stamina.pips:
		assert_vector(pip.custom_minimum_size).override_failure_message(pip.name).is_equal(
			Vector2(23, 15)
		)
	assert_vector(hud.mic.custom_minimum_size).is_equal(Vector2(75, 75))
	assert_vector(hud.mic_icon.custom_minimum_size).is_equal(Vector2(42, 42))
	for place: HudSlot in hud.places:
		assert_vector(place.custom_minimum_size).is_equal(Vector2(117, 132))
		assert_vector(place.picture.custom_minimum_size).is_equal(Vector2(57, 57))
		assert_int(place.size_flags_vertical).is_equal(Control.SIZE_SHRINK_END)
	assert_vector(hud.raising_bar.custom_minimum_size).is_equal(Vector2(360, 24))
	for shrunk: Control in [hud.suit, hud.mic]:
		assert_int(shrunk.size_flags_vertical).is_equal(Control.SIZE_SHRINK_END)
	for centred: Control in [hud.time_label, hud.divider, hud.anger_column, hud.anger_bar]:
		assert_int(centred.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_int(hud.mic_icon.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	# The time's tile is as wide for "44:44" as for "11:11": its 120 px hold the widest time.
	hud.time_label.text = "11:11"
	var narrow := hud.timer.get_combined_minimum_size().x
	hud.time_label.text = "44:44"
	assert_float(hud.timer.get_combined_minimum_size().x).is_equal(narrow)


func test_no_node_takes_the_mouse_or_focus() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"human"))
	hud.show_hud(_state(&"cops"))
	var all: Array[Node] = hud.find_children("*", "Control", true, false)
	all.append(hud)
	for node: Node in all:
		var control := node as Control
		assert_int(control.mouse_filter).override_failure_message(str(control.get_path())).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).is_equal(Control.FOCUS_NONE)


func test_the_pips_are_round_value_x_ten_and_health_alarms_under_thirty_percent() -> void:
	# The handoff: round(value x 10) full pips; health under its alarm line (30 %) ToyPipAlarm with
	# its label ToyTextAlertOnLight; stamina never alarms.
	var hud := await _hud()
	for row: Array in [
		[0.22, 2, &"ToyPipAlarm"],
		[0.29, 3, &"ToyPipAlarm"],
		[0.3, 3, &"ToyPipHealth"],
		[0.8, 8, &"ToyPipHealth"],
		[1.0, 10, &"ToyPipHealth"],
		[0.0, 0, &"ToyPipAlarm"],
	]:
		var shown := _state(&"empty")
		shown.health = row[0]
		shown.stamina = row[0]
		hud.show_hud(shown)
		var full: int = row[1]
		assert_int(hud.health.full_count()).override_failure_message(str(row[0])).is_equal(full)
		assert_int(hud.stamina.full_count()).is_equal(full)
		for index in ToyPips.COUNT:
			var expected: StringName = row[2] if index < full else ToyPips.EMPTY
			assert_str(hud.health.pips[index].theme_type_variation).is_equal(expected)
			var stamina_look := ToyPips.STAMINA if index < full else ToyPips.EMPTY
			assert_str(hud.stamina.pips[index].theme_type_variation).is_equal(stamina_look)
		var caption := _label(hud, "Vitals/Suit/Rows/Health/Label")
		var alarmed: bool = row[2] == &"ToyPipAlarm"
		assert_str(caption.theme_type_variation).is_equal(
			&"ToyTextAlertOnLight" if alarmed else &"ToyHudCaption"
		)
		assert_str(_label(hud, "Vitals/Suit/Rows/Stamina/Label").theme_type_variation).is_equal(
			&"ToyHudCaption"
		)


func test_empty_shows_the_empty_pictures_and_aim() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"empty"))
	assert_bool(hud.timer.visible).is_true()
	assert_bool(hud.time_label.visible).is_true()
	assert_str(hud.time_label.text).is_equal("07:22")
	assert_str(hud.role_label.text).is_equal("role.engineer")
	assert_str(hud.role.theme_type_variation).is_equal(&"ToySticker")
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal("item.package")
	assert_bool(hud.raising.visible).is_false()
	assert_bool(hud.edge.visible or hud.cops.visible).is_false()
	assert_object(hud.hand.picture.texture).is_same(ToyIcons.texture(&"slot-empty-hand"))
	assert_object(hud.belt.picture.texture).is_same(ToyIcons.texture(&"slot-empty-belt"))
	for slot: HudSlot in hud.places:
		assert_bool(slot.picture.visible).is_true()
		assert_bool(slot.name_label.visible).is_false()
		assert_str(slot.shown_item()).is_empty()
	assert_object(hud.belt.picture.self_modulate).is_equal(
		GameUi.THEME.get_color(&"font_color", &"ToyTextOnDark")
	)
	assert_int(hud.health.full_count()).is_equal(8)
	assert_int(hud.stamina.full_count()).is_equal(9)
	# The mic on: `mic` tinted icon_on (never no glyph at all).
	assert_object(hud.mic_icon.texture).is_same(ToyIcons.texture(&"mic"))
	assert_object(hud.mic_icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"icon_on", &"ToyMic")
	)


func test_carry_shows_each_items_icon_and_name_in_its_tile() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"carry"))
	await get_tree().process_frame
	assert_bool(hud.aim.visible).is_false()
	var hand := hud.hand
	assert_object(hand.picture.texture).is_same(ToyIcons.texture(&"item-rocket"))
	assert_object(hand.picture.self_modulate).is_equal(
		GameUi.THEME.get_color(&"font_color", &"ToySlotText")
	)
	assert_bool(hand.name_label.visible).is_true()
	assert_str(hand.shown_item()).is_equal("item.fireworks")
	assert_object(hud.belt.picture.texture).is_same(ToyIcons.texture(&"item-bun"))
	assert_str(hud.belt.shown_item()).is_equal("item.bun")
	# A two-handed item keeps the tile's size (the handoff draws no wide hand).
	assert_vector(hand.custom_minimum_size).is_equal(Vector2(117, 132))
	assert_float(hand.size.x).is_equal(117.0)
	# A kind with no pack icon shows its name alone.
	var shown := _state(&"carry")
	shown.hand = _slot("item.gnome", &"", false)
	hud.show_hud(shown)
	assert_bool(hud.hand.picture.visible).is_false()
	assert_str(hud.hand.shown_item()).is_equal("item.gnome")


func test_an_items_name_wraps_onto_two_lines_inside_the_tile() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"carry"))
	await get_tree().process_frame
	var hand := hud.hand
	var label := hand.name_label
	var inner := 117.0 - hand.get_theme_stylebox(&"panel").get_minimum_size().x
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_int(label.max_lines_visible).is_equal(2)
	assert_bool(label.clip_text).is_true()
	assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	# A name that fits: one line, one line's height.
	await _show_item(hand, "Bun")
	assert_int(label.get_line_count()).is_equal(1)
	var one_line := label.get_combined_minimum_size().y
	assert_int(one_line as int).is_equal(label.get_line_height())
	var two_lines: float = 2.0 * one_line + label.get_theme_constant(&"line_spacing")
	# Delivery D2's names (#1017): whole, on two lines, in the tile's unchanged width.
	for name_text: String in ["Garden gnome", "Моторна олива", "Садовий гном"]:
		await _show_item(hand, name_text)
		assert_int(label.get_line_count()).override_failure_message(name_text).is_equal(2)
		assert_float(label.size.x).override_failure_message(name_text).is_equal(inner)
		assert_float(label.size.y).override_failure_message(name_text).is_equal(two_lines)
		assert_float(hand.size.x).override_failure_message(name_text).is_equal(117.0)
	# More than two lines' worth: the label is two lines tall, the tile as wide as before.
	await _show_item(hand, "Garden gnome with a very long hat")
	assert_float(label.size.y).is_equal(two_lines)
	assert_float(hand.size.x).is_equal(117.0)
	await _show_item(hand, "Bun")
	assert_float(label.size.y).is_equal(one_line)


func test_human_takes_the_danger_tile() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"human"))
	assert_str(hud.role_label.text).is_equal("role.dissident")
	assert_str(hud.role.theme_type_variation).is_equal(&"ToyStickerAlert")
	assert_bool(hud.aim.visible).is_false()
	assert_object(hud.hand.picture.texture).is_same(ToyIcons.texture(&"item-battery"))
	# The map hides the tile at once (#491) and gives it back.
	hud.role_hidden = true
	assert_bool(hud.role.visible).is_false()
	hud.role_hidden = false
	assert_bool(hud.role.visible).is_true()


func test_the_timer_holds_every_time_without_changing_width() -> void:
	# _fit_timer measures "dd:dd" through the label itself (#489): every m:ss fits the width it
	# sets, so the centred tile never moves with the time; the shown time is kept.
	var hud := await _hud()
	var shown := HudText.Shown.new()
	shown.time = "07:22"
	hud.show_hud(shown)
	await get_tree().process_frame
	var width := hud.time_label.custom_minimum_size.x
	var probe: Label = auto_free(UiParts.styled_label("", &"ToyTimer"))
	hud.add_child(probe)
	for digit in 10:
		probe.text = "%d%d:%d%d" % [digit, digit, digit, digit]
		await get_tree().process_frame
		assert_float(probe.get_minimum_size().x).override_failure_message(probe.text).is_less_equal(
			width
		)
	assert_str(hud.time_label.text).is_equal("07:22")


func test_the_halls_others_chip_names_the_other_dead_beside_the_mic() -> void:
	# s09's dead-room: Vitals shows the mic and "Also here: …" beside it, the suit hidden.
	TranslationServer.set_locale(Languages.ENGLISH)
	var hud := await _hud()
	assert_bool(hud.others.visible).is_false()
	var shown := HudText.Shown.new()
	shown.vitals = true
	shown.mic = true
	shown.others = PackedStringArray(["Bulk", "Zinga"])
	hud.show_hud(shown)
	assert_bool(hud.others.visible).is_true()
	assert_bool(hud.suit.visible).is_false()
	assert_bool(hud.mic.visible).is_true()
	assert_int(hud.others.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_str(hud.others_label.text).is_equal("Also here: Bulk, Zinga")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_str(hud.others_label.text).is_equal("Тут також: Bulk, Zinga")
	TranslationServer.set_locale(Languages.ENGLISH)
	shown.others = PackedStringArray()
	hud.show_hud(shown)
	assert_bool(hud.others.visible).is_false()


func test_the_zap_notice_shows_only_with_its_text() -> void:
	var hud := await _hud()
	assert_bool(hud.notice.visible).is_false()
	var shown := HudText.Shown.new()
	shown.notice = "words"
	hud.show_hud(shown)
	assert_bool(hud.notice.visible).is_true()
	assert_str(hud.notice_label.text).is_equal("words")
	hud.show_hud(HudText.Shown.new())
	assert_bool(hud.notice.visible).is_false()


func test_raising_replaces_aim_and_the_map_hides_the_middle() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"raising"))
	assert_bool(hud.aim.visible).is_false()
	assert_bool(hud.raising.visible).is_true()
	assert_float(hud.raising_bar.value).is_equal(0.6)
	assert_bool(hud.raising_bar.show_percentage).is_false()
	hud.aiming = false
	assert_bool(hud.cross.visible or hud.aim.visible or hud.raising.visible).is_false()
	hud.aiming = true
	hud.show_hud(_state(&"empty"))
	assert_bool(hud.raising.visible).is_false()
	assert_bool(hud.aim.visible).is_true()


func test_the_raise_cue_takes_aims_place_in_the_decks_words_with_the_key() -> void:
	# The rescuer's cue (#497, the engineer on PR #721): `tutorial.step.downed.how` with the raise
	# key's label, set in code and written again on a language switch; the own raise replaces it.
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var hud := await _hud()
	var cue := _state(&"cue")
	hud.show_hud(cue)
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal("Hold E next to them")
	assert_int(hud.aim_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	TranslationServer.set_locale("uk")
	hud.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(hud.aim_label.text).is_equal("Утримуй E поруч")
	cue.raising = 0.6
	hud.show_hud(cue)
	assert_bool(hud.aim.visible).is_false()
	assert_bool(hud.raising.visible).is_true()
	# An item's name again: its deck key, translated by the label.
	hud.show_hud(_state(&"empty"))
	assert_str(hud.aim_label.text).is_equal("item.package")
	assert_int(hud.aim_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_INHERIT)
	TranslationServer.set_locale(locale)


func test_the_hand_over_cue_takes_aims_place_with_the_interact_key() -> void:
	# #1411: HudText.HAND_OVER_CUE with the key's label, set in code, written again on a switch.
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var hud := await _hud()
	var cue := _state(&"empty")
	cue.aim = ""
	cue.hand_over_key = "E"
	hud.show_hud(cue)
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal("Press E to hand it over")
	assert_int(hud.aim_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	TranslationServer.set_locale("uk")
	hud.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(hud.aim_label.text).is_equal("Натисни E, щоб передати")
	cue.hand_over_key = ""
	hud.show_hud(cue)
	assert_bool(hud.aim.visible).is_false()
	TranslationServer.set_locale(locale)


func test_the_sit_cue_takes_aims_place_and_shows_its_raw_key_until_the_deck_has_the_row() -> void:
	# #1420: HudText.SIT_CUE with the key's label, set in code. The deck row comes with the UI
	# track; until then the translation of an unknown key is the key itself, and this pins it.
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var hud := await _hud()
	var cue := _state(&"empty")
	cue.aim = ""
	cue.sit_key = "E"
	hud.show_hud(cue)
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal(HudText.SIT_CUE)
	assert_int(hud.aim_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	cue.sit_key = ""
	hud.show_hud(cue)
	assert_bool(hud.aim.visible).is_false()
	TranslationServer.set_locale(locale)


func test_the_mic_off_is_mic_off_tinted_icon_off() -> void:
	var hud := await _hud()
	var shown := _state(&"empty")
	shown.mic = false
	hud.show_hud(shown)
	assert_bool(hud.shows_mic_on()).is_false()
	assert_object(hud.mic_icon.texture).is_same(ToyIcons.texture(&"mic-off"))
	assert_object(hud.mic_icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"icon_off", &"ToyMic")
	)


func test_the_downed_see_the_mic_alone_and_a_spectator_nothing() -> void:
	# The handoff s09 (#497): `down` keeps Vitals/Mic (off) only; `dead` in the round's hall
	# (#1489, `dead-room`) keeps Vitals/Mic only, the suit hidden; a dead spectator (a phase with no
	# hall) sees nothing of the HUD.
	var hud := await _hud()
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	model.fold(&"KnockedDown", {"peer": model.own_peer, "position": Vector3.ZERO})
	hud.show_hud(HudText.of(model, _mode, 100, HudText.Local.new()))
	assert_bool(hud.mic.is_visible_in_tree()).is_true()
	assert_bool(hud.shows_mic_on()).is_false()
	var downed_hidden: Array[Control] = [
		hud.timer, hud.role, hud.roster, hud.suit, hud.slots, hud.aim, hud.raising, hud.cops
	]
	for hidden: Control in downed_hidden:
		assert_bool(hidden.is_visible_in_tree()).override_failure_message(hidden.name).is_false()
	model.fold(&"Died", {"peer": model.own_peer, "position": Vector3.ZERO})
	assert_bool(model.waits_in_hall()).is_true()
	hud.show_hud(HudText.of(model, _mode, 100, HudText.Local.new()))
	assert_bool(hud.mic.is_visible_in_tree()).is_true()
	var hall_hidden: Array[Control] = [
		hud.timer, hud.role, hud.roster, hud.suit, hud.slots, hud.aim, hud.raising, hud.others
	]
	for hidden: Control in hall_hidden:
		assert_bool(hidden.is_visible_in_tree()).override_failure_message(hidden.name).is_false()
	# A round whose dead walk no hall: they spectate and see nothing of the HUD.
	var spectator := Preview.fake_model(FixtureCombatModes.respawning(), true)
	Preview.fold_round(spectator)
	spectator.fold(&"Died", {"peer": spectator.own_peer, "position": Vector3.ZERO})
	assert_bool(spectator.waits_in_hall()).is_false()
	hud.show_hud(HudText.of(spectator, _mode, 100, HudText.Local.new()))
	var dead_hidden: Array[Control] = [
		hud.timer, hud.role, hud.roster, hud.vitals, hud.slots, hud.aim, hud.raising
	]
	for hidden: Control in dead_hidden:
		assert_bool(hidden.is_visible_in_tree()).override_failure_message(hidden.name).is_false()


func test_large_text_keeps_the_sizes_and_shrinks_back() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"carry"))
	var holder := hud.get_parent() as Control
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(hud.hand.custom_minimum_size).is_equal(Vector2(117, 132))
	assert_vector(hud.mic.custom_minimum_size).is_equal(Vector2(75, 75))
	assert_vector(hud.health.pips[0].custom_minimum_size).is_equal(Vector2(23, 15))
	holder.theme = GameUi.THEME
	await get_tree().process_frame
	await get_tree().process_frame
	hud.show_hud(_state(&"empty"))
	await get_tree().process_frame
	# The slots' row shrinks back to its minimum and stays in the corner, 36 px in.
	assert_float(hud.slots.size.x).is_equal(hud.slots.get_combined_minimum_size().x)
	assert_float(hud.slots.get_rect().end.x).is_equal(holder.size.x - 36.0)


## GDD §6 (#1218): the selected place is the handoff's Hand tile (empty showing its empty hand),
## the others its Belt tile, and each keeps its number and its item.
func test_the_selected_place_is_lit_and_the_others_are_belt_places() -> void:
	var hud := await _hud()
	var shown := _state(&"empty")
	shown.places[1] = _slot("item.knife", &"item-knife", false)
	shown.selected = 2
	hud.show_hud(shown)
	var looks: Array = hud.places.map(
		func(slot: HudSlot) -> StringName: return slot.theme_type_variation
	)
	assert_array(looks).is_equal([&"ToySlotBelt", &"ToySlotBelt", &"ToySlotHand"])
	assert_object(hud.hand).is_same(hud.places[2])
	assert_str(hud.places[2].head.text).is_equal("hud.slot.hand")
	assert_object(hud.places[2].picture.texture).is_same(ToyIcons.texture(&"slot-empty-hand"))
	assert_str(hud.places[0].head.text).is_equal("hud.slot.belt")
	assert_object(hud.places[0].picture.texture).is_same(ToyIcons.texture(&"slot-empty-belt"))
	assert_object(hud.places[1].picture.texture).is_same(ToyIcons.texture(&"item-knife"))
	assert_str(hud.places[1].number_label.text).is_equal("2")
	assert_bool(hud.places[1].number_label.visible).is_true()
	# Back to the first place: the light moves with it.
	shown.selected = 0
	hud.show_hud(shown)
	assert_str(hud.places[0].theme_type_variation).is_equal(&"ToySlotHand")
	assert_str(hud.places[2].theme_type_variation).is_equal(&"ToySlotBelt")
	assert_str(hud.places[2].head.text).is_equal("hud.slot.belt")
	assert_object(hud.places[2].picture.texture).is_same(ToyIcons.texture(&"slot-empty-belt"))


## The handoff's states as HudText would show them (its samples: 07:22, health 0.8, stamina 0.9,
## the mic on, the crosshair on a package; carry: fireworks in the hand and a bun on the belt;
## human: the dissident's danger tile, a roster with its tags and a battery; cops: the minute).
static func _state(state: StringName) -> HudText.Shown:
	var shown := HudText.Shown.new()
	shown.time = "07:22"
	shown.role = "role.engineer"
	shown.vitals = true
	shown.bars = true
	shown.health = 0.8
	shown.stamina = 0.9
	shown.mic = true
	shown.slots = true
	shown.aim = "item.package"
	match state:
		&"carry":
			shown.aim = ""
			shown.hand = _slot("item.fireworks", &"item-rocket", true)
			shown.belt = _slot("item.bun", &"item-bun", false)
		&"hurt":
			shown.health = 0.22
			shown.stamina = 0.18
		&"human":
			shown.aim = ""
			shown.role = "role.dissident"
			shown.role_alert = true
			shown.anger = 0.55
			shown.siren = true
			shown.hand = _slot("item.battery", &"item-battery", false)
			shown.roster = [
				_row(1, "Bulk", true, false, "role.dissident"),
				_row(2, "Olena", false, false, ""),
				_row(3, "Taras", false, true, ""),
				_row(4, "Zinga", false, false, "role.dissident"),
			]
		&"raising":
			shown.raising = 0.6
		&"cue":
			shown.aim = ""
			shown.raise_key = "E"
		&"cops":
			shown.aim = ""
			shown.anger = 1.0
			shown.siren = true
			shown.cops = "0:58"
	return shown


static func _slot(item: String, icon: StringName, two_handed: bool) -> HudText.Slot:
	var slot := HudText.Slot.new()
	slot.item = item
	slot.icon = icon
	slot.two_handed = two_handed
	return slot


static func _row(peer: int, row_name: String, own: bool, dead: bool, tag: String) -> HudText.Row:
	var row := HudText.Row.new()
	row.peer = peer
	row.name = row_name
	row.colour = Color.from_hsv(peer / 8.0, 0.5, 0.8)
	row.own = own
	row.dead = dead
	row.tag = tag
	return row


static func _label(hud: Hud, path: String) -> Label:
	return hud.get_node(path) as Label


## A Hud under the shared theme at the 1920x1080 base, after its sizes were read.
func _hud() -> Hud:
	var holder: Control = auto_free(Control.new())
	holder.theme = GameUi.THEME
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	await get_tree().process_frame
	return hud


## Shows `item_name` in `hand` and lets the layout settle.
func _show_item(hand: HudSlot, item_name: String) -> void:
	var slot := HudText.Slot.new()
	slot.item = item_name
	slot.icon = &"item"
	slot.two_handed = true
	hand.show_slot(slot)
	await get_tree().process_frame
	await get_tree().process_frame
