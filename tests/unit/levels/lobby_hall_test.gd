extends GdUnitTestSuite
## The lobby hall (#1451): the art lobby hall's level set (prime-game-art#356, PR art#364, its
## HANDOFF.md) in place of the greybox hall (#1354), with the game's own pieces beside it (GDD §3
## Base mode, the Lobby bullet; docs/design/m8-match.md §1). `Hall` instances the art's
## levels/lobby/lobby_hall.tscn (the hall, the docked ship from the ship package, the Earth, the
## light rig and the art's ten spawn markers); the game keeps the bar, the photo booth, the pinball
## machine and the mirror as separate greybox boxes, the ten lobby spawns at the art's markers and
## the tap, pinball and booth markers. The box places are placeholders, "not a decision" (the MVP
## content ADR): the engineer sets the layout on this scene.
## The colliders are checked as the host sees them: LevelWorld (server/level_world.gd) built from
## the scene, asked with the player's capsule. The guards: the boxes stand inside the hall, apart
## and clear of the hall's and the ship's colliders; and nothing but the floor stands where the bot
## scenarios walk in the lobby (their fake world is one flat floor, §9.7, content_modes_test's
## test_the_scenarios_levels_are_flat): no collider within a capsule and a margin of a lobby marker
## or of a straight walk a scenario takes before it first waits.

const LOBBY := "res://levels/lobby/lobby.tscn"
const HALL := "res://levels/lobby/lobby_hall.tscn"
const SHIP := "res://levels/ship/ship.tscn"
const PLAYER := "res://client/player/player.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
## The game's pieces of the hall, each a node of its own under the root.
const PIECES: Array[String] = ["Bar", "PhotoBooth", "Pinball", "Mirror"]
## The hall's floor plan inside its straight walls (x, z), the art's layouts/lobby/hall.toml
## (x0, x1, zN, zS); the window bows south of it to z 16.
const INSIDE := Rect2(-20.0, -30.0, 40.0, 40.0)
## The ship's plan origin in the hall (#1451's positions comment, the engineer's 2026-10-30).
const SHIP_ORIGIN := Vector3(0.0, 0.0, -14.5)
## The ten lobby spawns (the same comment): x from -9 to 9 in steps of 2, z 2.5, facing +z.
const SPAWN_Z := 2.5
## A collider whose top is no higher stands under the feet: the floor plates and the ring inlay.
const FLOOR_TOP_M := 0.05
## Beyond a bot's capsule radius: room to pass a collider's edge.
const MARGIN_M := 0.1
const EPS := 1e-4

var _root: Node3D
var _mode: GameMode


func before() -> void:
	_mode = load(BASE_MODE) as GameMode


func before_test() -> void:
	_root = auto_free((load(LOBBY) as PackedScene).instantiate()) as Node3D


