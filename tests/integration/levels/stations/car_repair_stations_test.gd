extends GdUnitTestSuite
## The car repair's station scenes (#809, R5; the car repair ADR's RE8 and RE16), the ones whose
## shape the station-scene suite's single front use spot does not fit: the car, its use spot
## under the car (RE16's exception), its body an AnimatableBody3D on the client-only layer 4
## (`movers`, bit value 8) with no top a player can stand on and its lowest point under
## `clearance_m`, so R7's raise always lifts it; the lift's static frame on layer 1, clear of the
## use spot; the panel's light dark by default; the parts shelf with one bin per part kind (RD2's
## 3, a placeholder), each bin its own use spot and picture; the part picture, a frame on a wall
## with a hidden plate the client fills and no collision of its own. The lift panel's use spot and
## collision are station_scenes_test.gd's.

const CAR := "res://levels/stations/car.tscn"
const LIFT_PANEL := "res://levels/stations/lift_panel.tscn"
const PARTS_SHELF := "res://levels/stations/parts_shelf.tscn"
const PART_PICTURE := "res://levels/stations/part_picture.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The car's body layer: layer 4, `movers` (RE8), bit value 8.
const MOVERS := 8
## RD2's placeholders ("not a decision"): the raised underside's height, the footprint's
## half-length (the use spot to `car_end`) and the number of part kinds (bins).
const CLEARANCE_M := 1.4
const HALF_LENGTH_M := 2.3
const BINS := 3
## How far above a jump's reach (jump height plus step height) the car's top stands, so no
## player lands on it (RE8: no top to stand on).
const TOP_MARGIN_M := 0.2
const NEAR := 1e-3
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05


func test_the_car_s_body_is_an_animatable_body_on_layer_4() -> void:
	var lift := _scene(CAR).get_node_or_null("Lift") as AnimatableBody3D
	assert_object(lift).override_failure_message("no Lift AnimatableBody3D").is_not_null()
	if lift == null:
		return
	assert_int(lift.collision_layer).is_equal(MOVERS)
	assert_bool(lift.sync_to_physics).is_true()
	var shapes := lift.find_children("*", "CollisionShape3D", false, false)
	assert_int(shapes.size()).is_equal(1)
	assert_object((lift.get_node("Hull") as CollisionShape3D).shape).is_instanceof(BoxShape3D)


func test_the_car_s_body_has_no_top_to_stand_on_and_its_underside_under_the_clearance() -> void:
	var rules := (load(BASE_MODE) as GameMode).player_rules
	var hull := _scene(CAR).get_node("Lift/Hull") as CollisionShape3D
	var half := (hull.shape as BoxShape3D).size.y / 2.0
	var lowest := hull.position.y - half
	var top := hull.position.y + half
	# Above the floor and under clearance_m: R7 raises the lowest point to clearance_m.
	assert_float(lowest).is_greater(0.0)
	assert_float(lowest).is_less(CLEARANCE_M)
	# Beyond a jump's reach: a box's top is flat, so it must stand too high to land on.
	assert_float(top).is_greater(rules.jump_height_m + rules.step_height_m + TOP_MARGIN_M)
	# Only a crouched player gets under the raised car (RD1).
	assert_float(rules.crouch_height_m).is_less(CLEARANCE_M)
	assert_float(CLEARANCE_M).is_less(rules.capsule_height_m)


func test_only_the_lift_s_frame_collides_on_layer_1() -> void:
	for path: String in [CAR, PARTS_SHELF, PART_PICTURE]:
		var root := _scene(path)
		var layer_one: Array[String] = []
		for body: CollisionObject3D in _collision_objects(root):
			if (body.collision_layer & LevelWorld.WORLD_LAYER) != 0:
				layer_one.append(String(root.get_path_to(body)))
		# The art's hint colliders are off; the picture hangs on the room's wall.
		var expected: Array[String] = []
		if path != PART_PICTURE:
			expected.append("Collision")
		assert_array(layer_one).override_failure_message(path).is_equal(expected)
		var collision := root.get_node_or_null("Collision") as StaticBody3D
		if collision == null:
			continue
		for child: Node in collision.get_children():
			var shape := child as CollisionShape3D
			var what := "%s: %s" % [path, child.name]
			assert_object(shape).override_failure_message(what).is_not_null()
			if shape != null:
				assert_bool(_primitive(shape.shape)).override_failure_message(what).is_true()
		var level := LevelWorld.from_packed(load(path) as PackedScene, path)
		assert_array(Array(level.errors)).override_failure_message(path).is_empty()


func test_the_car_s_use_spot_and_car_end_lie_on_the_floor_along_its_axis() -> void:
	var root := _scene(CAR)
	var read := MarkerReader.read(root, CAR, HostWorldQuery.new())
	assert_array(Array(read.errors)).is_empty()
	assert_array(read.layout.tags()).contains_exactly_in_any_order([&"car", &"car_end"])
	var spot := root.get_node_or_null("UseSpot") as Marker3D
	var end := root.get_node_or_null("CarEnd") as Marker3D
	assert_object(spot).is_not_null()
	assert_object(end).is_not_null()
	if spot == null or end == null:
		return
	assert_bool(spot.is_in_group("spawn_car")).is_true()
	assert_bool(end.is_in_group("spawn_car_end")).is_true()
	assert_bool(spot.position.is_zero_approx()).is_true()
	assert_bool(end.position.is_equal_approx(Vector3(0, 0, HALF_LENGTH_M))).is_true()


