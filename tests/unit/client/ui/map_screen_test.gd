extends GdUnitTestSuite
## The map and tasks screen (MapScreen, #253; its Toy look #490) from a fake ClientModel, the
## client's own mode and the preview's fake house: one row per task type with its name and its
## counter in the language now, no description, a «?» per row asking for the type's how-to card,
## the rooms by pictogram and name, the zones of a hovered or focused type, the own pin, the clock;
## the tree node for node as prime-game-ui's s08 handoff at ui-2.5.4 draws it, and its keyboard
## focus. And the privacy rule (the M4 ADR's §3 item 4 as revised by #253, replacing hud_test's "the
## task screen names no place"): models that differ only in the other players, the items and the
## circles draw the very same screen. How it looks: the `shot`s of client/dev/map_*preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
## The fake round's host tick: 271 s before the match clock ends.
const NOW := 100

var _mode: GameMode
var _data: MapData


func before() -> void:
	_mode = load(MODE) as GameMode
	var house := Preview.fake_level()
	_data = MapData.from_level(house, _mode)
	house.free()


func before_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func after_test() -> void:
	for key: Key in [KEY_DOWN, KEY_ENTER]:
		_key(key, false)


func after() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_one_row_per_task_type_with_its_name_and_counter_and_no_description() -> void:
	# The fake round's two Delivery tasks (1 of 3 and 2 of 2) share their type's row.
	var screen := _screen(_round_model())
	assert_array(_row_texts(screen)).contains_exactly(["Delivery|3 of 5|?"])
	var all := _all_texts(screen)
	var delivery := _mode.find_task_type(&"delivery")
	assert_str(all).not_contains(delivery.description)
	assert_str(all).not_contains("NEW")
	assert_str(all).not_contains("Shared progress")
	assert_str(screen.time_label.text).is_equal("Time: 4:31")
	assert_str(screen.title.text).is_equal("map.tasks")
	# A task type the client's mode does not name shows its id, in the order of its task.
	var model := _round_model()
	model.fold(&"TaskState", {"task": 5, "type": &"zones", "done": 0, "total": 4})
	screen.refresh(model, _mode, NOW, _local())
	assert_array(_row_texts(screen)).contains_exactly(["Delivery|3 of 5|?", "zones|0 of 4|?"])


func test_a_counter_changes_in_place_and_keeps_the_focus() -> void:
	var screen := _screen(_round_model())
	var help := _help(screen, 0)
	help.grab_focus()
	var model := _round_model()
	model.fold(&"TaskState", {"task": 0, "type": &"delivery", "done": 2, "total": 3})
	screen.refresh(model, _mode, NOW, _local())
	assert_array(_row_texts(screen)).contains_exactly(["Delivery|4 of 5|?"])
	assert_object(_help(screen, 0)).is_same(help)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(help)


func test_a_task_with_every_subtask_done_is_struck_through() -> void:
	# The fake round's Delivery row is 3 of 5 (placeholder look until #150: a line over the name).
	var screen := _screen(_round_model())
	assert_bool(_struck(screen, 0)).is_false()
	var model := _round_model()
	model.fold(&"TaskState", {"task": 0, "type": &"delivery", "done": 3, "total": 3})
	screen.refresh(model, _mode, NOW, _local())
	assert_array(_row_texts(screen)).contains_exactly(["Delivery|5 of 5|?"])
	assert_bool(_struck(screen, 0)).is_true()
	screen.refresh(_round_model(), _mode, NOW, _local())
	assert_bool(_struck(screen, 0)).is_false()


func test_an_unchanged_refresh_does_not_lay_the_zone_tag_out_again() -> void:
	var screen := _screen(_round_model())
	screen.light(&"delivery")
	var marked := Vector2(-7, -7)
	screen.zone_hint.position = marked
	screen.refresh(_round_model(), _mode, NOW, _local())
	assert_vector(screen.zone_hint.position).is_equal(marked)
	assert_bool(screen.zone_hint.visible).is_true()