func test_the_hall_is_the_art_lobby_halls_level_set_with_the_ship_docked_shut() -> void:
	assert_str(_mode.lobby_level).is_equal(LOBBY)
	var hall := _root.get_node_or_null("Hall") as Node3D
	assert_object(hall).is_not_null()
	if hall == null:
		return
	assert_str(hall.scene_file_path).is_equal(HALL)
	assert_bool(hall.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	var ship := hall.get_node_or_null("Ship") as Node3D
	assert_object(ship).is_not_null()
	if ship == null:
		return
	assert_str(ship.scene_file_path).is_equal(SHIP)
	assert_vector(ship.position).is_equal_approx(SHIP_ORIGIN, Vector3(EPS, EPS, EPS))
	# The jaw nose shut (the ship package's HANDOFF: the lobby shows it closed).
	for jaw: String in ["Nose/jaw_lower", "Nose/jaw_upper"]:
		var piece := ship.get_node_or_null(jaw) as Node3D
		assert_object(piece).override_failure_message(jaw).is_not_null()
		if piece != null:
			assert_float(piece.rotation.x).override_failure_message(jaw).is_equal_approx(0.0, EPS)
	# The Earth at infinity and the hall's one environment.
	assert_object(hall.get_node_or_null("Earth/EarthObject")).is_not_null()
	assert_object(hall.get_node_or_null("Environment/WorldEnvironment")).is_not_null()


## The level script frees the ship package's own clearing, environment and suns on _ready, so the
## hall has one WorldEnvironment and no forest (the package's HANDOFF).
func test_in_the_tree_the_ship_keeps_no_clearing_and_the_hall_one_environment() -> void:
	add_child(_root)
	# The script frees on _ready, then recaptures the probes a frame later: let it finish.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var ship := _root.get_node("Hall/Ship")
	assert_object(ship.get_node_or_null("Clearing")).is_null()
	assert_object(ship.get_node_or_null("Environment")).is_null()
	var suns := ship.find_children("*", "DirectionalLight3D", true, false)
	assert_array(suns).is_empty()
	var environments := _root.find_children("*", "WorldEnvironment", true, false)
	assert_int(environments.size()).is_equal(1)
	remove_child(_root)


## The player's camera reaches the Earth: its far plane at least the hall's `camera_far_m`.
func test_the_player_camera_sees_as_far_as_the_hall_needs() -> void:
	var hall := _root.get_node("Hall")
	var far_m: float = hall.get_meta(&"camera_far_m", 0.0)
	assert_float(far_m).is_greater(0.0)
	# Read from the scene's state: an instanced player would leave its script's nodes behind.
	var state := (load(PLAYER) as PackedScene).get_state()
	var default_camera := Camera3D.new()
	var cameras := 0
	for node: int in state.get_node_count():
		if state.get_node_type(node) != &"Camera3D":
			continue
		cameras += 1
		var far := default_camera.far
		for prop: int in state.get_node_property_count(node):
			if state.get_node_property_name(node, prop) == &"far":
				far = state.get_node_property_value(node, prop)
		assert_float(far).is_greater_equal(far_m)
	default_camera.free()
	assert_int(cameras).is_greater(0)


func test_the_lobby_spawns_stand_on_the_art_halls_spawn_markers() -> void:
	var spawns := _markers(&"spawn_lobby_player")
	var art := _root.get_node("Hall/Markers").get_children()
	assert_int(spawns.size()).is_equal(10)
	assert_int(art.size()).is_equal(10)
	if spawns.size() != art.size():
		return
	for i: int in spawns.size():
		var spawn := LevelWorld.transform_in_scene(spawns[i], _root)
		var marker := LevelWorld.transform_in_scene(art[i] as Node3D, _root)
		(
			assert_bool(spawn.is_equal_approx(marker))
			. override_failure_message("%s at %s" % [spawns[i].name, spawn])
			. is_true()
		)
		assert_vector(spawn.origin).is_equal_approx(
			Vector3(-9.0 + 2.0 * i, 0.0, SPAWN_Z), Vector3(EPS, EPS, EPS)
		)
		# Facing the window: a marker's forward (-Z) points south (+z).
		assert_float((-spawn.basis.z).z).is_equal_approx(1.0, EPS)


func test_the_host_reads_each_lobby_spawn_facing_the_window() -> void:
	# #1522: the host's marker reader carries each spawn's facing, which a joiner's Welcome and the
	# lobby's placement turn the player to: the window, south (+z).
	var read := MarkerReader.read_scene(LOBBY, FlatWorldQuery.new())
	assert_array(Array(read.errors)).is_empty()
	var faced := read.layout.facings(&"lobby_player")
	assert_int(faced.size()).is_equal(10)
	for facing: Vector3 in faced:
		assert_vector(facing).is_equal_approx(Vector3.BACK, Vector3(EPS, EPS, EPS))


func test_each_piece_is_a_separate_box_body_on_the_metre_grid() -> void:
	for piece_name: String in PIECES:
		var piece := _root.get_node_or_null(piece_name) as StaticBody3D
		assert_object(piece).override_failure_message(piece_name).is_not_null()
		if piece == null:
			continue
		assert_object(piece.get_parent()).is_same(_root)
		assert_int(piece.collision_layer & 1).override_failure_message(piece_name).is_equal(1)
		# Its origin, its north-west floor corner, on the grid; no turn.
		var origin := piece.transform.origin
		assert_float(origin.x).override_failure_message(piece_name).is_equal(roundf(origin.x))
		assert_float(origin.z).override_failure_message(piece_name).is_equal(roundf(origin.z))
		assert_float(origin.y).override_failure_message(piece_name).is_equal(0.0)
		assert_bool(piece.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()
		var shapes := piece.find_children("*", "CollisionShape3D", true, false)
		var meshes := piece.find_children("*", "MeshInstance3D", true, false)
		assert_int(shapes.size()).override_failure_message(piece_name).is_equal(1)
		assert_int(meshes.size()).override_failure_message(piece_name).is_equal(1)
		if shapes.size() != 1 or meshes.size() != 1:
			continue
		var shape := shapes[0] as CollisionShape3D
		var mesh := meshes[0] as MeshInstance3D
		var box := shape.shape as BoxShape3D
		assert_object(box).override_failure_message(piece_name).is_not_null()
		assert_object(mesh.mesh as BoxMesh).override_failure_message(piece_name).is_not_null()
		if box == null or not mesh.mesh is BoxMesh:
			continue
		# The look is the collider: the same box at the same place.
		assert_vector((mesh.mesh as BoxMesh).size).is_equal(box.size)
		assert_bool(mesh.transform.is_equal_approx(shape.transform)).is_true()
		# It stands on the floor with its north-west corner at the origin.
		var bounds := _bounds(shape)
		assert_vector(bounds.position).override_failure_message(piece_name).is_equal_approx(
			origin, Vector3(EPS, EPS, EPS)
		)


## Each box inside the hall's straight walls, apart from the others and clear of every collider of
## the art hall and its ship (the doors' frames, the pilasters, the ship's hull and legs).
func test_the_pieces_stand_inside_the_hall_apart_and_clear_of_the_art() -> void:
	var hall := LevelWorld.build(HALL)
	assert_array(hall.errors).is_empty()
	assert_int(hall.body_count()).is_greater(100)
	var placed: Array[AABB] = []
	for piece_name: String in PIECES:
		var shape := _shape_of(_root.get_node(piece_name))
		var bounds := _bounds(shape)
		var footprint := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		assert_bool(INSIDE.encloses(footprint)).override_failure_message(piece_name).is_true()
		for other: AABB in placed:
			assert_bool(bounds.intersects(other)).override_failure_message(piece_name).is_false()
		placed.append(bounds)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = LevelWorld.transform_in_scene(shape, _root).translated(
			Vector3(0.0, FLOOR_TOP_M, 0.0)
		)
		(
			assert_array(hall.space_state().intersect_shape(query, 1))
			. override_failure_message(piece_name + " meets the art hall")
			. is_empty()
		)
	for marker: Node3D in _markers(&"spawn_lobby_player"):
		var at := marker.position
		(
			assert_bool(INSIDE.has_point(Vector2(at.x, at.z)))
			. override_failure_message(marker.name)
			. is_true()
		)


## The host accepts the lobby: its world reads with no error and holds the hall's colliders.
func test_the_host_reads_the_lobby_world_without_errors() -> void:
	var world := LevelWorld.build(LOBBY)
	assert_array(world.errors).is_empty()
	assert_int(world.body_count()).is_greater(100)
	# The floor stands at y 0 under a spawn.
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 2.0, SPAWN_Z), Vector3(0, -1, SPAWN_Z)
	)
	var hit := world.space_state().intersect_ray(ray)
	assert_bool(hit.is_empty()).is_false()
	if not hit.is_empty():
		assert_float((hit["position"] as Vector3).y).is_equal_approx(0.0, 0.05)


