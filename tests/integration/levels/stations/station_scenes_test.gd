extends GdUnitTestSuite
## The Generator's station scenes (#799, G4; the Generator ADR's GE11) and the photo task's
## devices (#783, P4: the camera, the film box, the printer, the board) and the car repair's lift
## panel (#809, R5): each scene is the device,
## its collision its own primitive shapes on layer 1 (the art body's hint colliders off), one
## use-spot Marker3D in its spawn group on the floor in front of the device, where a player
## stands clear of the device, and the named nodes the client drives with their default looks
## (the switch's active look, off; GD5's fixed look hidden; the generator's bars and glow dark).
## The convention: the level piece ADR's "Station scenes"
## (docs/decisions/2026-10-09-level-piece-conventions.md).

const SWITCH := "res://levels/stations/switch.tscn"
const GENERATOR := "res://levels/stations/generator.tscn"
## The photo task's devices (#783, P4); its photo spot, a floor mark with no device, is
## photo_stations_test.gd's.
const CAMERA := "res://levels/stations/camera.tscn"
const FILM_BOX := "res://levels/stations/film_box.tscn"
const PRINTER := "res://levels/stations/printer.tscn"
const PHOTO_BOARD := "res://levels/stations/photo_board.tscn"
## The car repair's lift panel (#809, R5); the car, the parts shelf and the part picture, whose
## use spots and collision differ, are car_repair_stations_test.gd's.
const LIFT_PANEL := "res://levels/stations/lift_panel.tscn"
## Each station scene and its use spot's tag (provisional, "not a decision").
const SCENES := {
	SWITCH: &"switch",
	GENERATOR: &"generator",
	CAMERA: &"camera",
	FILM_BOX: &"film_box",
	PRINTER: &"printer",
	PHOTO_BOARD: &"photo_board",
	LIFT_PANEL: &"lift_panel",
}
## The other markers a scene holds besides its use spot: the printer's tray (`spawn_photo`).
const OTHER_TAGS := {PRINTER: [&"photo"]}
const BASE_MODE := "res://content/modes/base_mode.tres"
const NEAR := 1e-3
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05


func test_each_scene_has_one_use_spot_in_its_group_on_the_floor_in_front() -> void:
	for path: String in SCENES:
		var tag: StringName = SCENES[path]
		var root := _scene(path)
		var read := MarkerReader.read(root, path, HostWorldQuery.new())
		assert_array(Array(read.errors)).override_failure_message(path).is_empty()
		var tags: Array[StringName] = [tag]
		tags.append_array(OTHER_TAGS.get(path, []) as Array)
		tags.sort()
		var found := read.layout.tags()
		found.sort()
		assert_array(found).override_failure_message(path).is_equal(tags)
		assert_int(read.layout.count(tag)).override_failure_message(path).is_equal(1)
		var spot := root.get_node_or_null("UseSpot") as Marker3D
		assert_object(spot).override_failure_message("%s: no UseSpot Marker3D" % path).is_not_null()
		if spot == null:
			continue
		assert_bool(spot.is_in_group("spawn_%s" % tag)).override_failure_message(path).is_true()
		# On the floor (the root stands at the device's floor point), in front: local +Z.
		var at := spot.position
		assert_float(at.y).override_failure_message(path).is_equal_approx(0.0, NEAR)
		assert_float(at.x).override_failure_message(path).is_equal_approx(0.0, NEAR)
		assert_float(at.z).override_failure_message(path).is_greater(0.0)


