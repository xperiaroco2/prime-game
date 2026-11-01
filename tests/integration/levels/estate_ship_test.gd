extends GdUnitTestSuite
## The estate's ship is the art ship (#1499): `levels/estate/rooms/ship.tscn` instances the art
## package's `levels/ship/ship.tscn` (prime-game-art#335, the lobby's too) with no greybox left,
## frees the package's clearing, sky and suns on the client while the host never had their
## colliders, closes the hull the package leaves open (its skin has no `-col` hints), stands its
## grated floors on convex hulls (their lattice trimeshes cost the physics too much), and puts the
## engine's markers and stand-ins on the art's station spots, gill sets and engine pods
## (docs/design/estate-map.md §5a). The engine's own contract: estate_engine_test.gd.

const ShipHull := preload("res://tests/fixtures/ship_hull_colliders.gd")
const ShipFloor := preload("res://tests/fixtures/ship_floor_colliders.gd")
const Check := preload("res://tools/assets/asset_check.gd")
const SHIP := "res://levels/estate/rooms/ship.tscn"
const ART := "res://levels/ship/ship.tscn"
## The deck over the ship's origin, and the start console package's button over the deck and its
## pedestal's radius (prime-game-art's start_console HANDOFF "Placement").
const DECK_M := 1.2
const BUTTON_OVER_DECK_M := 0.814
const PEDESTAL_M := 0.6
## The parts of the estate's piece beside the art: the engine, the hull's colliders, the map's
## label and the door marker.
const OWN_PARTS: Array[String] = ["Art", "Hull", "Engine", "Name", "Doors"]
## How near a stand-in or a place stands to the art part it binds to.
const ON_ART_M := 0.03
## How far in front of its art spot an engine marker may stand (a player's capsule from the wall
## at least, within the station's reach at most).
const IN_FRONT_M := Vector2(0.35, 1.5)
## A trimesh thinner than this with more triangles than that is a lattice of floor, which costs
## Jolt's motion queries a hundred times plain floor (tests/fixtures/ship_floor_colliders.gd).
const THIN_M := 0.05
const DENSE_TRIANGLES := 500
## How far the floor test drops its ball, and the ball's radius (a capsule's lower cap; smaller
## than a player's 0.4 m circle, so it finds gaps the player rides over too).
const DROP_M := 1.2
const BALL_M := 0.3
## The floor plates the ship turns off to level a station's use spot with the deck (#1499).
const LEVELLED_PLATES := 2

var _root: Node3D


func before_test() -> void:
	_root = (load(SHIP) as PackedScene).instantiate() as Node3D


func after_test() -> void:
	if is_instance_valid(_root):
		if _root.is_inside_tree():
			remove_child(_root)
		_root.free()


func test_the_ship_is_the_art_package_and_no_greybox_is_left() -> void:
	var art := _root.get_node(^"Art")
	assert_str(art.scene_file_path).is_equal(ART)
	var names: Array[String] = []
	for child: Node in _root.get_children():
		names.append(str(child.name))
	assert_array(names).contains_exactly_in_any_order(OWN_PARTS)
	# Every mesh of the piece's own is the engine's stand-in; no CSG anywhere.
	for found: Node in _root.find_children("*", "MeshInstance3D", true, false):
		if art.is_ancestor_of(found):
			continue
		(
			assert_bool(_root.get_node(^"Engine").is_ancestor_of(found))
			. override_failure_message("%s is no engine stand-in" % _root.get_path_to(found))
			. is_true()
		)
	assert_array(_root.find_children("*", "CSGShape3D", true, false)).is_empty()
	# The art's own root declares its size too, but inside the estate's lot it is no second map
	# room: the estate's piece, with its record, is the one room.
	var rooms := MapData.rooms_of(_root)
	assert_int(rooms.size()).is_equal(1)
	assert_str(String(rooms[0].id)).is_equal("ship")


func test_the_client_frees_the_clearing_sky_and_suns_and_keeps_the_host_s_colliders() -> void:
	var host := LevelWorld.build(SHIP)
	assert_array(Array(host.errors)).is_empty()
	# The package's clearing ground (a WorldBoundary at y 0) is not the host's: no floor out here.
	var out := PhysicsRayQueryParameters3D.create(Vector3(40.0, 5.0, 0.0), Vector3(40.0, -5.0, 0.0))
	assert_bool(host.space_state().intersect_ray(out).is_empty()).is_true()
	add_child(_root)
	await get_tree().process_frame
	for gone: String in ["Art/Clearing", "Art/Environment", "Art/Lights/@DirectionalLight3D@3"]:
		assert_object(_root.get_node_or_null(gone)).override_failure_message(gone).is_null()
	assert_array(_root.find_children("*", "WorldEnvironment", true, false)).is_empty()
	assert_array(_root.find_children("*", "DirectionalLight3D", true, false)).is_empty()
	assert_int(LevelWorld.from_scene(_root, SHIP).body_count()).is_equal(host.body_count())


