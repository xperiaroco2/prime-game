extends GdUnitTestSuite
## The lobby hall greybox (#1354; GDD §3 Base mode, the Lobby bullet; docs/design/m8-match.md §1):
## one walled hall on the lobby's one floor, with the skat (closed), the bar, the photo booth, the
## pinball machine and the mirror each a separate box the engineer can move in the editor, the
## Earth window and the sealed door as looks on the walls. Every size and place is a placeholder,
## "not a decision" (the MVP content ADR): the engineer sets the layout on this scene.
## The guards: each piece is its own layer-1 box body under the root, on the whole-metre grid,
## standing on the floor inside the walls, apart from the other pieces; and nothing but the floor
## stands where the bot scenarios walk in the lobby (their fake world is one flat floor, §9.7,
## content_modes_test's test_the_scenarios_levels_are_flat): no collider within a capsule and a
## margin of a lobby marker or of a straight walk a scenario takes before it first waits.

const LOBBY := "res://levels/lobby/lobby.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
const SCENARIOS_DIR := "res://content/scenarios/"
## The pieces of the hall, each a node of its own under the root.
const PIECES: Array[String] = ["Skat", "Bar", "PhotoBooth", "Pinball", "Mirror"]
const WALLS: Array[String] = ["North", "South", "West", "East"]
## The level-piece ADR's door opening (levels/CLAUDE.md): 1.4 x 2.15 m.
const DOOR_SIZE := Vector2(1.4, 2.15)
## Beyond a bot's capsule radius: room to pass a collider's edge.
const MARGIN_M := 0.1
const EPS := 1e-4

var _root: Node3D


func before_test() -> void:
	_root = auto_free((load(LOBBY) as PackedScene).instantiate()) as Node3D


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


func test_the_pieces_stand_inside_the_walls_and_apart() -> void:
	var inside := _inner_rect()
	assert_bool(inside.has_area()).is_true()
	var placed: Array[AABB] = []
	for piece_name: String in PIECES:
		var bounds := _bounds(_shape_of(_root.get_node(piece_name)))
		var footprint := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		assert_bool(inside.encloses(footprint)).override_failure_message(piece_name).is_true()
		for other: AABB in placed:
			assert_bool(bounds.intersects(other)).override_failure_message(piece_name).is_false()
		placed.append(bounds)
	for marker: Node3D in _markers():
		var at := marker.position
		(
			assert_bool(inside.has_point(Vector2(at.x, at.z)))
			. override_failure_message(marker.name)
			. is_true()
		)


func test_the_walls_and_the_floor_close_the_hall() -> void:
	var floor_bounds := _bounds(_shape_of(_root.get_node("Floor")))
	assert_float(floor_bounds.end.y).is_equal_approx(0.0, EPS)
	for wall_name: String in WALLS:
		var wall := _root.get_node_or_null("Walls/" + wall_name) as StaticBody3D
		assert_object(wall).override_failure_message(wall_name).is_not_null()
		if wall == null:
			continue
		assert_int(wall.collision_layer & 1).is_equal(1)
		var bounds := _bounds(_shape_of(wall))
		# On the floor, within it, and higher than a player jumps.
		assert_float(bounds.position.y).override_failure_message(wall_name).is_equal_approx(
			0.0, EPS
		)
		assert_bool(
			floor_bounds.grow(EPS).encloses(AABB(bounds.position - Vector3(0, 1, 0), bounds.size))
		)
		assert_float(bounds.size.y).override_failure_message(wall_name).is_greater_equal(3.0)
	# The walls meet at the corners: the inner rectangle is closed on all four sides.
	var inside := _inner_rect()
	for wall_name: String in WALLS:
		var bounds := _bounds(_shape_of(_root.get_node("Walls/" + wall_name)))
		var footprint := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		if wall_name == "North" or wall_name == "South":
			(
				assert_bool(
					footprint.position.x <= inside.position.x and footprint.end.x >= inside.end.x
				)
				. is_true()
			)
		else:
			(
				assert_bool(
					footprint.position.y <= inside.position.y and footprint.end.y >= inside.end.y
				)
				. is_true()
			)


func test_the_window_and_the_sealed_door_are_looks_on_the_walls() -> void:
	var window := _root.get_node_or_null("EarthWindow") as MeshInstance3D
	var door := _root.get_node_or_null("SealedDoor") as MeshInstance3D
	assert_object(window).is_not_null()
	assert_object(door).is_not_null()
	if window == null or door == null:
		return
	# Looks only: the wall behind each keeps players in.
	assert_array(window.find_children("*", "CollisionShape3D", true, false)).is_empty()
	assert_array(door.find_children("*", "CollisionShape3D", true, false)).is_empty()
	var door_size := (door.mesh as BoxMesh).size
	assert_vector(Vector2(maxf(door_size.x, door_size.z), door_size.y)).is_equal_approx(
		DOOR_SIZE, Vector2(EPS, EPS)
	)
	assert_float(door.transform.origin.y - door_size.y / 2.0).is_equal_approx(0.0, EPS)
	var inside := _inner_rect().grow(EPS)
	for look: MeshInstance3D in [window, door]:
		var at := look.transform.origin
		var half := (look.mesh as BoxMesh).size / 2.0
		# Against a wall's inner face, within the hall.
		var on_x := (
			absf(at.x - half.x - inside.position.x) < EPS
			or absf(at.x + half.x - inside.end.x) < EPS
		)
		var on_z := (
			absf(at.z - half.z - inside.position.y) < EPS
			or absf(at.z + half.z - inside.end.y) < EPS
		)
		assert_bool(on_x or on_z).override_failure_message(look.name).is_true()


