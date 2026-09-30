extends GdUnitTestSuite
## MarkerReader through the host's worlds (ARCHITECTURE §4.5 Starting; §10's reader question,
## option (b) on #66): read_levels points HostWorldQuery at each level before reading it, so each
## level's circle markers snap to that level's own floor. Fixture levels in
## tests/fixtures/levels/ (host_world_query_test.gd describes them), and 2j's flat levels.

const ROOM := "res://tests/fixtures/levels/platform_room.tscn"
const LEVEL := "res://tests/fixtures/levels/wall_ledge_crate.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
const NEAR := Vector3(1e-3, 1e-3, 1e-3)


func test_each_level_s_circles_snap_to_its_own_floor() -> void:
	# Both levels have a circle marker at x 0, z 6: on the room's platform (top 1) and above the
	# level's crate (top 0.5). The other level's world would put each at another height.
	var mode := _mode()
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	var room := levels.layouts[ROOM].positions(&"circle")
	assert_int(room.size()).is_equal(1)
	assert_vector(room[0]).is_equal_approx(Vector3(0, 1, 6), NEAR)
	var level := levels.layouts[LEVEL].positions(&"circle")
	assert_int(level.size()).is_equal(3)
	# On the crate, on the floor from above, and from a hair under the floor.
	assert_vector(level[0]).is_equal_approx(Vector3(0, 0.5, 6), NEAR)
	assert_vector(level[1]).is_equal_approx(Vector3(0, 0, -3), NEAR)
	assert_vector(level[2]).is_equal_approx(Vector3(3, 0, -3), NEAR)
	# A marker that does not stand on the floor is taken as placed.
	assert_array(Array(levels.layouts[LEVEL].positions(&"package"))).is_equal([Vector3(-3, 0.4, 3)])


func test_a_circle_with_no_floor_in_the_host_s_world_is_reported() -> void:
	var root: Node3D = auto_free(Node3D.new())
	root.name = "Level"
	var box := BoxShape3D.new()
	box.size = Vector3(2, 1, 2)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)
	var on := Marker3D.new()
	on.name = "On"
	on.add_to_group(&"spawn_circle", true)
	root.add_child(on)
	var off := Marker3D.new()
	off.name = "Off"
	off.position = Vector3(5, 0, 0)
	off.add_to_group(&"spawn_circle", true)
	root.add_child(off)
	var world := HostWorldQuery.new()
	world.add_level(LevelWorld.from_scene(root, "res://tests/levels/in_code.tscn"))
	world.use_level("res://tests/levels/in_code.tscn")
	var floor_tags: Array[StringName] = [&"circle"]
	var result := MarkerReader.read(root, "res://tests/levels/in_code.tscn", world, floor_tags)
	assert_int(result.errors.size()).is_equal(1)
	assert_str(result.errors[0]).contains("Off").contains("not on a floor")
	var circles := result.layout.positions(&"circle")
	assert_int(circles.size()).is_equal(1)
	assert_vector(circles[0]).is_equal_approx(Vector3.ZERO, NEAR)


func test_2j_s_flat_levels_read_the_same_as_with_the_flat_fake() -> void:
	var mode := load(BASE_MODE) as GameMode
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var host := MarkerReader.read_levels(mode, world)
	var flat := MarkerReader.read_levels(mode, FlatWorldQuery.new())
	assert_array(Array(host.errors)).is_empty()
	assert_array(host.layouts.keys()).is_equal(flat.layouts.keys())
	for path: String in flat.layouts:
		var want := flat.layouts[path]
		var got := host.layouts[path]
		assert_array(got.tags()).is_equal(want.tags())
		for tag: StringName in want.tags():
			var wanted := want.positions(tag)
			var found := got.positions(tag)
			assert_int(found.size()).is_equal(wanted.size())
			for i: int in wanted.size():
				assert_vector(found[i]).is_equal_approx(wanted[i], NEAR)
	assert_int(host.layouts[mode.maps[0]].count(&"circle")).is_greater(0)


func _mode() -> GameMode:
	var mode := GameMode.new()
	var delivery := Delivery.new()
	delivery.circle = StationKind.new()
	delivery.circle.spawn_tag = &"circle"
	mode.task_types = [delivery]
	mode.lobby_level = ROOM
	mode.maps = PackedStringArray([LEVEL])
	return mode