func test_the_hull_s_colliders_are_the_art_skin_and_close_the_hull() -> void:
	if _art_is_a_pointer():
		return
	var art := _root.get_node(^"Art") as Node3D
	for stem: String in ShipHull.STEMS:
		var saved := load(ShipHull.shape_path(stem)) as ConcavePolygonShape3D
		var faces := ShipHull.faces_of(art, stem)
		assert_int(faces.size()).is_greater(0)
		(
			assert_bool(saved.get_faces() == faces)
			. override_failure_message(
				"%s is stale: run tests/fixtures/ship_hull_colliders.gd" % ShipHull.shape_path(stem)
			)
			. is_true()
		)
	var host := LevelWorld.build(SHIP)
	# A throw over the hall meets the hull's top, not the deck under its open ceiling.
	var down := PhysicsRayQueryParameters3D.create(Vector3(0, 20, -0.4), Vector3(0, -1, -0.4))
	var hit := host.space_state().intersect_ray(down)
	assert_float((hit.get("position", Vector3.ZERO) as Vector3).y).is_greater(4.0)
	# Under the aft hull, between its legs, the belly (0.77 m up) leaves no room for a player.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.92, 8.0))
	assert_array(host.space_state().intersect_shape(query, 1)).is_not_empty()


func test_the_floors_are_the_convex_hulls_of_the_art_s_grates_and_discs() -> void:
	for file: String in ShipFloor.FLOOR_SHAPES:
		var saved := load(ShipFloor.hull_path(file)) as ConvexPolygonShape3D
		var kit := load(ShipFloor.KIT + file) as ConcavePolygonShape3D
		(
			assert_bool(saved.points == ShipFloor.hull_of(kit))
			. override_failure_message(
				(
					"%s is stale: run tests/fixtures/ship_floor_colliders.gd"
					% ShipFloor.hull_path(file)
				)
			)
			. is_true()
		)
	# No lattice of thin floor triangles is left under the ship, a kit floor of the list or a new one.
	var dense: Array[String] = []
	for found: Node in _root.find_children("*", "CollisionShape3D", true, false):
		var shape := (found as CollisionShape3D).shape
		var body := found.get_parent() as CollisionObject3D
		if not shape is ConcavePolygonShape3D or body == null or body.collision_layer & 1 == 0:
			continue
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		var box := AABB(faces[0], Vector3.ZERO)
		for v: Vector3 in faces:
			box = box.expand(v)
		if faces.size() / 3 > DENSE_TRIANGLES and box.size.y < THIN_M:
			dense.append("%s (%d)" % [_root.get_path_to(found), faces.size() / 3])
	assert_array(dense).is_empty()


func test_a_player_stands_on_the_hulls_where_he_stood_on_the_art_s_floors() -> void:
	var art_floors := (load(SHIP) as PackedScene).instantiate() as Node3D
	var swapped := 0
	for found: Node in art_floors.find_children("*", "CollisionShape3D", true, false):
		var collision := found as CollisionShape3D
		if collision.shape != null and collision.shape.resource_path.begins_with(ShipFloor.HULLS):
			var file := collision.shape.resource_path.get_file()
			if ShipFloor.FLOOR_SHAPES.has(file):
				collision.shape = load(ShipFloor.KIT + file) as Shape3D
				collision.disabled = false
				swapped += 1
	assert_int(swapped).is_greater(40)
	var levelled := _levelled_plates()
	assert_array(levelled.keys()).has_size(LEVELLED_PLATES)
	var hull_world := LevelWorld.from_scene(_root, SHIP)
	var art_world := LevelWorld.from_scene(art_floors, SHIP)
	var hulls := hull_world.space_state()
	var trimeshes := art_world.space_state()
	art_floors.free()
	# A ball (BALL_M) dropped over every deck of the ship comes to rest at the
	# same height on both: the hull fills the lattice's holes and nothing more.
	var drops := 0
	var off: Array[String] = []
	for over: float in [2.3, 3.2, 4.2, 5.8]:
		for x in range(-26, 27):
			for z in range(-20, 21):
				var at := Vector3(x * 0.5, over, z * 0.5)
				var on_hulls := _rest_height(hulls, at)
				var on_trimeshes := _rest_height(trimeshes, at)
				if is_nan(on_hulls) and is_nan(on_trimeshes):
					continue
				drops += 1
				# Over a plate levelled with the deck, the deck may lie lower, by the plate at most.
				var lower := 0.0
				for plate: Rect2 in levelled:
					if plate.grow(BALL_M).has_point(Vector2(at.x, at.z)):
						lower = maxf(lower, levelled[plate] as float)
				var below := on_trimeshes - on_hulls if not is_nan(on_hulls + on_trimeshes) else 0.0
				if lower > 0.0 and below > 0.0 and below <= lower + 0.01:
					continue
				if is_nan(on_hulls) or is_nan(on_trimeshes) or absf(on_hulls - on_trimeshes) > 0.01:
					off.append("%s: %.3f, art %.3f" % [at, on_hulls, on_trimeshes])
	assert_int(drops).is_greater(1000)
	assert_array(off).is_empty()