func test_the_words_follow_the_language_at_once() -> void:
	var screen := _screen(_round_model())
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_array(_row_texts(screen)).contains_exactly(["Доставка|3 з 5|?"])
	assert_str(screen.time_label.text).is_equal("Час: 4:31")
	assert_str(_room_label(screen, &"storage").text).is_equal("Склад")
	screen.light(&"delivery")
	assert_str(_visible_texts(screen.zone_hint)).is_equal("Тут ця задача")
	TranslationServer.set_locale(Languages.ENGLISH)
	await get_tree().process_frame
	assert_str(_room_label(screen, &"storage").text).is_equal("Storage")
	assert_array(_row_texts(screen)).contains_exactly(["Delivery|3 of 5|?"])


func test_the_tree_is_the_handoffs_node_for_node() -> void:
	# prime-game-ui's docs/handoff/s08-map.md at ui-2.5.4, state `list`.
	var screen := _screen(_round_model())
	await get_tree().process_frame
	var names: Array[String] = []
	for child: Node in screen.get_children():
		names.append(String(child.name))
	assert_array(names).contains_exactly(["Dim", "Tasks", "Board", "Dim2", "Guide"])
	var dim := screen.get_node("Dim") as Panel
	assert_str(String(dim.theme_type_variation)).is_equal("ToyBackdropDeep")
	assert_int(dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# Tasks: at the top left, 60 px in, 624 wide, growing down to its content.
	assert_vector(screen.tasks_panel.position).is_equal(Vector2(60, 60))
	assert_float(screen.tasks_panel.size.x).is_equal(624.0)
	_expect(screen.tasks_panel, "Tasks", "ToyPanelMenu")
	_expect(screen.tasks_panel.get_node("V"), "V", "ToyColumnSixteen")
	_expect(screen.tasks_panel.get_node("V/Title"), "Title", "ToyKicker")
	assert_bool((screen.tasks_panel.get_node("V/Title") as Label).uppercase).is_true()
	_expect(screen.tasks_panel.get_node("V/Rows"), "Rows", "ToyColumnFour")
	_expect(screen.tasks_panel.get_node("V/Time"), "Time", "ToyTextMutedOnLight")
	var row := screen.rows_box.get_node("Delivery") as Control
	_expect(row, "Delivery", "ToySettingRow")
	assert_vector(row.custom_minimum_size).is_equal(Vector2(0, 96))
	_expect(row.get_node("H"), "H", "ToyRowSixteen")
	var task_name := row.get_node("H/Name") as Label
	_expect(task_name, "Name", "ToySettingRowValue")
	assert_int(task_name.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_int(task_name.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	_expect(row.get_node("H/Count"), "Count", "ToySettingRowText")
	var help := row.get_node("H/Help") as Button
	_expect(help, "Help", "ToyKeyRoundButton")
	assert_vector(help.custom_minimum_size).is_equal(Vector2(63, 63))
	assert_int(help.focus_mode).is_equal(Control.FOCUS_ALL)
	assert_int(help.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	# Board: 732 to 1860 across, 60 to 1020 down; Rooms inside its 6 px margins is 1116x948.
	assert_vector(screen.board.position).is_equal(Vector2(732, 60))
	assert_vector(screen.board.size).is_equal(Vector2(1128, 960))
	_expect(screen.board, "Board", "ToyMapBoard")
	assert_str(String(screen.plan.name)).is_equal("Rooms")
	assert_vector(screen.plan.size).is_equal(MapScreen.ROOMS_SIZE)
	# The board's head, fixed: 48 px in, 24 px down, first in Rooms.
	var head := screen.plan.get_node("Head") as Label
	_expect(head, "Head", "ToyKicker")
	assert_str(head.text).is_equal("map.title")
	assert_bool(head.uppercase).is_true()
	assert_vector(head.position).is_equal(Vector2(48, 24))
	assert_int(head.get_index()).is_equal(0)
	var room := screen.plan.get_node("Storage") as Control
	_expect(room, "Storage", "ToyMapRoom")
	var column := room.get_node("V") as VBoxContainer
	_expect(column, "V", "ToyColumnEight")
	var label := room.get_node("V/Name") as Label
	_expect(label, "Name", "ToyKicker")
	assert_bool(label.uppercase).is_true()
	assert_int(label.get_index()).is_equal(0)
	var area := room.get_node("V/Area") as Control
	assert_int(area.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)
	var icon := room.get_node("V/Area/Icon") as TextureRect
	assert_object(icon.texture).is_same(ToyIcons.texture(&"room/storage"))
	assert_vector(icon.custom_minimum_size).is_equal(Vector2(72, 72))
	assert_int(icon.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(icon.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	# Centred in the Area.
	assert_vector(icon.position + icon.size / 2.0).is_equal_approx(
		area.size / 2.0, Vector2.ONE * 0.51
	)
	# Drawn in the heads' dim colour (ToyKicker's, the pack's tint_color #a39dbd).
	assert_str(icon.self_modulate.to_html(false)).is_equal("a39dbd")
	# The rooms fill the area under the head: none above 72 px or left of 48 px.
	for each: MapData.Room in _data.rooms:
		var tile := screen.plan.get_node(String(each.id).to_pascal_case()) as Control
		(
			assert_bool(MapScreen.ROOMS_AREA.grow(0.01).encloses(Rect2(tile.position, tile.size)))
			. is_true()
		)
	_expect(screen.pin, "Pin", "ToyMapPin")
	_expect(screen.here, "Here", "ToyChipPlate")
	_expect(screen.here.get_node("Text"), "Text", "ToyHudCaption")
	# Every room of the fake house has its pictogram.
	for each: MapData.Room in _data.rooms:
		var tile := screen.plan.get_node(String(each.id).to_pascal_case())
		assert_object((tile.get_node("V/Area/Icon") as TextureRect).texture).is_not_null()


func test_each_rows_question_mark_asks_for_its_types_card() -> void:
	var screen := _screen(_round_model())
	var asked: Array[StringName] = []
	screen.howto_requested.connect(func(type: StringName) -> void: asked.append(type))
	_help(screen, 0).pressed.emit()
	assert_array(asked).contains_exactly([&"delivery"])
	assert_bool(screen.howto_open()).is_true()


func test_a_question_mark_opens_its_types_card_over_the_map() -> void:
	# #254, s8's `guide`: the card on Dim2, centred, the list and the board out of focus's reach.
	var screen := _screen(_round_model())
	assert_bool(screen.howto_open()).is_false()
	assert_bool(screen.howto_dim.visible).is_false()
	_help(screen, 0).pressed.emit()
	assert_bool(screen.howto_open()).is_true()
	assert_str(String(screen.howto_type)).is_equal("delivery")
	assert_str(screen.howto_dim.name).is_equal("Dim2")
	assert_str(String(screen.howto_dim.theme_type_variation)).is_equal("ToyBackdrop")
	assert_int(screen.howto_dim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(screen.howto_dim.visible).is_true()
	assert_bool(screen.howto_center.visible).is_true()
	assert_int(screen.howto_center.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_object(screen.howto.get_parent()).is_same(screen.howto_center)
	var face := HowtoCardView.face_of(screen.howto)
	# The card takes its content's width: the sideways Scroll's 1384 px (s8's Card).
	assert_float(face.scroll.custom_minimum_size.x).is_equal(1384.0)
	assert_str(face.title_label.text).is_equal("task.delivery")
	assert_object(face.close_button).is_not_null()
	var first := face.frames_box.get_child(0).get_child(0) as Control
	assert_that(first.custom_minimum_size).is_equal(HowtoCardView.MAP_ART)
	for each: Control in [screen.tasks_panel, screen.board]:
		assert_int(each.focus_behavior_recursive).is_equal(Control.FOCUS_BEHAVIOR_DISABLED)
	# The card is above the map: the last children of the screen.
	assert_int(screen.howto_center.get_index()).is_equal(screen.get_child_count() - 1)
	assert_int(screen.howto_dim.get_index()).is_equal(screen.get_child_count() - 2)
	var card := screen.howto
	face.close_button.pressed.emit()
	assert_bool(screen.howto_open()).is_false()
	assert_bool(screen.howto_dim.visible).is_false()
	assert_bool(screen.howto_center.visible).is_false()
	for each: Control in [screen.tasks_panel, screen.board]:
		assert_int(each.focus_behavior_recursive).is_equal(Control.FOCUS_BEHAVIOR_INHERITED)
	await get_tree().process_frame
	assert_bool(is_instance_valid(card)).is_false()
	# A type with no card opens nothing.
	assert_bool(screen.open_howto(&"no_such_task")).is_false()
	assert_bool(screen.howto_open()).is_false()


## Esc and the map key close the card through GameUi.overlays (game_ui_overlays_test.gd,
## map_input_test.gd); the map hiding closes it here.
func test_hiding_the_map_closes_the_card() -> void:
	var screen := _screen(_round_model())
	screen.open_howto(&"delivery")
	screen.visible = false
	assert_bool(screen.howto_open()).is_false()
	# The closed cards are freed at the end of the frame.
	await get_tree().process_frame


func test_closing_the_card_drops_its_own_focus_only() -> void:
	# The Esc menu opens before the map closes (GameUi.open_esc): its focus must stay.
	var screen := _screen(_round_model())
	var outside := Button.new()
	add_child(outside)
	auto_free(outside)
	screen.open_howto(&"delivery")
	outside.grab_focus()
	screen.close_howto()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(outside)
	screen.open_howto(&"delivery")
	var close := HowtoCardView.face_of(screen.howto).close_button
	close.grab_focus()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(close)
	screen.close_howto()
	assert_object(get_viewport().gui_get_focus_owner()).is_null()
	await get_tree().process_frame


func test_no_focus_on_open_and_the_first_arrow_focuses_the_first_question_mark() -> void:
	var screen := _screen(_round_model())
	await get_tree().process_frame
	assert_object(get_viewport().gui_get_focus_owner()).is_null()
	assert_str(String(screen.lit())).is_empty()
	_key(KEY_DOWN, true)
	_key(KEY_DOWN, false)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_help(screen, 0))
	# The keyboard's focus on a «?» lights its zones, as hovering its row does (state `zone`).
	await get_tree().process_frame
	assert_str(String(screen.lit())).is_equal("delivery")
	get_viewport().gui_release_focus()
	await get_tree().process_frame
	assert_str(String(screen.lit())).is_empty()
	# A focus the mouse gave (hidden) lights nothing: the mouse is over the row anyway.
	_help(screen, 0).grab_focus(true)
	await get_tree().process_frame
	assert_str(String(screen.lit())).is_empty()
	get_viewport().gui_release_focus()


func test_a_card_opened_by_the_keyboard_focuses_close_and_gives_the_focus_back() -> void:
	var screen := _screen(_round_model())
	_key(KEY_DOWN, true)
	_key(KEY_DOWN, false)
	var help := _help(screen, 0)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(help)
	# Enter presses the focused «?» (Space is out of ui_accept, #488).
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	assert_bool(screen.howto_open()).is_true()
	var close := HowtoCardView.face_of(screen.howto).close_button
	assert_object(get_viewport().gui_get_focus_owner()).is_same(close)
	# While the card is open an arrow focuses nothing under it.
	_key(KEY_DOWN, true)
	_key(KEY_DOWN, false)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(close)
	screen.close_howto()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(help)
	assert_bool(help.has_focus(true)).is_true()
	get_viewport().gui_release_focus()
	await get_tree().process_frame


func test_a_card_opened_with_the_mouse_drops_the_focus_on_close() -> void:
	var screen := _screen(_round_model())
	var help := _help(screen, 0)
	# A mouse press focuses the «?» hidden, then presses it.
	help.grab_focus(true)
	help.pressed.emit()
	assert_bool(screen.howto_open()).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_not_same(
		HowtoCardView.face_of(screen.howto).close_button
	)
	screen.close_howto()
	assert_object(get_viewport().gui_get_focus_owner()).is_null()
	await get_tree().process_frame


func test_lighting_a_type_shows_its_zones_and_their_tag_only() -> void:
	var screen := _screen(_round_model())
	assert_array(_lit_rooms(screen)).is_empty()
	assert_bool(screen.zone_hint.visible).is_false()
	screen.light(&"delivery")
	assert_array(_lit_rooms(screen)).contains_exactly(["storage", "lab"])
	assert_bool(screen.zone_hint.visible).is_true()
	assert_str(String(screen.zone_hint.name)).is_equal("ZoneDeliveryTag")
	assert_str(String(screen.zone_hint.theme_type_variation)).is_equal("ToyChipLight")
	_expect(screen.zone_hint.get_node("Text"), "Text", "ToyChipLightText")
	# A type the deck has no own tag for takes the handoff's map.zone_hint.task.
	assert_str(_visible_texts(screen.zone_hint)).is_equal("This task is here")
	assert_str(String(screen.lit())).is_equal("delivery")
	# The zone is its room's Area's first child, under the pictogram, filling the room under its
	# head.
	var zone := screen.plan.get_node("Storage/V/Area").get_child(0) as Panel
	assert_float(zone.anchor_right).is_equal(1.0)
	assert_float(zone.anchor_bottom).is_equal(1.0)
	assert_str(String(zone.name)).is_equal("ZoneDelivery")
	assert_str(String(zone.theme_type_variation)).is_equal("ToyMapZone")
	assert_int(zone.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	screen.unlight()
	assert_array(_lit_rooms(screen)).is_empty()
	assert_bool(screen.zone_hint.visible).is_false()
	# A type with no zones lights nothing.
	screen.light(&"zones")
	assert_array(_lit_rooms(screen)).is_empty()
	assert_bool(screen.zone_hint.visible).is_false()


func test_the_zone_tag_sits_under_its_room_and_wraps_only_at_the_boards_edge() -> void:
	TranslationServer.set_locale(Languages.UKRAINIAN)
	var screen := _screen(_round_model())
	screen.light(&"delivery")
	var tile := screen.plan.get_node("Storage") as Control
	assert_vector(screen.zone_hint.position).is_equal(
		tile.position + Vector2(0, tile.size.y + MapScreen.ZONE_HINT_GAP)
	)
	var label := screen.zone_hint.get_node("Text") as Label
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)
	# A narrow room at the board's right edge: the tag wraps rather than leave the board.
	var data := MapData.new()
	data.rooms.append(MapData.Room.new(&"hall", Rect2(0, 0, 30, 10)))
	data.rooms.append(MapData.Room.new(&"lab", Rect2(31, 0, 2, 10)))
	data.zones[&"delivery"] = PackedStringArray(["lab"])
	screen.set_data(data)
	screen.light(&"delivery")
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	(
		assert_float(screen.zone_hint.position.x + screen.zone_hint.get_combined_minimum_size().x)
		. is_less_equal(MapScreen.ROOMS_SIZE.x + 0.01)
	)


func test_the_zone_tag_of_a_room_in_the_bottom_row_goes_above_it_not_off_the_board() -> void:
	var screen := _screen(_round_model())
	# Large text: the tag is taller than what the plan leaves under its lowest row.
	screen.theme = GameUi.THEME_LARGE
	var data := MapData.new()
	data.rooms.append(MapData.Room.new(&"hall", Rect2(0, 0, 10, 10)))
	data.rooms.append(MapData.Room.new(&"lab", Rect2(0, 10, 10, 10)))
	data.zones[&"delivery"] = PackedStringArray(["lab"])
	screen.set_data(data)
	screen.light(&"delivery")
	var tile := screen.plan.get_node("Lab") as Control
	var tag: Control = screen.zone_hint
	assert_float(tag.position.y + tag.size.y).is_less_equal(MapScreen.ROOMS_SIZE.y + 0.01)
	assert_float(tag.position.y + tag.size.y).is_less_equal(tile.position.y)
	assert_float(tag.position.y).is_greater_equal(0.0)


func test_the_rooms_by_name_and_the_own_pin_at_the_own_place_and_heading() -> void:
	var local := _local()
	local.placed = false
	var screen := _screen(_round_model(), local)
	assert_array(_room_names(screen)).contains_exactly(
		["Storage", "Kitchen", "Lab", "Office", "Hall", "Break room"]
	)
	# No own place yet (or dead): no pin, no chip.
	assert_bool(screen.pin.visible).is_false()
	assert_bool(screen.here.visible).is_false()
	screen.refresh(_round_model(), _mode, NOW, _local())
	assert_bool(screen.pin.visible).is_true()
	assert_bool(screen.here.visible).is_true()
	assert_str(_visible_texts(screen.here)).is_equal("You are here")
	var centre := screen.pin.position + screen.pin.size / 2.0
	var expected := (
		MapScreen.ROOMS_AREA.position
		+ _data.to_board(
			Vector2(Preview.FAKE_OWN_PLACE.x, Preview.FAKE_OWN_PLACE.z), MapScreen.ROOMS_AREA.size
		)
	)
	assert_vector(centre).is_equal_approx(expected, Vector2.ONE * 0.01)
	assert_float(screen.pin.rotation).is_equal_approx(PI / 4.0 + Preview.FAKE_OWN_HEADING, 0.0001)
	assert_vector(screen.pin.size).is_equal(Vector2(42, 42))
	# "You are here" 21 px right of the pin's rect, its centre on the pin's centre line; it does
	# not turn.
	assert_float(screen.here.position.x).is_equal(screen.pin.position.x + 42 + 21)
	assert_float(screen.here.position.y + screen.here.size.y / 2.0).is_equal_approx(centre.y, 0.51)
	assert_float(screen.here.rotation).is_equal(0.0)


func test_a_room_shows_its_records_name_key_in_the_language_now() -> void:
	# The room record (#306) names the room, not its id; a key the deck lacks shows the id.
	var screen := _screen(_round_model())
	var data := MapData.new()
	data.rooms.append(MapData.Room.new(&"cellar", Rect2(0, 0, 10, 10), "room.storage"))
	data.rooms.append(MapData.Room.new(&"attic_nook", Rect2(10, 0, 10, 10), "room.no_such_room"))
	screen.set_data(data)
	assert_str(_room_label(screen, &"cellar").text).is_equal("Storage")
	assert_str(_room_label(screen, &"attic_nook").text).is_equal("attic_nook")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_str(_room_label(screen, &"cellar").text).is_equal("Склад")


func test_a_level_without_rooms_hides_the_board_and_keeps_the_tasks() -> void:
	var screen := _screen(_round_model())
	screen.set_data(MapData.new())
	assert_bool(screen.board.visible).is_false()
	assert_bool(screen.pin.visible).is_false()
	assert_int(_row_texts(screen).size()).is_equal(1)


func test_other_players_items_and_circles_change_nothing_on_the_screen() -> void:
	# The privacy rule: the screen is the same whatever the model holds of the others, the items
	# (where they lie, who holds them) and the circles; only the own place moves the pin.
	var plain := Preview.fake_model(_mode, true)
	Preview.fold_round(plain, false)
	var busy := _round_model()
	busy.roster[7] = ClientModel.Member.new()
	busy.roster[7].name = "Stranger"
	busy.spots[2] = Vector3(-15, 0, 2)
	busy.spots[7] = Vector3(14, 0, -11)
	busy.bodies[3] = Vector3(-17, 0, -13)
	busy.avatars[2] = {"position": Vector3(-15, 0, 2)}
	for item: ClientModel.Item in busy.items.values():
		item.position = Vector3(-15, 0, 2)
		item.holder = 0
	for station: ClientModel.Station in busy.stations.values():
		station.position = Vector3(14, 0, -11)
	for lit: StringName in [&"", &"delivery"]:
		var one := _screen(plain)
		var other := _screen(busy)
		if not lit.is_empty():
			one.light(lit)
			other.light(lit)
		assert_array(_signature(other)).is_equal(_signature(one))
	# The board holds its head, the rooms (each its column of name and area), the pin and two
	# chips: nothing else to draw on.
	var screen := _screen(busy)
	assert_int(screen.plan.get_child_count()).is_equal(_data.rooms.size() + 4)
	for room: MapData.Room in _data.rooms:
		var tile := screen.plan.get_node(String(room.id).to_pascal_case())
		assert_int(tile.get_child_count()).is_equal(1)
		assert_int(tile.get_node("V").get_child_count()).is_equal(2)
	var all := _all_texts(screen)
	assert_str(all).not_contains("Player")
	assert_str(all).not_contains("Stranger")
	for item: ClientModel.Item in busy.items.values():
		assert_str(all).not_contains(str(item.position))


func _screen(model: ClientModel, local: HudText.Local = _local()) -> MapScreen:
	var screen: MapScreen = auto_free(MapScreen.new())
	screen.theme = GameUi.THEME
	add_child(screen)
	screen.set_data(_data)
	screen.refresh(model, _mode, NOW, local)
	return screen


func _round_model() -> ClientModel:
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	return model


func _local() -> HudText.Local:
	var local := HudText.Local.new()
	local.placed = true
	local.position = Preview.FAKE_OWN_PLACE
	local.heading = Preview.FAKE_OWN_HEADING
	return local


func _help(screen: MapScreen, row: int) -> Button:
	return screen.rows_box.get_child(row).find_child("Help", true, false) as Button


func _expect(node: Node, expected_name: String, variation: String) -> void:
	assert_str(String(node.name)).is_equal(expected_name)
	assert_str(String((node as Control).theme_type_variation)).is_equal(variation)


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Each row as "name|counter|«?»".
func _row_texts(screen: MapScreen) -> Array[String]:
	var made: Array[String] = []
	for row: Node in screen.rows_box.get_children():
		if row.is_queued_for_deletion():
			continue
		var name_label := row.find_child("Name", true, false) as Label
		var count := row.find_child("Count", true, false) as Label
		var help := row.find_child("Help", true, false) as Button
		made.append("%s|%s|%s" % [name_label.text, count.text, help.text])
	return made


func _struck(screen: MapScreen, index: int) -> bool:
	var name_label := screen.rows_box.get_child(index).find_child("Name", true, false) as Label
	return name_label.get_meta(&"struck", false)


func _room_label(screen: MapScreen, id: StringName) -> Label:
	return screen.plan.get_node("%s/V/Name" % String(id).to_pascal_case()) as Label


func _room_names(screen: MapScreen) -> Array[String]:
	var names: Array[String] = []
	for room: MapData.Room in _data.rooms:
		names.append(_room_label(screen, room.id).text)
	return names


## The ids of the rooms holding a lit zone.
func _lit_rooms(screen: MapScreen) -> Array[String]:
	var lit: Array[String] = []
	for zone: Node in screen.plan.find_children("Zone*", "Panel", true, false):
		if (zone as Control).visible:
			# Zone < Area < V < the room's tile.
			lit.append(String(zone.get_parent().get_parent().get_parent().name).to_snake_case())
	return lit


## The labels' words under `under` as drawn: a key text translated as its label would.
func _visible_texts(under: Node) -> String:
	var texts := PackedStringArray()
	for label: Node in under.find_children("*", "Label", true, false):
		texts.append(label.atr((label as Label).text))
	return "\n".join(texts)


## Every text under the screen, its labels' and its buttons' (tooltips too).
func _all_texts(screen: MapScreen) -> String:
	var texts := PackedStringArray()
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		texts.append(control.tooltip_text)
		if control is Label:
			texts.append((control as Label).text)
		elif control is Button:
			texts.append((control as Button).text)
	return "\n".join(texts)


## Each node under the screen, in tree order: its class, name, place, size, turn, visibility and
## text. Node names that the engine makes unique (@Label@123) are cut to their class.
func _signature(screen: MapScreen) -> Array[String]:
	var made: Array[String] = []
	for node: Node in screen.find_children("*", "Control", true, false):
		if node.is_queued_for_deletion():
			continue
		var control := node as Control
		var text := ""
		if control is Label:
			text = (control as Label).text
		elif control is Button:
			text = (control as Button).text
		var shown_name := "@" if String(control.name).begins_with("@") else String(control.name)
		(
			made
			. append(
				(
					"%s %s %s %s %.4f %s %s"
					% [
						control.get_class(),
						shown_name,
						control.position,
						control.size,
						control.rotation,
						control.visible,
						text,
					]
				)
			)
		)
	return made
