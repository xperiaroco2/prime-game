extends GdUnitTestSuite
## The round HUD's Controls (client/ui/Hud and HudSlot, #489; ARCHITECTURE §4.7.36) under the
## shared theme: the UI handoff's tree node for node (prime-game-ui `ui-0.4.0`
## `docs/handoff/s07-hud.md`: names, classes, variations, anchors, offsets, grow directions, size
## flags and minimum sizes), every node ignoring the mouse and focus, the health fill's ramp stop
## (0.22, 0.8, 1.0), and each state the handoff draws: empty, pack, tired, hurt, mate, raising
## (the mate state's name plate: name_plate_test.gd), large text and a dead spectator's plate.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_the_tree_is_the_handoffs_node_for_node() -> void:
	var hud := await _hud()
	# [path, class, variation] of every node the handoff lists (Spectate: s09's, Watching only).
	var nodes: Array[Array] = [
		["Timer", "PanelContainer", &"ToyPlate"],
		["Timer/Time", "Label", &"ToyTimer"],
		["Role", "PanelContainer", &"ToyChipPlate"],
		["Role/Text", "Label", &"ToyChipPlateText"],
		["Cross", "Panel", &"ToyCrosshair"],
		["Aim", "PanelContainer", &"ToyChipPlate"],
		["Aim/Text", "Label", &"ToyChipPlateText"],
		["Vitals", "VBoxContainer", &"ToyColumnTwelve"],
		["Vitals/Health", "VBoxContainer", &"ToyColumnFour"],
		["Vitals/Health/Cap", "PanelContainer", &"ToyBarLabel"],
		["Vitals/Health/Cap/Text", "Label", &"ToyHudCaption"],
		["Vitals/Health/Track", "PanelContainer", &"ToyBarTrack"],
		["Vitals/Health/Track/Fill", "ProgressBar", &"ToyBarHealth"],
		["Vitals/Stamina", "VBoxContainer", &"ToyColumnFour"],
		["Vitals/Stamina/Cap", "PanelContainer", &"ToyBarLabel"],
		["Vitals/Stamina/Cap/Text", "Label", &"ToyHudCaption"],
		["Vitals/Stamina/Track", "PanelContainer", &"ToyBarTrack"],
		["Vitals/Stamina/Track/Fill", "ProgressBar", &"ToyBarStamina"],
		["Vitals/Mic", "PanelContainer", &"ToyMic"],
		["Vitals/Mic/Icon", "TextureRect", &""],
		["Slots", "HBoxContainer", &"ToyRowTwelve"],
		["Slots/Hand", "PanelContainer", &"ToySlotActive"],
		["Slots/Hand/Center", "CenterContainer", &""],
		["Slots/Hand/Center/Row", "HBoxContainer", &"ToyRowEight"],
		["Slots/Hand/Center/Row/Icon", "TextureRect", &""],
		["Slots/Hand/Center/Row/Name", "Label", &"ToySlotTextEmpty"],
		["Slots/Hand/Center/Row/ItemName", "Label", &"ToySlotText"],
		["Slots/Belt", "PanelContainer", &"ToySlot"],
		["Slots/Belt/Center/Row/Name", "Label", &"ToySlotTextEmpty"],
		["Raising", "PanelContainer", &"ToyPlate"],
		["Raising/Bar", "ProgressBar", &"ToyBarProgress"],
		["Spectate", "PanelContainer", &"ToyPlate"],
		["Spectate/V", "VBoxContainer", &"ToyColumnFour"],
		["Spectate/V/Watching", "Label", &"ToyTitleOnDark"],
	]
	for node: Array in nodes:
		var found := hud.get_node_or_null(node[0] as String) as Control
		assert_object(found).override_failure_message(node[0] as String).is_not_null()
		assert_str(found.get_class()).override_failure_message(node[0] as String).is_equal(node[1])
		assert_str(found.theme_type_variation).is_equal(node[2])
	assert_array(hud.slots.get_children()).is_equal([hud.hand, hud.belt])
	# Texts: the deck's keys; data (time, the watched name) never translated (#208).
	assert_str(_label(hud, "Vitals/Health/Cap/Text").text).is_equal("hud.health")
	assert_str(_label(hud, "Vitals/Stamina/Cap/Text").text).is_equal("hud.stamina")
	assert_str(_label(hud, "Slots/Hand/Center/Row/Name").text).is_equal("hud.slot.hand")
	assert_str(_label(hud, "Slots/Belt/Center/Row/Name").text).is_equal("hud.slot.belt")
	for data: Label in [hud.time_label, hud.watching_label]:
		assert_int(data.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_anchors_offsets_grow_and_sizes_are_the_handoffs() -> void:
	var hud := await _hud()
	var both := Control.GROW_DIRECTION_BOTH
	var begin := Control.GROW_DIRECTION_BEGIN
	var end := Control.GROW_DIRECTION_END
	# [node, anchors (left, top, right, bottom), offsets, grow h, grow v]
	var placed: Array[Array] = [
		[hud.timer, Vector4(0.5, 0, 0.5, 0), Vector4(0, 40, 0, 40), both, end],
		[hud.role, Vector4(0, 0, 0, 0), Vector4(40, 40, 40, 40), end, end],
		[hud.cross, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 0, 0, 0), both, both],
		[hud.aim, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 38, 0, 38), both, both],
		[hud.vitals, Vector4(0, 1, 0, 1), Vector4(40, -40, 40, -40), end, begin],
		[hud.slots, Vector4(1, 1, 1, 1), Vector4(-40, -40, -40, -40), begin, begin],
		[hud.raising, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0, 38, 0, 38), both, both],
		[hud.spectate, Vector4(0.5, 0, 0.5, 0), Vector4(0, 40, 0, 40), both, end],
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
	assert_vector(hud.time_label.custom_minimum_size).is_equal(Vector2(140, 0))
	assert_vector(hud.cross.custom_minimum_size).is_equal(Vector2(8, 8))
	assert_vector(hud.health_box.custom_minimum_size).is_equal(Vector2(320, 0))
	assert_vector(hud.health.custom_minimum_size).is_equal(Vector2(320, 16))
	assert_vector(hud.health.fill.custom_minimum_size).is_equal(Vector2(0, 10))
	assert_vector(hud.stamina.custom_minimum_size).is_equal(Vector2(320, 16))
	assert_vector(hud.mic.custom_minimum_size).is_equal(Vector2(46, 46))
	assert_vector(hud.mic_icon.custom_minimum_size).is_equal(Vector2(28, 28))
	assert_vector(hud.hand.custom_minimum_size).is_equal(Vector2(88, 88))
	assert_vector(hud.belt.custom_minimum_size).is_equal(Vector2(88, 88))
	assert_vector(hud.raising_bar.custom_minimum_size).is_equal(Vector2(240, 10))
	assert_int(hud.mic.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	var cap := hud.get_node("Vitals/Health/Cap") as Control
	assert_int(cap.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_int(hud.mic_icon.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_int(hud.hand.name_label.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	# The time's plate is as wide for "44:44" as for "11:11": its 140 px hold the widest time.
	hud.time_label.text = "11:11"
	var narrow := hud.timer.get_combined_minimum_size().x
	hud.time_label.text = "44:44"
	assert_float(hud.timer.get_combined_minimum_size().x).is_equal(narrow)


func test_no_node_takes_the_mouse_or_focus() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"mate"))
	var all: Array[Node] = hud.find_children("*", "Control", true, false)
	all.append(hud)
	for node: Node in all:
		var control := node as Control
		assert_int(control.mouse_filter).override_failure_message(str(control.get_path())).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).is_equal(Control.FOCUS_NONE)


func test_the_health_fill_takes_the_ramps_stop() -> void:
	var hud := await _hud()
	for row: Array in [[0.22, "ramp_stop_04"], [0.8, "ramp_stop_16"], [1.0, "ramp_stop_20"]]:
		var shown := _state(&"empty")
		shown.health = row[0]
		hud.show_hud(shown)
		assert_float(hud.health.fill.value).is_equal(row[0])
		assert_object(hud.health.fill.self_modulate).is_equal(
			GameUi.THEME.get_color(row[1] as String, &"ToyBarHealth")
		)


func test_empty_shows_the_slot_names_and_aim() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"empty"))
	assert_bool(hud.timer.visible).is_true()
	assert_str(hud.time_label.text).is_equal("07:22")
	assert_str(hud.role_label.text).is_equal("role.engineer")
	assert_bool(hud.aim.visible).is_true()
	assert_str(hud.aim_label.text).is_equal("item.package")
	assert_bool(hud.raising.visible).is_false()
	assert_bool(hud.spectate.visible).is_false()
	for slot: HudSlot in [hud.hand, hud.belt]:
		assert_bool(slot.name_label.visible).is_true()
		assert_bool(slot.icon.visible).is_false()
		assert_bool(slot.item_label.visible).is_false()
	assert_float(hud.health.fill.value).is_equal(0.8)
	assert_float(hud.stamina.fill.value).is_equal(0.9)
	# The mic on: `mic` tinted icon_on.
	assert_object(hud.mic_icon.texture).is_same(ToyIcons.texture(&"mic"))
	assert_object(hud.mic_icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"icon_on", &"ToyMic")
	)