## The host's world holds only what the client keeps (invariant 7: its sanity checks ask the same
## colliders the player walks on). The host never runs lobby_hall.gd's _ready, so a body the script
## frees, such as the ship package's Clearing ground (an endless WorldBoundary at y 0), must not be
## on layer 1: else the host has a floor past the window and under any hole in the art floor, and
## every floor check here passes with no art floor at all.
func test_the_host_world_holds_only_the_colliders_the_client_keeps() -> void:
	var host := LevelWorld.build(LOBBY)
	for at: Vector3 in [Vector3(60.0, 0.0, 0.0), Vector3(0.0, 0.0, 40.0), Vector3(-60, 0, -80)]:
		var ray := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 5.0, at + Vector3.DOWN * 5.0
		)
		var hit := host.space_state().intersect_ray(ray)
		var why := "a floor outside the hall at %s: %s" % [at, hit.get("position")]
		assert_bool(hit.is_empty()).override_failure_message(why).is_true()
	add_child(_root)
	await get_tree().process_frame
	var kept := LevelWorld.from_scene(_root, LOBBY)
	assert_int(host.body_count()).is_equal(kept.body_count())
	remove_child(_root)


## #1390: the bar's tap is one marker, inside the walls, clear of every collider by a capsule, with
## the Bar's edge within the tap's reach.
func test_the_tap_marker_stands_beside_the_bar_clear_of_every_collider() -> void:
	var taps := _markers(&"spawn_tap")
	assert_int(taps.size()).is_equal(1)
	var at := Vector2(taps[0].position.x, taps[0].position.z)
	assert_bool(INSIDE.has_point(at)).is_true()
	_assert_capsule_clear(LevelWorld.build(LOBBY), at, "the tap")
	var kind := load("res://content/stations/tap.tres") as StationKind
	assert_float(_distance_to_box(at, _shape_of(_root.get_node("Bar")))).is_less_equal(
		kind.radius_m
	)