func test_nothing_but_the_floor_stands_where_the_bots_walk_in_the_lobby() -> void:
	var mode := load(BASE_MODE) as GameMode
	assert_str(mode.lobby_level).is_equal(LOBBY)
	var clearance := mode.player_rules.capsule_radius_m + MARGIN_M
	var blocks: Array[Rect2] = []
	for shape: Node in _root.find_children("*", "CollisionShape3D", true, false):
		if shape.get_parent() == _root.get_node("Floor"):
			continue
		var bounds := _bounds(shape as CollisionShape3D)
		blocks.append(
			Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z).grow(
				clearance
			)
		)
	assert_int(blocks.size()).is_greater(PIECES.size())
	var starts: Array[Vector2] = []
	for marker: Node3D in _markers():
		starts.append(Vector2(marker.position.x, marker.position.z))
	assert_int(starts.size()).is_greater(0)
	for at: Vector2 in starts:
		for block: Rect2 in blocks:
			(
				assert_bool(block.has_point(at))
				. override_failure_message("marker at %s" % at)
				. is_false()
			)
	var walks := _lobby_walks()
	# voice_load walks in the lobby: the check is not empty.
	assert_int(walks.size()).is_greater(0)
	for walk: Array[Vector2] in walks:
		for start: Vector2 in starts:
			var from := start
			for to: Vector2 in walk:
				for block: Rect2 in blocks:
					(
						assert_bool(_crosses(from, to, block))
						. override_failure_message("walk %s -> %s crosses %s" % [from, to, block])
						. is_false()
					)
				from = to


## Each bot's walks to points in the lobby, in order: a scenario starts in the lobby, so the
## StepWalkTo steps before its first StepWaitFor (any later phase is waited for).
func _lobby_walks() -> Array[Array]:
	var walks: Array[Array] = []
	for file: String in DirAccess.get_files_at(SCENARIOS_DIR):
		if not file.ends_with(".tres"):
			continue
		var scenario := load(SCENARIOS_DIR + file) as BotScenario
		if scenario == null or scenario.mode == null or scenario.mode.lobby_level != LOBBY:
			continue
		for bot: int in range(1, scenario.scripts.size() + 1):
			var walk: Array[Vector2] = []
			for step: ScenarioStep in scenario.steps_of(bot):
				if step is StepWaitFor:
					break
				var to := step as StepWalkTo
				if to != null and to.target != null and to.target.kind == ScenarioTarget.Kind.POINT:
					walk.append(Vector2(to.target.point.x, to.target.point.z))
			if not walk.is_empty():
				walks.append(walk)
	return walks


## Whether the segment from `from` to `to` meets `rect` (the slab test).
func _crosses(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var t_in := 0.0
	var t_out := 1.0
	var delta := to - from
	for axis: int in 2:
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(delta[axis]) < EPS:
			if from[axis] < lo or from[axis] > hi:
				return false
			continue
		var t0 := (lo - from[axis]) / delta[axis]
		var t1 := (hi - from[axis]) / delta[axis]
		t_in = maxf(t_in, minf(t0, t1))
		t_out = minf(t_out, maxf(t0, t1))
		if t_in > t_out:
			return false
	return true


## The hall's floor plan inside the walls (x, z): from the west and north walls' inner faces to the
## east and south walls'.
func _inner_rect() -> Rect2:
	var north := _bounds(_shape_of(_root.get_node("Walls/North")))
	var south := _bounds(_shape_of(_root.get_node("Walls/South")))
	var west := _bounds(_shape_of(_root.get_node("Walls/West")))
	var east := _bounds(_shape_of(_root.get_node("Walls/East")))
	var from := Vector2(west.end.x, north.end.z)
	return Rect2(from, Vector2(east.position.x, south.position.z) - from)


func _markers() -> Array[Node3D]:
	var markers: Array[Node3D] = []
	for node: Node in _root.find_children("*", "Marker3D", true, false):
		if node.is_in_group(&"spawn_lobby_player"):
			markers.append(node as Node3D)
	return markers


func _shape_of(body: Node) -> CollisionShape3D:
	var shapes := body.find_children("*", "CollisionShape3D", true, false)
	assert_int(shapes.size()).override_failure_message(str(body.name)).is_equal(1)
	return shapes[0] as CollisionShape3D


## The box collider's bounds in the level's space (the scene is not in a tree: the transforms of
## its ancestors up to the root, in turn).
func _bounds(shape: CollisionShape3D) -> AABB:
	var placed := shape.transform
	var node := shape.get_parent()
	while node != _root and node is Node3D:
		placed = (node as Node3D).transform * placed
		node = node.get_parent()
	var size := (shape.shape as BoxShape3D).size
	return placed * AABB(-size / 2.0, size)
