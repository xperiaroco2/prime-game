extends GdUnitTestSuite
## The map screen's data (MapData, #253): the rooms of a level by PR #611's convention (a Node3D
## with `metadata/size_m`, its origin the north-west corner, plan x = X, plan y = Z) and each task
## type's zones: the rooms that hold a marker of one of its item spawn tags, never a circle's or a
## spawn point's, and never from the model. The level is built in code (the preview's fake house).

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const GREYBOX := "res://levels/greybox/greybox.tscn"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_rooms_come_from_the_size_metadata_in_tree_order_with_their_ids() -> void:
	var level: Node3D = auto_free(Node3D.new())
	var wing := Node3D.new()
	wing.position = Vector3(100, 0, 0)
	level.add_child(wing)
	_room(wing, "Storage", Vector3(-10, 0, -8), Vector2i(6, 4))
	var named := _room(level, "SomeNode", Vector3(2, 3.2, 5), Vector2(3, 2))
	named.set_meta(MapData.ID_KEY, &"lab")
	var plain := Node3D.new()
	level.add_child(plain)
	var data := MapData.from_level(level, _mode)
	assert_int(data.rooms.size()).is_equal(2)
	assert_str(String(data.rooms[0].id)).is_equal("storage")
	# Through its parents, the level's height dropped: x = X, y = Z.
	assert_that(data.rooms[0].rect).is_equal(Rect2(90, -8, 6, 4))
	assert_str(String(data.rooms[1].id)).is_equal("lab")
	assert_that(data.rooms[1].rect).is_equal(Rect2(2, 5, 3, 2))


func test_a_task_types_zones_are_the_rooms_holding_a_marker_of_its_items_tag() -> void:
	var level: Node3D = auto_free(Preview.fake_level())
	var data := MapData.from_level(level, _mode)
	# The fake house: the packages' markers lie in the storage and the lab; a circle's marker in the
	# kitchen and the round's spawn points in the hall light nothing.
	assert_array(Array(data.zone_of(&"delivery"))).contains_exactly(["storage", "lab"])
	assert_array(Array(data.zone_of(&"switches"))).is_empty()
	# A package marker in no room makes no zone, and a moved item changes nothing: zones are
	# level data, read once.
	var stray := Marker3D.new()
	stray.position = Vector3(500, 0, 500)
	stray.add_to_group(&"spawn_package", true)
	level.add_child(stray)
	assert_array(Array(MapData.from_level(level, _mode).zone_of(&"delivery"))).contains_exactly(
		["storage", "lab"]
	)


func test_a_level_without_rooms_or_no_level_draws_nothing() -> void:
	assert_array(MapData.from_level(null, _mode).rooms).is_empty()
	var empty: Node3D = auto_free(Node3D.new())
	var data := MapData.from_level(empty, _mode)
	assert_array(data.rooms).is_empty()
	assert_array(Array(data.zone_of(&"delivery"))).is_empty()
	assert_that(data.bounds()).is_equal(Rect2())
	assert_float(data.scale_for(Vector2(800, 600))).is_equal(0.0)


func test_every_room_of_the_greybox_has_an_area() -> void:
	# Holds before #306 (no room) and after it (rooms): a room with no area could draw nothing.
	var level: Node = auto_free((load(GREYBOX) as PackedScene).instantiate())
	for room: MapData.Room in MapData.rooms_of(level):
		(
			assert_bool(room.rect.has_area())
			. override_failure_message("the room %s of the greybox has no area" % room.id)
			. is_true()
		)


func test_the_spawn_group_prefix_is_the_host_readers() -> void:
	# client/ may not name MarkerReader, so MapData copies its prefix; a change there would
	# silently light no zone while the tests above, which use the literal group, stay green.
	assert_str(MapData.SPAWN_GROUP_PREFIX).is_equal(MarkerReader.GROUP_PREFIX)


func test_a_room_repeating_an_id_is_left_out() -> void:
	var level: Node3D = auto_free(Node3D.new())
	_room(level, "Hall", Vector3.ZERO, Vector2i(4, 4))
	var wing := Node3D.new()
	level.add_child(wing)
	_room(wing, "Hall", Vector3(10, 0, 0), Vector2i(4, 4))
	var copy := _room(level, "Other", Vector3(20, 0, 0), Vector2i(4, 4))
	copy.set_meta(MapData.ID_KEY, &"hall")
	var rooms := MapData.rooms_of(level)
	assert_int(rooms.size()).is_equal(1)
	assert_that(rooms[0].rect).is_equal(Rect2(0, 0, 4, 4))


func test_a_marker_is_placed_as_the_hosts_reader_places_it() -> void:
	# A level root off the origin counts; a top_level holder is placed by its own transform alone
	# (LevelWorld.transform_in_scene); a marker in two spawn groups is the reader's load error.
	var level: Node3D = auto_free(Node3D.new())
	level.position = Vector3(100, 0, 0)
	_room(level, "Left", Vector3.ZERO, Vector2i(10, 10))
	_room(level, "Right", Vector3(100, 0, 0), Vector2i(10, 10))
	var holder := Node3D.new()
	holder.top_level = true
	holder.position = Vector3(4, 0, 3)
	level.add_child(holder)
	var marker := Marker3D.new()
	marker.add_to_group(&"spawn_package", true)
	holder.add_child(marker)
	var data := MapData.from_level(level, _mode)
	# The root's X of 100 puts "Left" at 100..110 and "Right" at 200..210; the top_level holder at
	# (4, 3) lies in neither, so it lights nothing, as the host spawns the package at (4, 0, 3).
	assert_that(data.rooms[0].rect).is_equal(Rect2(100, 0, 10, 10))
	assert_array(Array(data.zone_of(&"delivery"))).is_empty()
	holder.top_level = false
	holder.position = Vector3(4, 0, 3)
	assert_array(Array(MapData.from_level(level, _mode).zone_of(&"delivery"))).contains_exactly(
		["left"]
	)
	marker.add_to_group(&"spawn_other", true)
	assert_array(Array(MapData.from_level(level, _mode).zone_of(&"delivery"))).is_empty()


func test_the_board_fits_the_rooms_centred_with_one_scale() -> void:
	var level: Node3D = auto_free(Preview.fake_level())
	var data := MapData.from_level(level, _mode)
	var board := Vector2(900, 600)
	var scale := data.scale_for(board)
	assert_float(scale).is_greater(0.0)
	var area := data.bounds()
	var top_left := data.to_board(area.position, board)
	var bottom_right := data.to_board(area.end, board)
	# Centred: the same gap on both sides of each axis, and every corner inside the margin.
	assert_float(top_left.x).is_equal_approx(board.x - bottom_right.x, 0.001)
	assert_float(top_left.y).is_equal_approx(board.y - bottom_right.y, 0.001)
	var margin := MapData.MARGIN * minf(board.x, board.y)
	assert_bool(top_left.x >= margin - 0.001 and top_left.y >= margin - 0.001).is_true()
	# One scale: a metre is as long on both axes.
	var east := data.to_board(area.position + Vector2(1, 0), board) - top_left
	var south := data.to_board(area.position + Vector2(0, 1), board) - top_left
	assert_float(east.x).is_equal_approx(south.y, 0.001)
	assert_that(data.room_at(Vector2(-15, -12)).id).is_equal(&"storage")
	assert_object(data.room_at(Vector2(500, 500))).is_null()


func _room(parent: Node, room_name: String, corner: Vector3, size: Variant) -> Node3D:
	var room := Node3D.new()
	room.name = room_name
	room.position = corner
	room.set_meta(MapData.SIZE_KEY, size)
	parent.add_child(room)
	return room
