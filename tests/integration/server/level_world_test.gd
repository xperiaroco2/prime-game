extends GdUnitTestSuite
## LevelWorld (ARCHITECTURE §4.5, E8): a level scene, instantiated but never added to a tree,
## turned into a World3D.new() of its layer-1 static colliders through PhysicsServer3D, with
## composed transforms; CSG, GridMap and CollisionPolygon3D collision reported (D2 (a)). The
## geometry is read back through HostWorldQuery's rays. Fixture level: see
## host_world_query_test.gd.

const LEVEL := "res://tests/fixtures/levels/wall_ledge_crate.tscn"
const IN_CODE := "res://tests/levels/in_code.tscn"
const NEAR := Vector3(1e-3, 1e-3, 1e-3)


## The probe of §4.5 ("A fresh space"): under Jolt, a space of World3D.new() answers a ray in the
## frame its static body was added, before any physics step, and again after one step. So the
## host needs no physics step between building its worlds and asking them.
func test_a_fresh_space_answers_a_ray_before_and_after_one_physics_step() -> void:
	assert_str(str(ProjectSettings.get_setting("physics/3d/physics_engine"))).is_equal(
		"Jolt Physics"
	)
	var world := World3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 1, 2)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, box.get_rid(), Transform3D.IDENTITY)
	PhysicsServer3D.body_set_state(
		body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))
	)
	PhysicsServer3D.body_set_space(body, world.space)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -5, 0), 1)
	var same_frame := world.direct_space_state.intersect_ray(ray)
	await get_tree().physics_frame
	var after_step := world.direct_space_state.intersect_ray(ray)
	PhysicsServer3D.free_rid(body)
	assert_bool(same_frame.is_empty()).is_false()
	assert_vector(same_frame["position"] as Vector3).is_equal_approx(Vector3.ZERO, NEAR)
	assert_bool(after_step.is_empty()).is_false()
	assert_vector(after_step["position"] as Vector3).is_equal_approx(Vector3.ZERO, NEAR)


func test_the_level_s_layer_1_static_bodies_are_built() -> void:
	var level := LevelWorld.build(LEVEL)
	assert_array(Array(level.errors)).is_empty()
	assert_str(level.path).is_equal(LEVEL)
	# Floor, Wall, Ledge and LowCrate; not GhostsOnly (layer 3) nor Disabled (its only shape is off).
	assert_int(level.body_count()).is_equal(4)
	var query := _query(level)
	assert_float(query.floor_below(Vector3(0, 5, 0)).y).is_equal_approx(0.0, 1e-3)
	assert_float(query.floor_below(Vector3(10, 5, 10)).y).is_equal_approx(0.0, 1e-3)
	assert_float(query.floor_below(Vector3(10, 5, -10)).y).is_equal_approx(0.0, 1e-3)


func test_transforms_are_composed_up_to_the_scene_s_root() -> void:
	var query := _query(LevelWorld.build(LEVEL))
	# The ledge: a body at y = 0.15 in Room, at x = -8: a 4 m square with its top at 0.3.
	assert_float(query.floor_below(Vector3(-8, 5, 0)).y).is_equal_approx(0.3, 1e-3)
	assert_float(query.floor_below(Vector3(-6.1, 5, 1.9)).y).is_equal_approx(0.3, 1e-3)
	assert_float(query.floor_below(Vector3(-5.9, 5, 0)).y).is_equal_approx(0.0, 1e-3)
	# The crate: at (2, 0.25, 0) in Props, turned 90 degrees about y at (0, 0, 8): at (0, _, 6).
	assert_float(query.floor_below(Vector3(0, 5, 6)).y).is_equal_approx(0.5, 1e-3)
	assert_float(query.floor_below(Vector3(2, 5, 8)).y).is_equal_approx(0.0, 1e-3)
	# The wall: its shape 1.5 m up in a body at x = 5: 0.2 m thick, 3 m high.
	assert_bool(query.line_of_sight(Vector3(0, 2.9, 0), Vector3(10, 2.9, 0))).is_false()
	assert_bool(query.line_of_sight(Vector3(0, 3.1, 0), Vector3(10, 3.1, 0))).is_true()
	assert_bool(query.line_of_sight(Vector3(0, 1, 5.1), Vector3(10, 1, 5.1))).is_true()