func test_each_gill_set_stands_on_the_art_s_gills() -> void:
	if _art_is_a_pointer():
		return
	add_child(_root)
	var sets := _root.get_node(^"Engine").find_children("Gills*", "Node3D", false, false)
	assert_int(sets.size()).is_equal(2)
	for gills: Node in sets:
		var set_at := gills as Node3D
		var wall := _art_piece("th_wall_e_" if set_at.global_position.x > 0.0 else "th_wall_w_")
		for k in range(1, 6):
			var slit := set_at.get_node("Slit%d" % k) as Node3D
			var lip := _centre(wall.get_node("gill%d_lip" % k) as MeshInstance3D)
			_assert_near(slit.global_position, lip, "%s slit %d" % [gills.name, k])
			var bar := _centre(wall.get_node("gill%d_bar_glow" % k) as MeshInstance3D)
			var light := set_at.get_node("Light%d" % k) as Node3D
			_assert_near(light.global_position, bar, "%s bar %d" % [gills.name, k])
		var dome := _centre(wall.get_node("btn_dome") as MeshInstance3D)
		var button := set_at.get_node("Button") as Node3D
		_assert_near(button.global_position, dome, "%s button" % gills.name)


func test_the_hologram_s_turbines_and_button_stand_at_the_art_s_pods_and_button() -> void:
	add_child(_root)
	var point := _root.get_node(^"Engine/Hologram") as Node3D
	var use_spot := (_root.get_node(^"Engine/Markers/EngineConsole01") as Node3D).global_position
	# Each pod, scaled down round the hologram's centre as the mimic board scales a breaker.
	var pods: Array[Vector3] = []
	for piece: Node in _root.get_node(^"Art/Pieces").get_children():
		if str(piece.name).begins_with("nozzle_pod_"):
			pods.append((piece as Node3D).global_position)
	assert_int(pods.size()).is_equal(3)
	var turbines := point.find_children("Turbine*", "Node3D", false, false)
	assert_int(turbines.size()).is_equal(pods.size())
	for pod: Vector3 in pods:
		var flat := Vector3(pod.x - use_spot.x, pod.y - DECK_M, pod.z - use_spot.z)
		var at := point.global_position + flat * ShipEngineViews.MIMIC_SCALE
		var nearest := INF
		for turbine: Node in turbines:
			nearest = minf(nearest, (turbine as Node3D).global_position.distance_to(at))
		assert_float(nearest).override_failure_message("the pod at %s" % pod).is_less(0.005)
	# The start console's button: on its pedestal's front, toward the mouth, at hip height.
	var console := _root.get_node(^"Art/Stations/Console") as Node3D
	var front := console.global_transform.basis.z.normalized()
	var button := console.global_position + front * PEDESTAL_M + Vector3.UP * BUTTON_OVER_DECK_M
	_assert_near((point.get_node("Button") as Node3D).global_position, button, "the button")
	# The hologram's own point over the console's middle.
	(
		assert_float(
			Vector2(point.global_position.x, point.global_position.z).distance_to(
				Vector2(console.global_position.x, console.global_position.z)
			)
		)
		. is_less(0.01)
	)


func test_each_engine_marker_stands_in_front_of_its_art_station_spot() -> void:
	add_child(_root)
	var spots := {
		"EngineConsole01": "Console",
		"GillButton01": "VentW",
		"GillButton02": "VentE",
		"BreakerBoard01": "BreakerW",
		"BreakerBoard02": "BreakerE",
		"CartridgeSocket01": "SocketW",
		"CartridgeSocket02": "SocketFW",
		"CartridgeSocket03": "SocketE",
		"CartridgeSocket04": "SocketFE",
		"Charger01": "RenewerW",
		"Charger02": "RenewerE",
	}
	for i in 8:
		spots["Breaker%02d" % (i + 1)] = "BreakerW" if i < 4 else "BreakerE"
	for marker_name: String in spots:
		var marker := _root.get_node("Engine/Markers/" + marker_name) as Node3D
		var spot := _root.get_node("Art/Stations/" + str(spots[marker_name])) as Node3D
		var normal := spot.global_transform.basis.z.normalized()
		var off := marker.global_position - spot.global_position
		var out := off.dot(normal)
		var where := "%s from %s" % [marker_name, spots[marker_name]]
		if marker_name == "EngineConsole01":
			# The console stands in the hall: its use spot past its pedestal, toward the mouth.
			out -= PEDESTAL_M
		(
			assert_bool(out >= IN_FRONT_M.x and out <= IN_FRONT_M.y)
			. override_failure_message("%s: %.2f m out" % [where, out])
			. is_true()
		)
		assert_float(absf(off.y)).override_failure_message(where).is_less(0.01)