func test_pack_widens_the_hand_with_its_icon_and_name() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"pack"))
	await get_tree().process_frame
	var hand := hud.hand
	assert_bool(hud.aim.visible).is_false()
	assert_bool(hand.name_label.visible).is_false()
	assert_bool(hand.icon.visible).is_true()
	assert_object(hand.icon.texture).is_same(ToyIcons.texture(&"item"))
	assert_vector(hand.icon.custom_minimum_size).is_equal(Vector2(48, 48))
	assert_object(hand.icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"font_color", &"ToySlotText")
	)
	assert_bool(hand.item_label.visible).is_true()
	assert_str(hand.item_label.text).is_equal("item.package")
	assert_vector(hand.item_label.custom_minimum_size).is_equal(Vector2(106, 0))
	assert_bool(hand.item_label.clip_text).is_true()
	assert_int(hand.item_label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_vector(hand.custom_minimum_size).is_equal(Vector2(180, 88))
	# The hand slot's width is its minimum: a long name is cut, never widening it.
	hand.item_label.text = "A very long name of some package"
	await get_tree().process_frame
	assert_float(hand.size.x).is_equal(180.0)
	# Empty again: back to 88.
	hud.show_hud(_state(&"empty"))
	assert_vector(hand.custom_minimum_size).is_equal(Vector2(88, 88))


func test_tired_and_hurt_change_only_their_bar() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"tired"))
	assert_float(hud.stamina.fill.value).is_equal(0.18)
	assert_float(hud.health.fill.value).is_equal(0.8)
	hud.show_hud(_state(&"hurt"))
	assert_float(hud.health.fill.value).is_equal(0.22)
	assert_object(hud.health.fill.self_modulate).is_equal(
		GameUi.THEME.get_color(&"ramp_stop_04", &"ToyBarHealth")
	)