func test_a_top_level_body_keeps_its_own_transform() -> void:
	var root := _root()
	var room := Node3D.new()
	room.position = Vector3(100, 0, 0)
	root.add_child(room)
	_box_body(room, Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var free_body := _box_body(room, Vector3(3, 1, 3), Vector3(1, 2, 1))
	free_body.top_level = true
	var query := _query(LevelWorld.from_scene(root, IN_CODE))
	assert_float(query.floor_below(Vector3(100, 5, 0)).y).is_equal_approx(1.0, 1e-3)
	assert_float(query.floor_below(Vector3(3, 5, 3)).y).is_equal_approx(2.0, 1e-3)
	assert_vector(query.floor_below(Vector3(103, 5, 3))).is_equal(WorldQuery.NO_FLOOR)


func test_scaled_parents_and_shapes_scale_the_colliders() -> void:
	# A level author scales a piece in the editor: through a parent, or on the shape's node.
	var root := _root()
	var parent := Node3D.new()
	parent.scale = Vector3(2, 2, 2)
	root.add_child(parent)
	_box_body(parent, Vector3(0, 0.5, 0), Vector3(1, 1, 1))
	var stretched := _box_body(root, Vector3(10, 0.5, 0), Vector3(1, 1, 1))
	(stretched.get_child(0) as CollisionShape3D).scale = Vector3(4, 1, 1)
	var query := _query(LevelWorld.from_scene(root, IN_CODE))
	assert_float(query.floor_below(Vector3(0.9, 5, 0)).y).is_equal_approx(2.0, 1e-3)
	assert_vector(query.floor_below(Vector3(1.1, 5, 0))).is_equal(WorldQuery.NO_FLOOR)
	assert_float(query.floor_below(Vector3(11.9, 5, 0)).y).is_equal_approx(1.0, 1e-3)
	assert_vector(query.floor_below(Vector3(12.1, 5, 0))).is_equal(WorldQuery.NO_FLOOR)


func test_csg_gridmap_and_collision_polygons_with_collision_are_reported() -> void:
	var root := _root()
	var csg := CSGBox3D.new()
	csg.name = "SolidCsg"
	csg.use_collision = true
	root.add_child(csg)
	var looks := CSGBox3D.new()
	looks.name = "LooksOnly"
	root.add_child(looks)
	var elsewhere := CSGBox3D.new()
	elsewhere.name = "OtherLayer"
	elsewhere.use_collision = true
	elsewhere.collision_layer = 2
	root.add_child(elsewhere)
	var grid := GridMap.new()
	grid.name = "Tiles"
	grid.mesh_library = MeshLibrary.new()
	grid.mesh_library.create_item(0)
	grid.set_cell_item(Vector3i.ZERO, 0)
	root.add_child(grid)
	var empty_grid := GridMap.new()
	empty_grid.name = "EmptyTiles"
	root.add_child(empty_grid)
	var body := _box_body(root, Vector3.ZERO, Vector3(1, 1, 1))
	body.name = "Body"
	var polygon := CollisionPolygon3D.new()
	polygon.name = "Polygon"
	body.add_child(polygon)
	var level := LevelWorld.from_scene(root, IN_CODE)
	assert_int(level.errors.size()).is_equal(3)
	assert_str(level.errors[0]).contains(IN_CODE).contains("SolidCsg").contains("a CSG node")
	assert_str(level.errors[1]).contains("Tiles").contains("a GridMap")
	assert_str(level.errors[2]).contains("Body/Polygon").contains("a CollisionPolygon3D")
	# The body's box is still read.
	assert_int(level.body_count()).is_equal(1)


func test_a_path_that_is_not_a_scene_is_an_error() -> void:
	var level := LevelWorld.build("res://tests/scratch/no_such_level.tscn")
	assert_int(level.errors.size()).is_equal(1)
	assert_str(level.errors[0]).contains("not a scene")
	assert_int(level.body_count()).is_equal(0)


func test_the_world_outlives_the_scene_it_was_read_from() -> void:
	# The shapes are sub-resources of the scene; the world keeps them after the scene is freed.
	var root := Node3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 1, 4)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)
	var level := LevelWorld.from_scene(root, IN_CODE)
	root.free()
	box = null
	await get_tree().physics_frame
	assert_float(_query(level).floor_below(Vector3(0, 5, 0)).y).is_equal_approx(0.0, 1e-3)


func _query(level: LevelWorld) -> HostWorldQuery:
	var query := HostWorldQuery.new()
	query.add_level(level)
	query.use_level(level.path)
	return query


func _root() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	root.name = "Level"
	return root


func _box_body(parent: Node, center: Vector3, size: Vector3) -> StaticBody3D:
	var box := BoxShape3D.new()
	box.size = size
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)
	return body