func test_the_lift_s_frame_stays_clear_of_a_player_on_the_car_s_use_spot() -> void:
	var level := LevelWorld.from_packed(load(CAR) as PackedScene, CAR)
	assert_int(level.body_count()).is_equal(1)
	assert_int(_hits(level, Vector3.ZERO)).is_equal(0)
	# The check can fail: the same capsule on a post.
	var post := (_scene(CAR).get_node("Collision/PostLeft") as Node3D).position
	assert_int(_hits(level, Vector3(post.x, 0, post.z))).is_greater(0)


func test_the_lift_panel_s_light_is_dark_by_default() -> void:
	var light := _scene(LIFT_PANEL).get_node_or_null("Light") as MeshInstance3D
	assert_object(light).override_failure_message("no Light mesh").is_not_null()
	if light != null:
		assert_bool(light.visible).is_false()


func test_the_shelf_has_one_bin_per_part_kind_each_with_its_use_spot_and_picture() -> void:
	var root := _scene(PARTS_SHELF)
	var read := MarkerReader.read(root, PARTS_SHELF, HostWorldQuery.new())
	assert_array(Array(read.errors)).is_empty()
	var level := LevelWorld.from_packed(load(PARTS_SHELF) as PackedScene, PARTS_SHELF)
	var tags: Array[StringName] = []
	var materials: Array[Material] = []
	for n: int in range(1, BINS + 1):
		var tag := StringName("part_bin_%d" % n)
		tags.append(tag)
		assert_int(read.layout.count(tag)).override_failure_message(String(tag)).is_equal(1)
		var spot := root.get_node_or_null("Bin%d/UseSpot" % n) as Marker3D
		var picture := root.get_node_or_null("Bin%d/Picture" % n) as MeshInstance3D
		assert_object(spot).override_failure_message("Bin%d: no UseSpot" % n).is_not_null()
		assert_object(picture).override_failure_message("Bin%d: no Picture" % n).is_not_null()
		if spot == null or picture == null:
			continue
		assert_bool(spot.is_in_group("spawn_%s" % tag)).is_true()
		# On the floor in front of the shelf (local +Z), a player there clear of it.
		var at := LevelWorld.transform_in_scene(spot, root).origin
		assert_float(at.y).override_failure_message(String(tag)).is_equal_approx(0.0, NEAR)
		assert_float(at.z).override_failure_message(String(tag)).is_greater(0.0)
		assert_int(_hits(level, at)).override_failure_message(String(tag)).is_equal(0)
		assert_bool(picture.visible).is_true()
		var material := picture.get_surface_override_material(0)
		assert_object(material).is_not_null()
		assert_bool(materials.has(material)).override_failure_message("Bin%d" % n).is_false()
		materials.append(material)
	assert_array(read.layout.tags()).contains_exactly_in_any_order(tags)
	# The check can fail: the same capsule inside the shelf.
	assert_int(_hits(level, Vector3.ZERO)).is_greater(0)


func test_the_part_picture_has_a_hidden_plate_and_a_use_spot_in_front() -> void:
	var root := _scene(PART_PICTURE)
	var read := MarkerReader.read(root, PART_PICTURE, HostWorldQuery.new())
	assert_array(Array(read.errors)).is_empty()
	assert_array(read.layout.tags()).is_equal([&"part_picture"])
	var spot := root.get_node_or_null("UseSpot") as Marker3D
	var plate := root.get_node_or_null("Picture") as MeshInstance3D
	assert_object(spot).is_not_null()
	assert_object(plate).is_not_null()
	if spot == null or plate == null:
		return
	assert_bool(spot.is_in_group("spawn_part_picture")).is_true()
	assert_float(spot.position.y).is_equal_approx(0.0, NEAR)
	assert_float(spot.position.x).is_equal_approx(0.0, NEAR)
	assert_float(spot.position.z).is_greater(0.0)
	# R7 draws the needed part there; nothing shows before the deal.
	assert_bool(plate.visible).is_false()


## The scene at `path`, instantiated and freed with the test.
func _scene(path: String) -> Node3D:
	return auto_free((load(path) as PackedScene).instantiate()) as Node3D


func _collision_objects(node: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	if node is CollisionObject3D:
		found.append(node as CollisionObject3D)
	for child: Node in node.get_children():
		found.append_array(_collision_objects(child))
	return found


## A primitive shape: no mesh-made hull or trimesh (those come from the art's GLBs).
static func _primitive(shape: Shape3D) -> bool:
	return (
		shape is BoxShape3D
		or shape is CylinderShape3D
		or shape is CapsuleShape3D
		or shape is SphereShape3D
	)


## How many shapes of the level's world a standing player's capsule (the base mode's PlayerRules)
## meets with its feet on the floor at `feet`.
static func _hits(level: LevelWorld, feet: Vector3) -> int:
	var rules := (load(BASE_MODE) as GameMode).player_rules
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := feet + Vector3.UP * (FLOOR_GAP_M + capsule.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return level.space_state().intersect_shape(query).size()
