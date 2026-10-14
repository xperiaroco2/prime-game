extends GdUnitTestSuite
## The photo task's station scenes (#783, P4; the photo task ADR §9's P4 row): what each holds
## beyond the station convention that station_scenes_test.gd checks for every device. The camera
## keeps its collision below the shooter's line of sight and holds the film slot and its
## depth-tested frames counter; the photo spot is a floor mark of the spot kind's radius with no
## device; the printer holds its tray marker on its top; the board holds named slots on its face.

const CAMERA := "res://levels/stations/camera.tscn"
const PHOTO_SPOT := "res://levels/stations/photo_spot.tscn"
const PRINTER := "res://levels/stations/printer.tscn"
const PHOTO_BOARD := "res://levels/stations/photo_board.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The photo spot kind's radius_m: PD9's placeholder for every photo station (2 m, "not a
## decision"; its data comes with P5). The mark is drawn at it.
const SPOT_RADIUS_M := 2.0
## The board's slots for the hung photos ("not a decision": two rows of five).
const SLOTS := 10
const NEAR := 1e-3


func test_the_camera_s_collision_stays_below_the_shooter_s_line_of_sight() -> void:
	var level := LevelWorld.from_packed(load(CAMERA) as PackedScene, CAMERA)
	var spot := (_scene(CAMERA).get_node("UseSpot") as Marker3D).position
	var eye := (load(BASE_MODE) as GameMode).player_rules.eye_height_m
	# The lens is the shooter's eye over the use spot (PhotoTask's frame); the aim lies ahead, -Z.
	var lens := spot + Vector3.UP * eye
	assert_bool(_ray_hits(level, lens, lens + Vector3.FORWARD * 10.0)).is_false()
	# The check can fail: the same line at the tripod's middle meets its collision.
	var low := spot + Vector3.UP * 0.7
	assert_bool(_ray_hits(level, low, low + Vector3.FORWARD * 10.0)).is_true()


func test_the_camera_holds_its_film_slot_and_a_depth_tested_frames_counter() -> void:
	var root := _scene(CAMERA)
	var slot := root.get_node_or_null("FilmSlot") as Node3D
	assert_object(slot).override_failure_message("no FilmSlot").is_not_null()
	var label := root.get_node_or_null("FramesLeft") as Label3D
	assert_object(label).override_failure_message("no FramesLeft Label3D").is_not_null()
	if slot == null or label == null:
		return
	# Drawn in the world, so a wall hides it (DD4): never through walls.
	assert_bool(label.no_depth_test).is_false()
	# Shown only while a film is loaded (P8 sets it), and read from the use spot's side (+Z).
	assert_bool(label.visible).is_false()
	assert_float(label.basis.z.dot(Vector3.BACK)).is_greater(0.99)
	# Both on the camera's head, between the tripod's top and the shooter's eye.
	var eye := (load(BASE_MODE) as GameMode).player_rules.eye_height_m
	for part: Node3D in [slot, label]:
		assert_float(part.position.y).override_failure_message(part.name).is_between(1.0, eye)
		assert_float(absf(part.position.x)).override_failure_message(part.name).is_less(0.3)


func test_the_photo_spot_is_a_floor_mark_of_the_spot_radius_with_no_device() -> void:
	var root := _scene(PHOTO_SPOT)
	var read := MarkerReader.read(root, PHOTO_SPOT, HostWorldQuery.new())
	assert_array(Array(read.errors)).is_empty()
	assert_array(read.layout.tags()).is_equal([&"photo_spot"])
	var spot := root.get_node_or_null("UseSpot") as Marker3D
	assert_object(spot).is_not_null()
	if spot != null:
		# The camera frames the mark's centre, the scene's floor point.
		assert_float(spot.position.length()).is_equal_approx(0.0, NEAR)
	var ring := root.get_node_or_null("Mark/Ring") as MeshInstance3D
	assert_object(ring).override_failure_message("no Mark/Ring").is_not_null()
	if ring != null:
		var torus := ring.mesh as TorusMesh
		assert_object(torus).is_not_null()
		if torus != null:
			assert_float(torus.outer_radius).is_equal_approx(SPOT_RADIUS_M, NEAR)
		# Flat on the floor: nothing to trip over or hide behind.
		var box := ring.get_aabb()
		assert_float(ring.position.y + box.end.y).is_less(0.05)
	# A display kind: nothing to use, nothing that collides.
	assert_array(_collision_objects(root)).is_empty()


func test_the_printer_holds_its_tray_marker_on_its_top() -> void:
	var root := _scene(PRINTER)
	var tray := root.get_node_or_null("Tray") as Marker3D
	assert_object(tray).override_failure_message("no Tray Marker3D").is_not_null()
	if tray == null:
		return
	assert_bool(tray.is_in_group(&"spawn_photo")).is_true()
	# Straight down from just above the tray: the printer's own collision, at most 2 cm below.
	var level := LevelWorld.from_packed(load(PRINTER) as PackedScene, PRINTER)
	var hit := _ray(level, tray.position + Vector3.UP * 0.5, tray.position + Vector3.DOWN)
	assert_bool(hit.is_empty()).is_false()
	if not hit.is_empty():
		var top: Vector3 = hit["position"]
		assert_float(tray.position.y - top.y).is_between(0.0, 0.02)
	# Over the printer (the art's body), not the desk beside it.
	var body := root.get_node("Body") as Node3D
	var offset := tray.position - body.position
	assert_float(Vector2(offset.x, offset.z).length()).is_less(0.25)


func test_the_board_holds_named_slots_on_its_face() -> void:
	var root := _scene(PHOTO_BOARD)
	var level := LevelWorld.from_packed(load(PHOTO_BOARD) as PackedScene, PHOTO_BOARD)
	var seen: Array[Vector3] = []
	for i in range(1, SLOTS + 1):
		var slot := root.get_node_or_null("Slots/Slot%d" % i) as Marker3D
		assert_object(slot).override_failure_message("no Slots/Slot%d" % i).is_not_null()
		if slot == null:
			continue
		var at := slot.position
		assert_bool(seen.has(at)).override_failure_message(slot.name).is_false()
		seen.append(at)
		# On the face: the board's panel right behind the slot, nothing in front of it.
		var behind := _ray(level, at, at + Vector3.FORWARD * 0.2)
		assert_bool(behind.is_empty()).override_failure_message(slot.name).is_false()
		if not behind.is_empty():
			var face: Vector3 = behind["position"]
			assert_float(at.z - face.z).override_failure_message(slot.name).is_between(0.0, 0.05)
		assert_bool(_ray_hits(level, at, at + Vector3.BACK * 2.0)).is_false()
	assert_int(root.get_node("Slots").get_child_count()).is_equal(SLOTS)


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


static func _ray(level: LevelWorld, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, LevelWorld.WORLD_LAYER)
	return level.space_state().intersect_ray(query)


static func _ray_hits(level: LevelWorld, from: Vector3, to: Vector3) -> bool:
	return not _ray(level, from, to).is_empty()
