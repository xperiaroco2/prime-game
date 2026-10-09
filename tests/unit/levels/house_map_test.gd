extends GdUnitTestSuite
## The House map against its design doc (docs/design/house-map.md §4, the room tables): every room
## the doc lists is placed at its (x, level height, y) with no rotation and its size, as its own
## scene, its collision stays inside that size, and the map places nothing else
## (docs/decisions/2026-10-09-level-piece-conventions.md).

const MAP := "res://levels/house/house.tscn"
const DOC := "res://docs/design/house-map.md"
const ROOMS := "res://levels/house/rooms/"
const NEAR := Vector3(1e-3, 1e-3, 1e-3)
## How far a collision box may reach past its room's bounds: rounding only.
const SLACK := 1e-3


## One row of the doc's room tables.
class DocRoom:
	var name: String
	var position: Vector3
	var size: Vector2i

	func _init(room_name: String, at: Vector3, dims: Vector2i) -> void:
		name = room_name
		position = at
		size = dims


func test_the_doc_s_room_rows_all_parse_on_four_levels() -> void:
	var rooms := _doc_rooms()
	(
		assert_int(rooms.size())
		. override_failure_message(
			"§4 has %d room rows but %d parse" % [_doc_row_count(), rooms.size()]
		)
		. is_equal(_doc_row_count())
	)
	var levels: Array[int] = []
	for room in rooms:
		var level := roundi(room.position.y / 3.2)
		if level not in levels:
			levels.append(level)
	assert_array(levels).contains_exactly_in_any_order([-1, 0, 1, 2])


func test_each_room_of_the_doc_is_placed_at_its_position_with_its_size() -> void:
	var map := _map()
	var placed := _placed(map)
	for room in _doc_rooms():
		var node: Node3D = placed.get(_pascal(room.name))
		(
			assert_object(node)
			. override_failure_message("no room %s in the map" % room.name)
			. is_not_null()
		)
		if node == null:
			continue
		var at := LevelWorld.transform_in_scene(node, map)
		(
			assert_vector(at.origin)
			. override_failure_message(
				"%s is at %s, the doc says %s" % [room.name, at.origin, room.position]
			)
			. is_equal_approx(room.position, NEAR)
		)
		(
			assert_bool(at.basis.is_equal_approx(Basis.IDENTITY))
			. override_failure_message("%s is rotated or scaled" % room.name)
			. is_true()
		)
		var size: Variant = node.get_meta(&"size_m")
		(
			assert_object(size)
			. override_failure_message(
				"%s: size_m %s, the doc says %s" % [room.name, size, room.size]
			)
			. is_equal(room.size)
		)
		assert_str(node.scene_file_path).is_equal(ROOMS + _snake(room.name) + ".tscn")


func test_the_map_places_only_the_doc_s_rooms_each_once() -> void:
	var names: Array[String] = []
	for node in _rooms_of(_map()):
		names.append(String(node.name))
	var listed: Array[String] = []
	for room in _doc_rooms():
		listed.append(_pascal(room.name))
	assert_array(names).contains_exactly_in_any_order(listed)


func test_each_room_s_collision_stays_inside_its_size() -> void:
	for room in _rooms_of(_map()):
		var size: Vector2i = room.get_meta(&"size_m")
		for shape in room.find_children("*", "CollisionShape3D", true, false):
			var box := (shape as CollisionShape3D).shape as BoxShape3D
			(
				assert_object(box)
				. override_failure_message("%s/%s is not a box" % [room.name, shape.name])
				. is_not_null()
			)
			if box == null:
				continue
			# transform_in_scene counts the room's own place on the map: undo it for the room's frame.
			var in_map := LevelWorld.transform_in_scene(shape as Node3D, room)
			var local := room.transform.affine_inverse() * in_map
			var aabb := local * AABB(-box.size / 2, box.size)
			var inside := (
				aabb.position.x >= -SLACK
				and aabb.position.z >= -SLACK
				and aabb.end.x <= size.x + SLACK
				and aabb.end.z <= size.y + SLACK
			)
			(
				assert_bool(inside)
				. override_failure_message(
					"%s/%s reaches %s, past its %s m" % [room.name, shape.name, aabb, size]
				)
				. is_true()
			)


func _map() -> Node3D:
	return auto_free((load(MAP) as PackedScene).instantiate()) as Node3D


## The map's rooms: the nodes that declare `size_m`.
func _rooms_of(map: Node3D) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for node in map.find_children("*", "Node3D", true, false):
		if node.has_meta(&"size_m"):
			rooms.append(node as Node3D)
	return rooms


## The rooms by name; a name placed twice fails the test.
func _placed(map: Node3D) -> Dictionary[String, Node3D]:
	var by_name: Dictionary[String, Node3D] = {}
	for room in _rooms_of(map):
		(
			assert_bool(by_name.has(String(room.name)))
			. override_failure_message("two rooms named %s" % room.name)
			. is_false()
		)
		by_name[String(room.name)] = room
	return by_name


## The rows of §4's room tables, each at its level's height: -3.2, 0, 3.2 and 6.4 m.
func _doc_rooms() -> Array[DocRoom]:
	var rooms: Array[DocRoom] = []
	var heading := RegEx.create_from_string("^### Level (-?\\d+)")
	var row := RegEx.create_from_string(
		"^\\| ([^|]+?) \\| (-?[\\d.]+), (-?[\\d.]+) \\| (\\d+) x (\\d+) m \\|"
	)
	var level := 0
	for line in _section_4():
		var h := heading.search(line)
		if h != null:
			level = int(h.get_string(1))
		var m := row.search(line)
		if m != null:
			var at := Vector3(float(m.get_string(2)), level * 3.2, float(m.get_string(3)))
			var size := Vector2i(int(m.get_string(4)), int(m.get_string(5)))
			rooms.append(DocRoom.new(m.get_string(1), at, size))
	return rooms


## The table rows of §4 that are not a header or a rule: each must be a room.
func _doc_row_count() -> int:
	var count := 0
	for line in _section_4():
		if line.begins_with("| ") and not line.begins_with("| Room |"):
			count += 1
	return count


func _section_4() -> PackedStringArray:
	var lines := PackedStringArray()
	var inside := false
	for line in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			inside = line.begins_with("## 4.")
		elif inside:
			lines.append(line)
	return lines


func _words(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in RegEx.create_from_string("[A-Za-z0-9]+").search_all(name):
		out.append(m.get_string())
	return out


func _pascal(name: String) -> String:
	var out := ""
	for w in _words(name):
		out += w.substr(0, 1).to_upper() + w.substr(1)
	return out


func _snake(name: String) -> String:
	var out := PackedStringArray()
	for w in _words(name):
		out.append(w.to_lower())
	return "_".join(out)