func test_each_scene_collides_on_layer_1_only_through_its_own_primitive_shapes() -> void:
	for path: String in SCENES:
		var root := _scene(path)
		var layer_one: Array[String] = []
		for body: CollisionObject3D in _collision_objects(root):
			if (body.collision_layer & LevelWorld.WORLD_LAYER) != 0:
				layer_one.append(String(root.get_path_to(body)))
		# The art body's hint colliders (convex hulls from the GLB) are off: only `Collision`.
		assert_array(layer_one).override_failure_message(path).is_equal(["Collision"])
		var collision := root.get_node_or_null("Collision") as StaticBody3D
		assert_object(collision).override_failure_message(path).is_not_null()
		if collision == null:
			continue
		var shapes := 0
		for child: Node in collision.get_children():
			var shape := child as CollisionShape3D
			var what := "%s: %s" % [path, child.name]
			assert_object(shape).override_failure_message(what).is_not_null()
			if shape == null:
				continue
			assert_bool(_primitive(shape.shape)).override_failure_message(what).is_true()
			shapes += 1
		assert_int(shapes).override_failure_message(path).is_greater(0)
		var level := LevelWorld.from_packed(load(path) as PackedScene, path)
		assert_array(Array(level.errors)).override_failure_message(path).is_empty()
		assert_int(level.body_count()).override_failure_message(path).is_equal(1)


func test_a_player_on_the_use_spot_stands_clear_of_the_device() -> void:
	for path: String in SCENES:
		var level := LevelWorld.from_packed(load(path) as PackedScene, path)
		var root := _scene(path)
		var spot := root.get_node("UseSpot") as Marker3D
		assert_int(_hits(level, spot.position)).override_failure_message(path).is_equal(0)
		# The check can fail: the same capsule on the device's own floor point.
		assert_int(_hits(level, Vector3.ZERO)).override_failure_message(path).is_greater(0)


func test_the_switch_shows_its_active_look_off_by_default() -> void:
	var root := _scene(SWITCH)
	var shown := ["Active", "Active/Off"]
	var hidden := ["Active/On", "Fixed"]
	for part: String in shown + hidden:
		var node := root.get_node_or_null(part) as Node3D
		assert_object(node).override_failure_message("no %s" % part).is_not_null()
		if node != null:
			assert_bool(node.visible).override_failure_message(part).is_equal(shown.has(part))
	# Each look's parts, the meshes the client never moves but shows or hides as a whole.
	for part: String in [
		"Active/Off/Lever",
		"Active/Off/Lamp",
		"Active/On/Lever",
		"Active/On/Lamp",
		"Fixed/Lever",
		"Fixed/Lamp",
		"Fixed/Cover",
	]:
		var mesh := root.get_node_or_null(part) as MeshInstance3D
		assert_object(mesh).override_failure_message("no mesh %s" % part).is_not_null()
	var frame := root.get_node_or_null("Fixed/Frame") as Node3D
	assert_object(frame).override_failure_message("no Fixed/Frame").is_not_null()
	if frame != null:
		assert_int(frame.get_child_count()).is_greater(0)
	# The lever is down when off and up when on (and locked up in the fixed look).
	var off := root.get_node("Active/Off/Lever") as Node3D
	var on := root.get_node("Active/On/Lever") as Node3D
	var fixed := root.get_node("Fixed/Lever") as Node3D
	assert_float(on.position.y).is_greater(off.position.y)
	assert_float(fixed.position.y).is_equal_approx(on.position.y, NEAR)


func test_the_generator_shows_its_button_and_dark_bars_by_default() -> void:
	var root := _scene(GENERATOR)
	var button := root.get_node_or_null("Button") as MeshInstance3D
	assert_object(button).override_failure_message("no Button mesh").is_not_null()
	if button != null:
		assert_bool(button.visible).is_true()
	for part: String in ["Bars/Bar1", "Bars/Bar2", "Bars/Bar3", "Bars/Bar4", "Glow"]:
		var mesh := root.get_node_or_null(part) as MeshInstance3D
		assert_object(mesh).override_failure_message("no mesh %s" % part).is_not_null()
		if mesh != null:
			assert_bool(mesh.visible).override_failure_message(part).is_false()
	var bars := root.get_node_or_null("Bars") as Node3D
	assert_object(bars).is_not_null()
	if bars != null:
		assert_bool(bars.visible).is_true()


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