## #1398: the pinball machine is one marker outside the Pinball box (#1399 owns that node), inside
## the walls, clear of every collider by a capsule, with the box's edge within the machine's reach.
func test_the_pinball_marker_stands_before_the_machine_clear_of_every_collider() -> void:
	var spots := _markers(&"spawn_pinball")
	assert_int(spots.size()).is_equal(1)
	assert_object(spots[0].get_parent()).is_same(_root)
	var at := Vector2(spots[0].position.x, spots[0].position.z)
	assert_bool(INSIDE.has_point(at)).is_true()
	_assert_capsule_clear(LevelWorld.build(LOBBY), at, "the pinball")
	var kind := load("res://content/stations/pinball.tres") as StationKind
	var reach := _distance_to_box(at, _shape_of(_root.get_node("Pinball")))
	assert_float(reach).is_less_equal(kind.radius_m)


## #1400: the pinball's client places (placeholders the engineer moves): the table's mount on the
## machine's top, the seated player's close-up camera and the display, one marker each under the
## Pinball node in PinballViews' groups, none in a spawn group.
func test_the_pinball_s_view_markers_sit_on_the_machine_once_each() -> void:
	var machine := _root.get_node("Pinball")
	for group: StringName in [
		PinballViews.TABLE_GROUP, PinballViews.CLOSE_UP_GROUP, PinballViews.DISPLAY_GROUP
	]:
		var found := _root.find_children("*", "Marker3D", true, false).filter(
			func(node: Node) -> bool: return node.is_in_group(group)
		)
		assert_int(found.size()).override_failure_message(String(group)).is_equal(1)
		var marker := found[0] as Node3D
		assert_object(marker.get_parent()).is_same(machine)
		for each: StringName in marker.get_groups():
			assert_bool(String(each).begins_with("spawn_")).is_false()
	var box := _bounds(_shape_of(machine))
	var mount := (machine as Node3D).transform * (machine.get_node("TableMount") as Node3D).position
	# On the box's top, its middle over the box.
	assert_float(mount.y).is_greater_equal(box.end.y)
	(
		assert_bool(
			Rect2(box.position.x, box.position.z, box.size.x, box.size.z).has_point(
				Vector2(mount.x, mount.z)
			)
		)
		. is_true()
	)


## The photo booth's volume (#1396) is the booth station's own cylinder on the Booth marker: the
## whole cylinder stands clear of every collider (the PhotoBooth box stays solid until the engineer
## opens it), and right in front of the PhotoBooth box, less than a capsule's width away.
func test_the_booth_marker_stands_before_the_photo_booth_its_volume_clear() -> void:
	var booths := _markers(&"spawn_booth")
	assert_int(booths.size()).is_equal(1)
	var at := Vector2(booths[0].position.x, booths[0].position.z)
	var kind := load("res://content/stations/booth.tres") as StationKind
	assert_bool(INSIDE.grow(-kind.radius_m).has_point(at)).is_true()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = kind.radius_m
	cylinder.height = _mode.player_rules.capsule_height_m
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.transform = Transform3D(
		Basis.IDENTITY, Vector3(at.x, FLOOR_TOP_M + cylinder.height / 2.0, at.y)
	)
	var world := LevelWorld.build(LOBBY)
	assert_array(world.space_state().intersect_shape(query, 1)).is_empty()
	var gap := _distance_to_box(at, _shape_of(_root.get_node("PhotoBooth"))) - kind.radius_m
	assert_float(gap).is_less(2.0 * _mode.player_rules.capsule_radius_m)


