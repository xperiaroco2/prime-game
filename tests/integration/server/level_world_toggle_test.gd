extends GdUnitTestSuite
## LevelWorld's world toggles (#1295, ARCHITECTURE §4.5.9): a StaticBody3D in group
## `toggle_<key>` with the int metadata `toggle_index` is a part of toggle (key, index). A
## collider leaves the space while its toggle is on; a mover (a child Marker3D OnPose) stands at
## its OnPose instead. Read back through HostWorldQuery's rays with no physics step in between:
## the swap only adds and removes bodies, which an unstepped space sees at once (the probe in
## level_world_test.gd).

const IN_CODE := "res://tests/levels/in_code.tscn"


func test_a_collider_is_solid_while_off_and_gone_while_on() -> void:
	var query := _query(_level())
	assert_bool(_cover_0_clear(query)).is_false()
	query.set_toggle(&"cover", 0, true)
	assert_bool(_cover_0_clear(query)).is_true()
	query.set_toggle(&"cover", 0, false)
	assert_bool(_cover_0_clear(query)).is_false()


func test_only_the_named_index_and_key_change() -> void:
	var query := _query(_level())
	query.set_toggle(&"cover", 0, true)
	assert_bool(_cover_1_clear(query)).is_false()
	assert_bool(_bookcase_closed(query)).is_true()
	query.set_toggle(&"cover", 7, true)
	query.set_toggle(&"nothing", 0, true)
	assert_bool(_cover_1_clear(query)).is_false()


func test_a_mover_stands_at_its_on_pose_while_on() -> void:
	var query := _query(_level())
	# Off: the scene pose (x = 10) blocks, the OnPose (x = 12) is open.
	assert_bool(query.line_of_sight(Vector3(12, 1, -3), Vector3(12, 1, 3))).is_true()
	assert_bool(_bookcase_closed(query)).is_true()
	query.set_toggle(&"bookcase", 0, true)
	assert_bool(_bookcase_closed(query)).is_false()
	assert_bool(query.line_of_sight(Vector3(12, 1, -3), Vector3(12, 1, 3))).is_false()
	query.set_toggle(&"bookcase", 0, false)
	assert_bool(_bookcase_closed(query)).is_true()
	assert_bool(query.line_of_sight(Vector3(12, 1, -3), Vector3(12, 1, 3))).is_true()


func test_every_part_of_one_toggle_follows_it() -> void:
	var query := _query(_level())
	assert_bool(_bookcase_wall_clear(query)).is_false()
	query.set_toggle(&"bookcase", 0, true)
	assert_bool(_bookcase_wall_clear(query)).is_true()


func test_reset_stands_every_part_as_the_scene_does() -> void:
	var query := _query(_level())
	query.set_toggle(&"cover", 0, true)
	query.set_toggle(&"cover", 1, true)
	query.set_toggle(&"bookcase", 0, true)
	query.reset_toggles()
	assert_bool(_cover_0_clear(query)).is_false()
	assert_bool(_cover_1_clear(query)).is_false()
	assert_bool(_bookcase_closed(query)).is_true()
	assert_bool(_bookcase_wall_clear(query)).is_false()
	assert_bool(query.line_of_sight(Vector3(12, 1, -3), Vector3(12, 1, 3))).is_true()


func test_parts_are_counted_and_the_on_pose_body_is_not_a_level_body() -> void:
	var level := _level()
	assert_array(Array(level.errors)).is_empty()
	# Floor, two covers, the bookcase and its wall; the bookcase's OnPose body is not counted.
	assert_int(level.body_count()).is_equal(5)
	assert_int(level.toggle_part_count()).is_equal(4)


func test_a_toggle_with_no_level_is_nothing() -> void:
	var query := HostWorldQuery.new()
	query.set_toggle(&"cover", 0, true)
	query.reset_toggles()
	assert_str(query.level_path()).is_empty()


func test_a_part_without_an_int_index_or_in_two_groups_is_an_error() -> void:
	var root := _root()
	_box(root, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var no_index := _box(root, Vector3(0, 1, 0), Vector3.ONE)
	no_index.name = "NoIndex"
	no_index.add_to_group(&"toggle_cover", true)
	var text_index := _box(root, Vector3(3, 1, 0), Vector3.ONE)
	text_index.name = "TextIndex"
	text_index.add_to_group(&"toggle_cover", true)
	text_index.set_meta(StationKind.TOGGLE_INDEX_META, "0")
	var two := _part(root, &"cover", 0, Vector3(6, 1, 0))
	two.name = "TwoGroups"
	two.add_to_group(&"toggle_bookcase", true)
	var level := LevelWorld.from_scene(root, IN_CODE)
	assert_int(level.errors.size()).is_equal(3)
	assert_str(level.errors[0]).contains("NoIndex").contains("toggle_index")
	assert_str(level.errors[1]).contains("TextIndex").contains("toggle_index")
	assert_str(level.errors[2]).contains("TwoGroups").contains("two toggle groups")
	assert_int(level.toggle_part_count()).is_equal(0)


# A floor; covers 0 (x = 0) and 1 (z = 10); the bookcase (key bookcase, index 0): a mover at
# x = 10 whose OnPose is 2 m along x, and a plain wall at (10, _, 5) of the same toggle.
func _level() -> LevelWorld:
	var root := _root()
	_box(root, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_part(root, &"cover", 0, Vector3(0, 1, 0))
	_part(root, &"cover", 1, Vector3(0, 1, 10))
	var mover := _part(root, &"bookcase", 0, Vector3(10, 1, 0))
	var on_pose := Marker3D.new()
	on_pose.name = StationKind.ON_POSE
	on_pose.position = Vector3(2, 0, 0)
	mover.add_child(on_pose)
	_part(root, &"bookcase", 0, Vector3(10, 1, 5))
	return LevelWorld.from_scene(root, IN_CODE)


func _cover_0_clear(query: HostWorldQuery) -> bool:
	return query.line_of_sight(Vector3(-3, 1, 0), Vector3(3, 1, 0))


func _cover_1_clear(query: HostWorldQuery) -> bool:
	return query.line_of_sight(Vector3(-3, 1, 10), Vector3(3, 1, 10))


func _bookcase_closed(query: HostWorldQuery) -> bool:
	return not query.line_of_sight(Vector3(10, 1, -3), Vector3(10, 1, 3))


func _bookcase_wall_clear(query: HostWorldQuery) -> bool:
	return query.line_of_sight(Vector3(10, 1, 3), Vector3(10, 1, 8))


func _query(level: LevelWorld) -> HostWorldQuery:
	var query := HostWorldQuery.new()
	query.add_level(level)
	query.use_level(level.path)
	return query


func _root() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	root.name = "Level"
	return root


func _part(parent: Node, key: StringName, index: int, center: Vector3) -> StaticBody3D:
	var body := _box(parent, center, Vector3.ONE)
	body.add_to_group(StringName(StationKind.TOGGLE_GROUP_PREFIX + key), true)
	body.set_meta(StationKind.TOGGLE_INDEX_META, index)
	return body


func _box(parent: Node, center: Vector3, size: Vector3) -> StaticBody3D:
	var box := BoxShape3D.new()
	box.size = size
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)
	return body
