extends GdUnitTestSuite
## The map and tasks screen (MapScreen, #253) from a fake ClientModel, the client's own mode and the
## preview's fake house: one row per task with its name and its counter in the language now, no
## description, a «?» per row asking for the type's how-to card, the rooms by name, the zones of a
## hovered type, the own pin, the clock. And the privacy rule (the M4 ADR's §3 item 4 as revised by
## #253, replacing hud_test's "the task screen names no place"): models that differ only in the
## other players, the items and the circles draw the very same screen. How it looks: the `shot`s
## of client/dev/map_preview.tscn and map_preview_uk.tscn.

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


func after() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_one_row_per_task_with_its_name_and_counter_and_no_description() -> void:
	var screen := _screen(_round_model())
	assert_array(_row_texts(screen)).contains_exactly(["Delivery|1 of 3|?", "Delivery|2 of 2|?"])
	var all := _all_texts(screen)
	var delivery := _mode.find_task_type(&"delivery")
	assert_str(all).not_contains(delivery.description)
	assert_str(all).not_contains("NEW")
	assert_str(all).not_contains("Shared progress")
	assert_str(screen.time_label.text).is_equal("Time: 4:31")
	assert_str(screen.title.text).is_equal("map.tasks")
	# A task type the client's mode does not name shows its id.
	var model := _round_model()
	model.fold(&"TaskState", {"task": 5, "type": &"zones", "done": 0, "total": 4})
	screen.refresh(model, _mode, NOW, _local())
	assert_str(_row_texts(screen)[2]).is_equal("zones|0 of 4|?")


func test_the_words_follow_the_language_at_once() -> void:
	var screen := _screen(_round_model())
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_array(_row_texts(screen)).contains_exactly(["Доставка|1 з 3|?", "Доставка|2 з 2|?"])
	assert_str(screen.time_label.text).is_equal("Час: 4:31")
	assert_str(_room_label(screen, &"storage").text).is_equal("Склад")
	screen.light(&"delivery")
	assert_str(_visible_texts(screen.zone_hint)).is_equal("Тут можуть бути пакунки")
	TranslationServer.set_locale(Languages.ENGLISH)
	await get_tree().process_frame
	assert_str(_room_label(screen, &"storage").text).is_equal("Storage")
	assert_str(_row_texts(screen)[0]).is_equal("Delivery|1 of 3|?")


func test_each_rows_question_mark_asks_for_its_types_card() -> void:
	var screen := _screen(_round_model())
	var asked: Array[StringName] = []
	screen.howto_requested.connect(func(type: StringName) -> void: asked.append(type))
	var helps := screen.rows_box.find_children("Help", "Button", true, false)
	assert_int(helps.size()).is_equal(2)
	(helps[1] as Button).pressed.emit()
	assert_array(asked).contains_exactly([&"delivery"])
	# Only the mouse presses a «?» until #490 gives them keyboard focus.
	assert_int((helps[0] as Button).focus_mode).is_equal(Control.FOCUS_NONE)


func test_lighting_a_type_shows_its_zones_and_their_chip_only() -> void:
	var screen := _screen(_round_model())
	assert_array(_lit_rooms(screen)).is_empty()
	assert_bool(screen.zone_hint.visible).is_false()
	screen.light(&"delivery")
	assert_array(_lit_rooms(screen)).contains_exactly(["storage", "lab"])
	assert_bool(screen.zone_hint.visible).is_true()
	assert_str(_visible_texts(screen.zone_hint)).is_equal("Packages may be here")
	assert_str(String(screen.lit())).is_equal("delivery")
	screen.unlight()
	assert_array(_lit_rooms(screen)).is_empty()
	assert_bool(screen.zone_hint.visible).is_false()
	# A type with no zones lights nothing.
	screen.light(&"zones")
	assert_array(_lit_rooms(screen)).is_empty()
	assert_bool(screen.zone_hint.visible).is_false()


func test_the_zone_chip_stays_inside_its_room_in_a_long_language() -> void:
	TranslationServer.set_locale(Languages.UKRAINIAN)
	var screen := _screen(_round_model())
	screen.light(&"delivery")
	var tile := screen.plan.get_node("Room_storage") as Control
	assert_float(screen.zone_hint.get_combined_minimum_size().x).is_less_equal(
		tile.size.x - 2.0 * MapScreen.ZONE_HINT_GAP + 0.01
	)
	assert_vector(screen.zone_hint.position).is_equal(
		tile.position + Vector2.ONE * MapScreen.ZONE_HINT_GAP
	)


func test_the_rooms_by_name_and_the_own_pin_at_the_own_place_and_heading() -> void:
	var local := _local()
	local.placed = false
	var screen := _screen(_round_model(), local)
	assert_array(_room_names(screen)).contains_exactly(
		["Storage", "Hall", "Kitchen", "Lab", "Office", "Break room"]
	)
	# No own place yet (or dead): no pin, no chip.
	assert_bool(screen.pin.visible).is_false()
	assert_bool(screen.here.visible).is_false()
	screen.refresh(_round_model(), _mode, NOW, _local())
	assert_bool(screen.pin.visible).is_true()
	assert_bool(screen.here.visible).is_true()
	assert_str(_visible_texts(screen.here)).is_equal("You are here")
	var centre := screen.pin.position + screen.pin.size / 2.0
	var expected := _data.to_board(
		Vector2(Preview.FAKE_OWN_PLACE.x, Preview.FAKE_OWN_PLACE.z), MapScreen.BOARD_SIZE
	)
	assert_vector(centre).is_equal_approx(expected, Vector2.ONE * 0.01)
	assert_float(screen.pin.rotation).is_equal_approx(PI / 4.0 + Preview.FAKE_OWN_HEADING, 0.0001)
	assert_vector(screen.pin.size).is_equal(Vector2(28, 28))


func test_a_level_without_rooms_hides_the_board_and_keeps_the_tasks() -> void:
	var screen := _screen(_round_model())
	screen.set_data(MapData.new())
	assert_bool(screen.board.visible).is_false()
	assert_bool(screen.pin.visible).is_false()
	assert_int(_row_texts(screen).size()).is_equal(2)


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
	# The board holds the rooms (each with its zone and its name), the pin and two chips: nothing
	# else to draw on.
	var screen := _screen(busy)
	assert_int(screen.plan.get_child_count()).is_equal(_data.rooms.size() + 3)
	for room: MapData.Room in _data.rooms:
		assert_int(screen.plan.get_node("Room_%s" % room.id).get_child_count()).is_equal(2)
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


func _room_label(screen: MapScreen, id: StringName) -> Label:
	return screen.plan.get_node("Room_%s/Name" % id) as Label


func _room_names(screen: MapScreen) -> Array[String]:
	var names: Array[String] = []
	for room: MapData.Room in _data.rooms:
		names.append(_room_label(screen, room.id).text)
	return names


func _lit_rooms(screen: MapScreen) -> Array[String]:
	var lit: Array[String] = []
	for zone: Node in screen.plan.find_children("Zone_*", "Panel", true, false):
		if (zone as Control).visible:
			lit.append(zone.name.trim_prefix("Zone_"))
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
