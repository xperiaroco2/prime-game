extends GdUnitTestSuite
## The House's room records (#306): every room of the House (a node with `metadata/size_m`) carries
## its record on its own scene's root: an id (`metadata/room_id`), unique on the map, and a name
## (`metadata/name_key`), a copy deck key with English and Ukrainian text; the map screen's
## MapData reads each record as it stands. house_map_test.gd ties the rooms to the design doc.

const MAP := "res://levels/house/house.tscn"
const ROOMS := "res://levels/house/rooms/"
## The House's rooms (docs/design/house-map.md §4, the issue's 35).
const ROOM_COUNT := 35


func test_every_house_room_has_a_record_with_a_unique_id() -> void:
	var ids: Array[StringName] = []
	for room in _rooms_of(_map()):
		(
			assert_bool(room.has_meta(MapData.ID_KEY))
			. override_failure_message("%s has no %s" % [room.name, MapData.ID_KEY])
			. is_true()
		)
		var id: Variant = room.get_meta(MapData.ID_KEY, &"")
		(
			assert_bool(id is StringName and not (id as StringName).is_empty())
			. override_failure_message("%s: room_id %s is no StringName" % [room.name, id])
			. is_true()
		)
		(
			assert_bool(ids.has(id))
			. override_failure_message("%s repeats the id %s" % [room.name, id])
			. is_false()
		)
		ids.append(StringName(str(id)))
		# Each id is its room scene's file name today (the deck's keys follow them, ui-0.6.0), so a
		# record pasted from another room fails here.
		(
			assert_str(room.scene_file_path)
			. override_failure_message("%s: id %s" % [room.scene_file_path, id])
			. is_equal(ROOMS + str(id) + ".tscn")
		)
	assert_int(ids.size()).is_equal(ROOM_COUNT)


func test_every_house_room_s_name_key_has_english_and_ukrainian_text() -> void:
	var translations: Array[Translation] = []
	for locale: String in ["en", "uk"]:
		translations.append(
			load("res://client/i18n/strings.%s.translation" % locale) as Translation
		)
	var named := 0
	for room in _rooms_of(_map()):
		var key: Variant = room.get_meta(MapData.NAME_KEY, "")
		(
			assert_bool(key is String and not (key as String).is_empty())
			. override_failure_message("%s has no %s" % [room.name, MapData.NAME_KEY])
			. is_true()
		)
		for translation in translations:
			var text := String(translation.get_message(str(key)))
			var failure := "%s: %s has no %s text" % [room.name, key, translation.locale]
			assert_str(text).override_failure_message(failure).is_not_empty()
			assert_str(text).override_failure_message(failure).is_not_equal(str(key))
		named += 1
	assert_int(named).is_equal(ROOM_COUNT)


func test_the_map_screen_reads_each_record_as_it_stands() -> void:
	var map := _map()
	var read := MapData.rooms_of(map)
	var expected: Array[String] = []
	for room in _rooms_of(map):
		expected.append(
			"%s %s" % [room.get_meta(MapData.ID_KEY, ""), room.get_meta(MapData.NAME_KEY, "")]
		)
	var got: Array[String] = []
	for room: MapData.Room in read:
		got.append("%s %s" % [room.id, room.name_key])
	assert_array(got).contains_exactly(expected)


func _map() -> Node3D:
	return auto_free((load(MAP) as PackedScene).instantiate()) as Node3D


## The map's rooms: the nodes that declare `size_m`, in tree order.
func _rooms_of(map: Node3D) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for node in map.find_children("*", "Node3D", true, false):
		if node.has_meta(MapData.SIZE_KEY):
			rooms.append(node as Node3D)
	return rooms