func test_mate_shows_the_knife_icon_alone_on_the_belt_and_the_dissident_role() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"mate"))
	assert_str(hud.role_label.text).is_equal("role.dissident")
	assert_bool(hud.aim.visible).is_false()
	assert_bool(hud.belt.name_label.visible).is_false()
	assert_bool(hud.belt.icon.visible).is_true()
	assert_bool(hud.belt.item_label.visible).is_false()
	assert_object(hud.belt.icon.texture).is_same(ToyIcons.texture(&"knife"))
	assert_object(hud.belt.icon.self_modulate).is_equal(
		GameUi.THEME.get_color(&"font_color", &"ToyTextOnDark")
	)
	assert_vector(hud.belt.custom_minimum_size).is_equal(Vector2(88, 88))


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


func test_a_spectator_sees_the_watched_name_and_slots_only() -> void:
	var hud := await _hud()
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	model.fold(&"Died", {"peer": model.own_peer, "position": Vector3.ZERO})
	var local := HudText.Local.new()
	local.watching = 3
	hud.show_hud(HudText.of(model, _mode, 100, local))
	assert_bool(hud.spectate.visible).is_true()
	assert_str(hud.watching_label.text).is_equal(tr("dead.watching").format({"name": "Player3"}))
	for hidden: Control in [hud.timer, hud.role, hud.vitals, hud.aim, hud.raising]:
		assert_bool(hidden.visible).override_failure_message(hidden.name).is_false()
	assert_bool(hud.slots.visible).is_true()


func test_large_text_keeps_the_sizes_and_shrinks_back() -> void:
	var hud := await _hud()
	hud.show_hud(_state(&"pack"))
	var holder := hud.get_parent() as Control
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(hud.hand.custom_minimum_size).is_equal(Vector2(180, 88))
	assert_vector(hud.mic.custom_minimum_size).is_equal(Vector2(46, 46))
	holder.theme = GameUi.THEME
	await get_tree().process_frame
	await get_tree().process_frame
	hud.show_hud(_state(&"empty"))
	await get_tree().process_frame
	# The slots' row shrinks back to its minimum and stays in the corner, 40 px in.
	assert_float(hud.slots.size.x).is_equal(hud.slots.get_combined_minimum_size().x)
	assert_float(hud.slots.get_rect().end.x).is_equal(holder.size.x - 40.0)


## The handoff's states as HudText would show them (its samples: 07:22, health 0.8, stamina 0.9,
## the mic on, the crosshair on a package).
static func _state(state: StringName) -> HudText.Shown:
	var shown := HudText.Shown.new()
	shown.time = "07:22"
	shown.role = "role.engineer"
	shown.vitals = true
	shown.health = 0.8
	shown.stamina = 0.9
	shown.mic = true
	shown.slots = true
	shown.aim = "item.package"
	match state:
		&"pack":
			shown.aim = ""
			shown.hand = _slot("item.package", &"item", true)
		&"tired":
			shown.stamina = 0.18
		&"hurt":
			shown.health = 0.22
		&"mate":
			shown.aim = ""
			shown.role = "role.dissident"
			shown.belt = _slot("item.knife", &"knife", false)
		&"raising":
			shown.raising = 0.6
	return shown


static func _slot(item: String, icon: StringName, two_handed: bool) -> HudText.Slot:
	var slot := HudText.Slot.new()
	slot.item = item
	slot.icon = icon
	slot.two_handed = two_handed
	return slot


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
