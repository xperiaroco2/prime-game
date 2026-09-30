extends GdUnitTestSuite
## MarkerReader (ARCHITECTURE §9.6): Marker3D nodes in one `spawn_<tag>` group, read in scene-tree
## order into a LevelLayout; load errors for a marker in two groups and for a spawn group on
## another node; floor-standing markers (circles) snapped to the floor below, or reported when
## there is none (the engineer's answer on #82, item 3). Scenes built in code: a part's test never
## loads levels/ (§9.6); the real levels are read by the content test.

const LEVEL := "res://levels/test_level.tscn"


func test_markers_are_read_by_tag_in_scene_tree_order() -> void:
	var root := _root()
	_marker(root, "B", &"spawn_package", Vector3(2, 0, 0))
	var room := Node3D.new()
	room.name = "Room"
	room.position = Vector3(100, 0, 0)
	root.add_child(room)
	_marker(room, "Inner", &"spawn_package", Vector3(1, 0, 1))
	_marker(root, "A", &"spawn_package", Vector3(-5, 0, 0))
	_marker(root, "Spawn", &"spawn_round_player", Vector3(0, 0, 3))
	var plain := Marker3D.new()
	root.add_child(plain)
	var result := MarkerReader.read(root, LEVEL, FlatWorldQuery.new())
	assert_array(Array(result.errors)).is_empty()
	assert_str(result.layout.path).is_equal(LEVEL)
	assert_array(result.layout.tags()).is_equal([&"package", &"round_player"])
	# Scene-tree order, not name order; a child through its parent's transform.
	assert_array(Array(result.layout.positions(&"package"))).is_equal(
		[Vector3(2, 0, 0), Vector3(101, 0, 1), Vector3(-5, 0, 0)]
	)
	assert_array(Array(result.layout.positions(&"round_player"))).is_equal([Vector3(0, 0, 3)])


func test_a_rotated_parent_moves_its_markers() -> void:
	var root := _root()
	var turned := Node3D.new()
	turned.rotation_degrees = Vector3(0, 90, 0)
	turned.position = Vector3(10, 0, 0)
	root.add_child(turned)
	_marker(turned, "M", &"spawn_knife", Vector3(1, 0, 0))
	var at := MarkerReader.read(root, LEVEL, FlatWorldQuery.new()).layout.positions(&"knife")[0]
	assert_vector(at).is_equal_approx(Vector3(10, 0, -1), Vector3(1e-5, 1e-5, 1e-5))


func test_a_top_level_node_and_the_nodes_above_the_root_do_not_move_markers() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	holder.position = Vector3(50, 0, 0)
	var root := Node3D.new()
	root.position = Vector3(0, 0, 7)
	holder.add_child(root)
	var room := Node3D.new()
	room.position = Vector3(100, 0, 0)
	root.add_child(room)
	var free_room := Node3D.new()
	free_room.top_level = true
	free_room.position = Vector3(3, 0, 3)
	room.add_child(free_room)
	_marker(free_room, "Free", &"spawn_knife", Vector3(1, 0, 0))
	_marker(room, "Held", &"spawn_knife", Vector3(1, 0, 0))
	var at := MarkerReader.read(root, LEVEL, FlatWorldQuery.new()).layout.positions(&"knife")
	assert_array(Array(at)).is_equal([Vector3(4, 0, 3), Vector3(101, 0, 7)])


func test_a_marker_in_two_spawn_groups_is_a_load_error() -> void:
	var root := _root()
	var both := _marker(root, "Both", &"spawn_package", Vector3(1, 0, 0))
	both.add_to_group(&"spawn_knife", true)
	both.add_to_group(&"decor", true)
	_marker(root, "One", &"spawn_knife", Vector3(2, 0, 0))
	var result := MarkerReader.read(root, LEVEL, FlatWorldQuery.new())
	assert_int(result.errors.size()).is_equal(1)
	assert_str(result.errors[0]).contains("Both").contains("2 spawn groups")
	# It is left out; the others are read.
	assert_int(result.layout.count(&"package")).is_equal(0)
	assert_array(Array(result.layout.positions(&"knife"))).is_equal([Vector3(2, 0, 0)])