func _art_piece(prefix: String) -> Node3D:
	for piece: Node in _root.get_node(^"Art/Pieces").get_children():
		if str(piece.name).begins_with(prefix):
			return piece as Node3D
	return null


func _centre(look: MeshInstance3D) -> Vector3:
	return (look.global_transform * look.get_aabb()).get_center()


## Near across the wall's face; the art's parts sit a few centimetres into it.
func _assert_near(at: Vector3, art: Vector3, what: String) -> void:
	var across := Vector2(at.x - art.x, at.z - art.z).length()
	(
		assert_bool(across <= 0.1 and absf(at.y - art.y) <= ON_ART_M)
		. override_failure_message("%s at %s, the art's at %s" % [what, at, art])
		. is_true()
	)


## Where a ball of a player's capsule's radius dropped from `from` comes to rest, at its bottom:
## NAN when it starts inside a collider or falls more than DROP_M.
## The floor plates the estate's ship turns off (#1499: the hall disc's hub and bolts, 1.204 and
## 1.211 under the console's use spot, which the host snaps its marker onto, so a player on the
## deck beside it stood under the station's floor), each its plan rect in the ship's frame and how
## far its top stands over the deck.
func _levelled_plates() -> Dictionary[Rect2, float]:
	var found: Dictionary[Rect2, float] = {}
	for node: Node in _root.find_children("*", "CollisionShape3D", true, false):
		var collision := node as CollisionShape3D
		if not collision.disabled or not collision.shape is ConvexPolygonShape3D:
			continue
		var at := LevelWorld.transform_in_scene(collision, _root)
		var points := (collision.shape as ConvexPolygonShape3D).points
		var box := AABB(at * points[0], Vector3.ZERO)
		for point: Vector3 in points:
			box = box.expand(at * point)
		found[Rect2(box.position.x, box.position.z, box.size.x, box.size.z)] = box.end.y - DECK_M
	return found


## Where a ball of BALL_M dropped from `from` comes to rest (its lowest point), NAN for none.
func _rest_height(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var ball := SphereShape3D.new()
	ball.radius = BALL_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = Vector3.DOWN * DROP_M
	if not space.intersect_shape(query, 1).is_empty():
		return NAN
	var safe := space.cast_motion(query)[0]
	if safe >= 1.0:
		return NAN
	return from.y - DROP_M * safe - ball.radius


## Whether the art ship's meshes are Git LFS pointers (CI checks out no LFS content and imports a
## stand-in for each GLB, the LFS ADR's amendment, #515): a test of the art's geometry then says
## it skips, as deck_glyphs_test does, and checks the pointer.
func _art_is_a_pointer() -> bool:
	var glb := ""
	for line: String in FileAccess.get_file_as_string(ART).split("\n"):
		if line.begins_with("[ext_resource") and line.contains('.glb"'):
			glb = line.get_slice('path="', 1).get_slice('"', 0)
			break
	if glb.is_empty() or not Check.is_lfs_pointer(glb):
		return false
	print(
		"skip: %s is a Git LFS pointer (no LFS content here): the art's geometry is unchecked" % glb
	)
	assert_bool(FileAccess.get_file_as_string(glb).contains("oid sha256:")).is_true()
	return true


func test_the_engine_s_finish_flames_from_the_art_s_three_nozzles_out_of_the_stern() -> void:
	add_child(_root)
	var mouths := ShipEngineFinale.nozzles_of(_root)
	assert_int(mouths.size()).is_equal(3)
	var centre := (_root.get_node(^"Engine/Hologram") as Node3D).global_position
	for mouth: Transform3D in mouths:
		# Out of the hull: away from the hall, beyond the pod's own bell.
		var out := Vector3(mouth.origin.x - centre.x, 0.0, mouth.origin.z - centre.z).normalized()
		assert_float(mouth.basis.z.dot(out)).is_greater(0.5)
		assert_float(mouth.origin.z).is_greater(9.6)
