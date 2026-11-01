extends GdUnitTestSuite
## The forest estate's room records (#1374, as the House's #306): every lot of
## docs/design/estate-map.md §3 with a footprint is a room of the map screen, its record on its own
## scene's root: an id (`metadata/room_id`, its scene's file name), a name (`metadata/name_key`, a
## copy deck key) and `metadata/centred` (a lot stands at its centre, the level-piece ADR's
## 2026-10-29 amendment), so MapData draws each lot over the doc's footprint.

const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
## The proposed keys the copy deck has no text for yet: none since ui-2.5.0 (the estate's own names
## are in prime-game-ui's deck). A new room key without text goes here until it lands.
const AWAITING_DECK: Array[String] = []


func test_every_lot_with_a_footprint_is_a_room_with_its_record() -> void:
	var map := _map()
	var expected: Array[String] = []
	for module in EstateDoc.modules():
		if module.size != Vector2i.ZERO:
			expected.append(EstateDoc.snake(module.name))
	var got: Array[String] = []
	for room in _rooms_of(map):
		var id: Variant = room.get_meta(MapData.ID_KEY, &"")
		(
			assert_bool(id is StringName)
			. override_failure_message("%s: room_id %s is no StringName" % [room.name, id])
			. is_true()
		)
		got.append(str(id))
		# The id is its scene's file name, so a record pasted from another lot fails here.
		assert_str(room.scene_file_path).is_equal(EstateDoc.ROOMS + str(id) + ".tscn")
		assert_str(str(room.get_meta(MapData.NAME_KEY, ""))).is_equal("room." + str(id))
		(
			assert_bool(room.get_meta(MapData.CENTRED_KEY, false) == true)
			. override_failure_message("%s is not marked centred" % room.name)
			. is_true()
		)
	assert_array(got).contains_exactly_in_any_order(expected)
	assert_int(got.size()).is_equal(7)


func test_the_map_screen_draws_each_lot_over_the_doc_s_footprint() -> void:
	var rooms := MapData.rooms_of(_map())
	var by_id: Dictionary[StringName, MapData.Room] = {}
	for room: MapData.Room in rooms:
		by_id[room.id] = room
	for module in EstateDoc.modules():
		if module.size == Vector2i.ZERO:
			continue
		var id := StringName(EstateDoc.snake(module.name))
		assert_bool(by_id.has(id)).override_failure_message("no room %s" % id).is_true()
		if not by_id.has(id):
			continue
		var size := Vector2(module.size)
		assert_that(by_id[id].rect).is_equal(Rect2(module.centre - size / 2.0, size))


func test_a_point_on_a_lot_is_in_that_lot_and_the_open_ground_in_none() -> void:
	# No map-wide room (the plot) swallows the lots: room_at takes the first room in tree order.
	var data := MapData.new()
	data.rooms = MapData.rooms_of(_map())
	for module in EstateDoc.modules():
		var room := data.room_at(module.centre)
		if module.size == Vector2i.ZERO:
			assert_object(room).override_failure_message("%s is in a room" % module.name).is_null()
		else:
			assert_object(room).is_not_null()
			if room != null:
				assert_str(String(room.id)).is_equal(EstateDoc.snake(module.name))


func test_each_name_key_has_english_and_ukrainian_text_or_awaits_the_deck() -> void:
	var translations: Array[Translation] = []
	for locale: String in ["en", "uk"]:
		translations.append(
			load("res://client/i18n/strings.%s.translation" % locale) as Translation
		)
	for room in _rooms_of(_map()):
		var key := str(room.get_meta(MapData.NAME_KEY, ""))
		for translation in translations:
			var text := String(translation.get_message(key))
			var has_text := not text.is_empty() and text != key
			# A key the deck has gained leaves AWAITING_DECK: this fails until it does.
			(
				assert_bool(has_text)
				. override_failure_message(
					(
						"%s: %s %s text in %s"
						% [
							room.name,
							key,
							"has" if has_text else "has no",
							translation.locale,
						]
					)
				)
				. is_equal(not AWAITING_DECK.has(key))
			)


func _map() -> Node3D:
	return auto_free((load(EstateDoc.MAP) as PackedScene).instantiate()) as Node3D


## The map's rooms: the nodes that declare `size_m`, in tree order, none inside another room
## (MapData's rule: the ship lot's art scene declares its own size, #1499).
func _rooms_of(map: Node3D) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for node in map.find_children("*", "Node3D", true, false):
		if not node.has_meta(MapData.SIZE_KEY):
			continue
		if rooms.any(func(around: Node3D) -> bool: return around.is_ancestor_of(node)):
			continue
		rooms.append(node as Node3D)
	return rooms