func test_a_spawn_group_on_another_node_or_without_a_tag_is_a_load_error() -> void:
	var root := _root()
	var box := Node3D.new()
	box.name = "Box"
	box.add_to_group(&"spawn_package", true)
	root.add_child(box)
	_marker(root, "Nameless", &"spawn_", Vector3.ZERO)
	var result := MarkerReader.read(root, LEVEL, FlatWorldQuery.new())
	assert_int(result.errors.size()).is_equal(2)
	assert_str(result.errors[0]).contains("Box").contains("not a Marker3D")
	assert_str(result.errors[1]).contains("Nameless").contains("names no tag")
	assert_array(result.layout.tags()).is_empty()


func test_floor_markers_are_snapped_to_the_floor_below() -> void:
	# A circle marker placed above the floor (or a hair below it) stands on it after the read; a
	# package marker is taken as placed.
	var root := _root()
	_marker(root, "High", &"spawn_circle", Vector3(1, 0.4, 1))
	_marker(root, "Low", &"spawn_circle", Vector3(2, -0.05, 2))
	_marker(root, "Package", &"spawn_package", Vector3(3, 0.4, 3))
	var floor_tags: Array[StringName] = [&"circle"]
	var result := MarkerReader.read(root, LEVEL, FlatWorldQuery.new(), floor_tags)
	assert_array(Array(result.errors)).is_empty()
	assert_array(Array(result.layout.positions(&"circle"))).is_equal(
		[Vector3(1, 0, 1), Vector3(2, 0, 2)]
	)
	assert_array(Array(result.layout.positions(&"package"))).is_equal([Vector3(3, 0.4, 3)])


func test_a_floor_marker_with_no_floor_below_is_reported() -> void:
	var root := _root()
	_marker(root, "Sunk", &"spawn_circle", Vector3(1, -2, 1))
	var floor_tags: Array[StringName] = [&"circle"]
	var result := MarkerReader.read(root, LEVEL, FlatWorldQuery.new(), floor_tags)
	assert_int(result.errors.size()).is_equal(1)
	assert_str(result.errors[0]).contains("Sunk").contains("not on a floor")
	assert_int(result.layout.count(&"circle")).is_equal(0)


func test_floor_tags_are_the_spawn_tags_of_the_mode_s_stations() -> void:
	var mode := GameMode.new()
	var delivery := Delivery.new()
	delivery.circle = StationKind.new()
	delivery.circle.spawn_tag = &"circle"
	mode.task_types = [delivery, Delivery.new()]
	assert_array(MarkerReader.floor_tags_of(mode)).is_equal([&"circle"])
	assert_array(MarkerReader.floor_tags_of(GameMode.new())).is_empty()


func test_read_levels_points_the_world_at_each_level_before_reading_it() -> void:
	# The host's worlds answer for the level they are pointed at (§4.5 Starting): the lobby, then
	# each map once, each named before its circle markers ask for their floor.
	var room := "res://tests/fixtures/levels/platform_room.tscn"
	var level := "res://tests/fixtures/levels/wall_ledge_crate.tscn"
	var mode := GameMode.new()
	var delivery := Delivery.new()
	delivery.circle = StationKind.new()
	delivery.circle.spawn_tag = &"circle"
	mode.task_types = [delivery]
	mode.lobby_level = room
	mode.maps = PackedStringArray([level, room])
	assert_array(MarkerReader.level_paths_of(mode)).is_equal([room, level])
	var world := FixtureLevelWorld.new()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	assert_array(levels.layouts.keys()).is_equal([room, level])
	(
		assert_array(Array(world.calls))
		. is_equal(
			[
				"use_level %s" % room,
				"floor_below",
				"use_level %s" % level,
				"floor_below",
				"floor_below",
				"floor_below",
			]
		)
	)


func test_a_missing_scene_is_a_load_error() -> void:
	var result := MarkerReader.read_scene(
		"res://tests/scratch/no_such_level.tscn", FlatWorldQuery.new()
	)
	assert_str(result.errors[0]).contains("not a scene")
	assert_array(result.layout.tags()).is_empty()


func _root() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	root.name = "Level"
	return root


func _marker(parent: Node, marker_name: String, group: StringName, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	marker.add_to_group(group, true)
	parent.add_child(marker)
	return marker