func test_nothing_but_the_floor_stands_where_the_bots_walk_in_the_lobby() -> void:
	var world := LevelWorld.build(LOBBY)
	var starts: Array[Vector2] = []
	for marker: Node3D in _markers(&"spawn_lobby_player"):
		starts.append(Vector2(marker.position.x, marker.position.z))
	assert_int(starts.size()).is_greater(0)
	for at: Vector2 in starts:
		_assert_capsule_clear(world, at, "the spawn at %s" % at)
	var walks := _lobby_walks()
	# voice_load walks in the lobby: the check is not empty.
	assert_int(walks.size()).is_greater(0)
	var query := _capsule_query(Vector2.ZERO)
	for walk: Array[Vector2] in walks:
		for start: Vector2 in starts:
			var from := start
			for to: Vector2 in walk:
				query.transform.origin = Vector3(from.x, query.transform.origin.y, from.y)
				query.motion = Vector3(to.x - from.x, 0.0, to.y - from.y)
				var free := world.space_state().cast_motion(query)
				(
					assert_float(free[0] if free.size() > 0 else 0.0)
					. override_failure_message("walk %s -> %s meets a collider" % [from, to])
					. is_equal(1.0)
				)
				from = to


## The capsule of a bot (its radius and a margin), standing above the floor at `at`, meets nothing.
func _assert_capsule_clear(world: LevelWorld, at: Vector2, what: String) -> void:
	(
		assert_array(world.space_state().intersect_shape(_capsule_query(at), 1))
		. override_failure_message(what + " is within a capsule of a collider")
		. is_empty()
	)


func _capsule_query(at: Vector2) -> PhysicsShapeQueryParameters3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = _mode.player_rules.capsule_radius_m + MARGIN_M
	capsule.height = maxf(_mode.player_rules.capsule_height_m, 2.0 * capsule.radius)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(
		Basis.IDENTITY, Vector3(at.x, FLOOR_TOP_M + capsule.height / 2.0, at.y)
	)
	return query


## The distance on the floor plan from `at` to the box of `shape`.
func _distance_to_box(at: Vector2, shape: CollisionShape3D) -> float:
	var box := _bounds(shape)
	var nearest := Vector2(
		clampf(at.x, box.position.x, box.end.x), clampf(at.y, box.position.z, box.end.z)
	)
	return at.distance_to(nearest)


## Each bot's walks to points in the lobby, in order. A scenario starts in the lobby and stays there
## through a wait for a join or for the Countdown (the departure is at Loading); any other wait
## leaves it (the match is played in the map), and a StepReturnToLobby brings the bot back. Each
## stay in the lobby is one walk.
func _lobby_walks() -> Array[Array]:
	var walks: Array[Array] = []
	for file: String in ScenarioLevels.scenario_paths():
		var scenario := load(file) as BotScenario
		if scenario == null or scenario.mode == null or scenario.mode.lobby_level != LOBBY:
			continue
		for bot: int in range(1, scenario.scripts.size() + 1):
			var walk: Array[Vector2] = []
			var in_lobby := true
			for step: ScenarioStep in scenario.steps_of(bot):
				if step is StepReturnToLobby:
					in_lobby = true
				elif step is StepWaitFor and not _stays_in_lobby(step as StepWaitFor):
					in_lobby = false
					if not walk.is_empty():
						walks.append(walk)
						walk = []
				elif in_lobby and step is StepWalkTo:
					var to := step as StepWalkTo
					if to.target != null and to.target.kind == ScenarioTarget.Kind.POINT:
						walk.append(Vector2(to.target.point.x, to.target.point.z))
			if not walk.is_empty():
				walks.append(walk)
	return walks


## Whether a wait ends while the bot is still in the lobby: a join, the lobby phase, the Countdown.
func _stays_in_lobby(wait: StepWaitFor) -> bool:
	if wait.event == &"PlayerJoined":
		return true
	var phase := str(wait.fields.get("phase", ""))
	return wait.event == &"PhaseChanged" and phase in ["lobby", "countdown"]


## The root's markers in group `group`, in scene-tree order.
func _markers(group: StringName) -> Array[Node3D]:
	var markers: Array[Node3D] = []
	for node: Node in _root.find_children("*", "Marker3D", true, false):
		if node.is_in_group(group):
			markers.append(node as Node3D)
	return markers


func _shape_of(body: Node) -> CollisionShape3D:
	var shapes := body.find_children("*", "CollisionShape3D", true, false)
	assert_int(shapes.size()).override_failure_message(str(body.name)).is_equal(1)
	return shapes[0] as CollisionShape3D


## A box collider's bounds in the level's space (the scene is not in a tree).
func _bounds(shape: CollisionShape3D) -> AABB:
	var size := (shape.shape as BoxShape3D).size
	return LevelWorld.transform_in_scene(shape, _root) * AABB(-size / 2.0, size)
