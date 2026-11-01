extends GdUnitTestSuite
## A launched body never rests out of everyone's reach on the House (728f, #850; the knockdown
## rework's KD12 (a), KD11, KD14 (a); levels/CLAUDE.md's "Thrown items", bodies too): kept
## by the level, with no rule in core/. In the host's world of the House (LevelWorld and
## HostWorldQuery, as house_knife_launch_test.gd builds them, and HostBodies), with the base mode's
## own data: every Strike of its item kinds that launches, the raise rule's TargetInReach, the
## PlayerRules' capsule, step and crouched eye. Played on the melee fixture
## (FixtureBaseModeWithMelee: the shipped base mode with its Round's strike and knives, which the
## M8 slice took out of the shipped match, #1497), so a knockdown still launches a body there.
##
## The spots a player can walk to: the floors of the House's pieces WALKABLE names (their walked
## colliders (_walked): the art's floor, slab and stair pieces of a room's Shell, the plot's Ground,
## a greybox piece's Floor and stair-step boxes; never a crate's, a table's, a wall's or the roof's
## top), each spot named after the smallest piece whose footprint holds it, reached on foot from
## the round's spawn markers by a flood fill of the crouched capsule (STEP_M apart, each step a
## rise of at most PlayerRules.step_height_m, any drop, the capsule clear of the level at each spot;
## WorldQuery.stand_floor_below, as the mover stands). A floor in a gap the fill does not reach is
## no spot, so a body there fails.
##
## From a sample of those spots (one open spot near the middle of each piece), each launching
## strike knocks a target down in each of DIRECTIONS directions, as house_knife_launch_test.gd
## does (five places at once, peers 1 to 10), and each body's rest must lie off the locked roof and
## within the raise's reach of a spot: TargetInReach's distance from the spot's feet, and
## TargetInSight's line from the spot's crouched eye to just above the rest. A rest on a table top,
## a crate or the roof counts only through that reach, never as a spot of its own; one under a table
## is held to the same reach (KD14 (a)). A rest out of reach fails with its place, its direction
## and its point: the House's layout is the humans' to change (#850), never a rule in core/.

const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
const HOUSE := "res://levels/house/house.tscn"
## The House's pieces (house.tscn: a floor group, then the piece) whose floors players walk: the
## yard and the street, the rooms, the terrace, the balcony, the stairs, the basement and the attic.
## A piece added to the House is listed here or in LOCKED.
const WALKABLE: Array[String] = [
	"Basement/Storage",
	"Basement/Darkroom",
	"Basement/Corridor",
	"Basement/BoilerRoom",
	"Basement/GeneratorHall",
	"Basement/PumpRoom",
	"Basement/SwitchRoom",
	"Basement/Passage",
	"GroundFloor/Yard",
	"GroundFloor/Street",
	"GroundFloor/Path",
	"GroundFloor/Driveway",
	"GroundFloor/Garden",
	"GroundFloor/Greenhouse",
	"GroundFloor/PhotoZone",
	"GroundFloor/Terrace",
	"GroundFloor/ChillZone",
	"GroundFloor/OutdoorStairs",
	"GroundFloor/Garage",
	"GroundFloor/WC",
	"GroundFloor/Pantry",
	"GroundFloor/DiningRoom",
	"GroundFloor/LivingRoom",
	"GroundFloor/Stairs",
	"GroundFloor/Kitchen",
	"GroundFloor/Hallway",
	"SecondFloor/Bedroom",
	"SecondFloor/KidsRoom",
	"SecondFloor/Landing",
	"SecondFloor/Study",
	"SecondFloor/Bathroom",
	"SecondFloor/GuestRoom",
	"SecondFloor/Balcony",
	"AtticAndRoof/Attic",
]
## The House's pieces players reach but do not walk to: none since the art's attic stair (#1080,
## art #188: a 40.4 degree flight under a long hatch, the engineer's option B on PR #1043; the
## hatch ladder before it locked the attic, #523). A piece no walk reaches goes here.
const LOCKED: Array[String] = []
## The Shell pieces of the art's rooms players never stand on: walls, fences, railings, roofs,
## glass, beams, pillars, the attic hatch's balustrade and the garage gate's lintel (its top at
## 3.0 m would count as a walked floor) (their names' starts; every other Shell piece is a floor, a
## slab, a porch or a flight of stairs).
const NOT_WALKED: Array[String] = [
	"wall_",
	"fence",
	"gate",
	"railing_",
	"roof_",
	"glass_",
	"garage_door",
	"gable",
	"beam_",
	"pillar_",
	"chimney",
	"dormer_gable",
	"hatch_guard",
	"gazebo_roof",
	"gazebo_finial",
]
## The flood fill's spacing, each step taken in two halves (a stair's tread is 0.3 m).
const STEP_M := 0.5
## Flights narrower than the fill's lattice can pass (the attic stair, art #188: 1.1 m between its
## stringer walls, so no column 0.5 m apart fits the capsule up it): each walked SPACING_M at a
## time from a spot of the lattice at its foot (map coordinates, its floor's y) along its corners
## to a lattice spot beyond its top, as house_stairs_test.gd walks it; the top joins the fill.
const NARROW_FLIGHTS := {
	"attic stair, landing to attic":
	[
		Vector3(30.5, 3.2, 29.5),
		Vector3(30.5, 3.2, 29.3),
		Vector3(25.7, 3.2, 29.3),
		Vector3(25.5, 3.2, 29.5),
	],
}
const SPACING_M := 0.1
## How far a floor's top may lie from a spot's height, and the height band of the fill's cells.
const TOP_TOLERANCE_M := 0.02
const BAND_M := 0.05
## How far a spot may lie above or below the floor of the piece it is named after (a storey).
const STOREY_M := 3.3
## The downward rays on the capsule's ring that look for a walked floor under a spot (_piece_under).
const RING_RAYS := 8
## 60 physics frames a second, 20 host ticks.
const FRAMES_PER_TICK := 3
## The attacker stands this far behind its target, against the launch (within a strike's reach).
const BEHIND_M := 0.5
const DIRECTIONS := 8
## Places launched from at once: one attacker and one target each (the base mode's ten players).
const PER_ROUND := 5
## Blows at most before a target is down.
const MOST_BLOWS := 20
const PEERS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
## The deal's spawn tag (PlacePlayers: the House's `spawn_round_player` markers).
const ROUND_SPAWN := &"round_player"

var _mode: GameMode
var _rules: PlayerRules
var _world: HostWorldQuery
var _house: LevelWorld
var _layouts: Dictionary[String, LevelLayout]
var _game: Match
var _seen := 0
## The walked colliders alone (_walked), and each walkable piece's footprint: [key, Rect2, floor y].
var _walked_world: LevelWorld
var _footprints: Array[Array] = []
## The flood fill: each spot's piece by its cell, and the spots by their column.
var _spots: Dictionary[Vector3i, String] = {}
var _columns: Dictionary[Vector2i, Array] = {}
var _rejected: Dictionary[Vector3i, bool] = {}
var _pieces_in_scene: Array[String] = []


func before() -> void:
	_mode = FixtureBaseModeWithMelee.mode()
	_rules = _mode.player_rules
	_world = HostWorldQuery.new(_rules.capsule_radius_m, _rules.crouch_height_m)
	for path: String in MarkerReader.level_paths_of(_mode):
		var level := LevelWorld.build(path)
		if path == HOUSE:
			_house = level
		_world.add_level(level)
	var levels := MarkerReader.read_levels(_mode, _world)
	_layouts = levels.layouts
	assert_array(Array(_world.errors)).is_empty()
	assert_array(Array(levels.errors)).is_empty()
	_read_tops()
	_world.use_level(HOUSE)
	_flood_fill()


func after_test() -> void:
	if _world != null:
		_world.bodies.clear()
	_game = null


func after() -> void:
	_world = null
	_house = null
	_walked_world = null
	_mode = null
	_rules = null


func test_every_piece_of_the_house_is_listed_walkable_or_locked() -> void:
	var listed: Array[String] = WALKABLE + LOCKED
	listed.sort()
	var found := _pieces_in_scene.duplicate()
	found.sort()
	assert_array(found).is_equal(listed)


func test_no_spawn_marker_stands_in_a_locked_piece() -> void:
	var root: Node = (load(HOUSE) as PackedScene).instantiate()
	var stuck: Array[String] = []
	for key: String in LOCKED:
		var locked := _piece_node(root, key)
		assert_object(locked).is_not_null()
		for marker: Node in locked.find_children("*", "Marker3D", true, false):
			for group: StringName in marker.get_groups():
				if String(group).begins_with(MarkerReader.GROUP_PREFIX):
					stuck.append("%s: %s in %s" % [marker.name, group, key])
	root.free()
	(
		assert_array(stuck)
		. override_failure_message("a spawn marker no one can walk to: %s" % ", ".join(stuck))
		. is_empty()
	)


func test_the_walk_from_the_spawn_reaches_every_walkable_piece() -> void:
	assert_int(_layouts[HOUSE].count(ROUND_SPAWN)).is_greater(0)
	var reached: Dictionary[String, bool] = {}
	for cell: Vector3i in _spots:
		reached[_spots[cell]] = true
	for piece: String in WALKABLE:
		(
			assert_bool(reached.has(piece))
			. override_failure_message("no spot reached on foot on %s" % piece)
			. is_true()
		)


func test_the_base_mode_has_a_launching_strike_and_a_raise_reach() -> void:
	assert_array(_launching()).is_not_empty()
	assert_float(_raise_reach()).is_greater(0.0)


func test_every_launch_from_a_spot_rests_within_a_raise_of_a_spot() -> void:
	var places := _places()
	assert_int(places.size()).is_equal(WALKABLE.size())
	var reach := _raise_reach()
	var out_of_reach: Array[String] = []
	var rests := 0
	for launching: Dictionary in _launching():
		var kind: ItemKind = launching["kind"]
		var strike: Strike = launching["strike"]
		var cooldown: int = launching["cooldown_ticks"]
		var names := places.keys()
		for first in range(0, names.size(), PER_ROUND):
			var batch: Array = names.slice(first, first + PER_ROUND)
			for k in DIRECTIONS:
				var angle := TAU * k / DIRECTIONS
				var towards := Vector3(sin(angle), 0.0, cos(angle))
				_round()
				var targets: Array[int] = []
				for i in batch.size():
					var at: Vector3 = places[batch[i]]
					_arm(2 * i + 1, kind.id, at - towards * BEHIND_M)
					FixtureItemModes.stand(_game, 2 * i + 2, at)
					targets.append(2 * i + 2)
				_knock_down_all(targets, towards, cooldown)
				for target: int in targets:
					var launched := _game.state.player(target).velocity
					var expected := towards * strike.launch_mps + Vector3.UP * strike.launch_up_mps
					assert_vector(launched).is_equal_approx(expected, Vector3.ONE * 0.001)
				await _until_rest(targets)
				for i in targets.size():
					var body := _game.state.player(targets[i])
					var label := (
						"%s's launch from %s towards %s rests at %s"
						% [kind.id, batch[i], towards, body.position]
					)
					assert_object(body.motion).override_failure_message(label).is_null()
					rests += 1
					if HouseThrows.on_roof(_world, body.position):
						out_of_reach.append(label + ", on the locked roof")
					elif not _in_reach_of_a_spot(body.position, reach):
						out_of_reach.append(label + ", out of a raise's reach of every spot")
				assert_array(Array(_game.diagnostics)).is_empty()
	assert_int(rests).is_equal(_launching().size() * places.size() * DIRECTIONS)
	assert_array(out_of_reach).override_failure_message("\n".join(out_of_reach)).is_empty()


## Every Strike of the mode's item kinds' actions that launches, with its item kind and the
## cooldown its action waits between blows (its Cooldown conditions, in host ticks).
func _launching() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for kind: ItemKind in _mode.item_kinds:
		for action: Rule in kind.actions:
			var cooldown := 1
			for condition: Condition in action.conditions:
				if condition is Cooldown:
					cooldown = maxi(cooldown, Ticks.from_seconds((condition as Cooldown).seconds))
			for effect: RuleEffect in action.effects:
				var strike := effect as Strike
				if strike != null and (strike.launch_mps > 0.0 or strike.launch_up_mps > 0.0):
					found.append({"kind": kind, "strike": strike, "cooldown_ticks": cooldown})
	return found


## The raise's reach: the TargetInReach of the mode's Raise rule.
func _raise_reach() -> float:
	for action: Rule in _mode.actions:
		if action.trigger != &"Raise":
			continue
		for condition: Condition in action.conditions:
			if condition is TargetInReach:
				return (condition as TargetInReach).reach_m
	return 0.0


## The walked colliders of house.tscn (_walked) in a world of their own, every piece's name (the
## nodes under a floor group that declare size_m, the map's rooms) and each walkable piece's
## footprint (its origin's x and z, size_m, its floor at its origin's height). The scene is read,
## never added to a tree, then freed.
func _read_tops() -> void:
	var root := (load(HOUSE) as PackedScene).instantiate()
	for group: Node in root.get_children():
		for piece: Node in group.get_children():
			if not piece.has_meta(&"size_m"):
				continue
			var key := "%s/%s" % [group.name, piece.name]
			_pieces_in_scene.append(key)
			if not WALKABLE.has(key):
				continue
			var origin := LevelWorld.transform_in_scene(piece as Node3D, root).origin
			var size: Vector2i = piece.get_meta(&"size_m")
			var rect := Rect2(Vector2(origin.x, origin.z), Vector2(size))
			_footprints.append([key, rect, origin.y])
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		shape.disabled = shape.disabled or not _walked(shape, root)
	_walked_world = LevelWorld.from_scene(root, HOUSE)
	root.free()


## Whether players stand on `shape`: under a walkable piece, one of its Shell's floor, slab or
## stair pieces (the art's rooms), or a Floor or stair-step box (a greybox piece: the House has
## none since the garage's art, #1052); outside the pieces, the plot's Ground and its outdoor
## flight from the basement's passage up to the yard (its Shell's stairs_outdoor_ pieces).
func _walked(shape: CollisionShape3D, root: Node) -> bool:
	var path := String(root.get_path_to(shape)).split("/")
	if path.size() > 2 and path[0] == "Outdoor":
		return (
			path[1] == "Ground" or (path[1] == "Shell" and path[2].begins_with("stairs_outdoor_"))
		)
	if path.size() < 3 or not WALKABLE.has("%s/%s" % [path[0], path[1]]):
		return false
	var piece := root.get_node(NodePath("%s/%s" % [path[0], path[1]]))
	if not piece.has_node(^"Shell"):
		var shape_name := String(shape.name)
		return (
			shape_name.begins_with("Floor")
			or (shape_name.begins_with("Stairs") and shape_name.contains("Step"))
		)
	if path[2] != "Shell" or path.size() < 4:
		return false
	for start: String in NOT_WALKED:
		if path[3].begins_with(start):
			return false
	return true


## The piece `at` stands on: none unless a walked collider lies under the capsule's footprint
## (its middle or a ring just inside its radius, by downward rays: a cylinder query misses the
## plot's trimesh ground) within TOP_TOLERANCE_M of its feet (so never a crate's, a table's or a
## wall's top), then the walkable piece whose footprint holds `at` with its floor nearest `at`'s
## height (a storey at most), the smaller footprint on a tie (the garden in the yard). "" for none.
## The piece "Group/Piece" under the House scene's `root`, or null.
func _piece_node(root: Node, key: String) -> Node:
	var parts := key.split("/")
	for group: Node in root.get_children():
		if group.name == parts[0]:
			return group.get_node_or_null(parts[1])
	return null


func _piece_under(at: Vector3) -> String:
	var space := _walked_world.space_state()
	var walked := false
	for k in RING_RAYS + 1:
		var angle := TAU * k / RING_RAYS
		var ring := 0.0 if k == RING_RAYS else _rules.capsule_radius_m * 0.9
		var top := at + Vector3(cos(angle) * ring, TOP_TOLERANCE_M, sin(angle) * ring)
		var ray := PhysicsRayQueryParameters3D.create(
			top, top + Vector3.DOWN * (3.0 * TOP_TOLERANCE_M + 0.02), LevelWorld.WORLD_LAYER
		)
		if not space.intersect_ray(ray).is_empty():
			walked = true
			break
	if not walked:
		return ""
	var found := ""
	var best := INF
	for footprint: Array in _footprints:
		var rect: Rect2 = footprint[1]
		if not rect.has_point(Vector2(at.x, at.z)):
			continue
		var off := absf(at.y - (footprint[2] as float))
		if off > STOREY_M:
			continue
		var score := off * 1000.0 + rect.get_area() * 0.001
		if score < best:
			best = score
			found = footprint[0]
	return found


## The flood fill from the round's spawn markers, breadth first.
func _flood_fill() -> void:
	var queue: Array[Vector3] = []
	for marker: Vector3 in _layouts[HOUSE].positions(ROUND_SPAWN):
		var on_lattice := Vector3(snappedf(marker.x, STEP_M), marker.y, snappedf(marker.z, STEP_M))
		var start := _world.stand_floor_below(on_lattice + Vector3.UP * _rules.step_height_m)
		if _visit(start):
			queue.append(start)
	var head := 0
	var ways: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	while head < queue.size():
		var from := queue[head]
		head += 1
		for way: Vector2 in ways:
			var half := way * STEP_M / 2.0
			var middle := _step_from(from, half)
			if middle == WorldQuery.NO_FLOOR:
				continue
			var to := _step_from(middle, half)
			if to != WorldQuery.NO_FLOOR and _visit(to):
				queue.append(to)
		if head == queue.size():
			for flight: String in NARROW_FLIGHTS:
				var top := _walk_flight(NARROW_FLIGHTS[flight] as Array)
				if top != WorldQuery.NO_FLOOR and _visit(top):
					queue.append(top)


## The spot at the end of a narrow flight's walk (NARROW_FLIGHTS) when the fill has reached its
## start and every SPACING_M of it is a step a crouched player fits on, the capsule resting on the
## highest floor under its circle (on a flight's slope its up-hill edge); else NO_FLOOR.
func _walk_flight(corners: Array) -> Vector3:
	var start := corners[0] as Vector3
	# The fill stands where the mover does: on the flight's first tread when the capsule's rim
	# overhangs it, so the start's cell is that of the floor stood on, not the map's floor height.
	var at := _world.stand_floor_below(start + Vector3.UP * _rules.step_height_m)
	if at == WorldQuery.NO_FLOOR:
		return at
	var cell := Vector3i(roundi(at.x / STEP_M), roundi(at.y / BAND_M), roundi(at.z / STEP_M))
	if not _spots.has(cell):
		return WorldQuery.NO_FLOOR
	for i in range(1, corners.size()):
		var leg := (corners[i] as Vector3) - (corners[i - 1] as Vector3)
		var steps := ceili(Vector2(leg.x, leg.z).length() / SPACING_M)
		for k in steps:
			at = _step_from(at, Vector2(leg.x, leg.z) / steps)
			if at == WorldQuery.NO_FLOOR or not _crouched_fits(_resting(at)):
				return WorldQuery.NO_FLOOR
	return at


## `at` lifted to the highest floor within a step above it under the capsule's circle (its centre
## and RING_RAYS points on its rim), where the capsule rests.
func _resting(at: Vector3) -> Vector3:
	var top := at.y
	for k in RING_RAYS:
		var angle := TAU * k / RING_RAYS
		var rim := Vector3(cos(angle), 0.0, sin(angle)) * _rules.capsule_radius_m
		var under := _world.stand_floor_below(at + rim + Vector3.UP * _rules.step_height_m)
		if under != WorldQuery.NO_FLOOR:
			top = maxf(top, under.y)
	return Vector3(at.x, top, at.z)


## The floor a player at `from` steps onto `offset` away: no higher than a step, any drop.
func _step_from(from: Vector3, offset: Vector2) -> Vector3:
	var above := Vector3(from.x + offset.x, from.y + _rules.step_height_m, from.z + offset.y)
	return _world.stand_floor_below(above)


## Whether `at` is a new spot: on a walkable top, the crouched capsule clear there.
func _visit(at: Vector3) -> bool:
	if at == WorldQuery.NO_FLOOR:
		return false
	var cell := Vector3i(roundi(at.x / STEP_M), roundi(at.y / BAND_M), roundi(at.z / STEP_M))
	if _spots.has(cell) or _rejected.has(cell):
		return false
	var piece := _piece_under(at)
	if piece.is_empty() or not _crouched_fits(at):
		_rejected[cell] = true
		return false
	_spots[cell] = piece
	var column := Vector2i(cell.x, cell.z)
	if not _columns.has(column):
		_columns[column] = []
	_columns[column].append(at)
	return true


## Whether a crouching player's capsule at `at` (lifted by Items.SURFACE_CLEARANCE_M and narrowed
## by it: touching a floor or a wall is not a hit) is clear of the level (KD11).
func _crouched_fits(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = _rules.capsule_radius_m - Items.SURFACE_CLEARANCE_M
	capsule.height = _rules.crouch_height_m
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := at + Vector3.UP * (_rules.crouch_height_m / 2.0 + Items.SURFACE_CLEARANCE_M)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return _house.space_state().intersect_shape(query, 1).is_empty()


## Whether a spot lies within the raise's reach of `rest`: within `reach` of the spot's feet
## (TargetInReach) and in sight from its crouched eye to just above the rest (TargetInSight).
func _in_reach_of_a_spot(rest: Vector3, reach: float) -> bool:
	var span := ceili(reach / STEP_M)
	var middle := Vector2i(roundi(rest.x / STEP_M), roundi(rest.z / STEP_M))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for spot: Vector3 in _columns.get(middle + Vector2i(dx, dz), []):
				if spot.distance_to(rest) > reach:
					continue
				var eye := spot + Vector3.UP * _rules.crouch_eye_height_m
				if _world.line_of_sight(eye, Items.lifted(rest)):
					return true
	return false


## One launch place per walkable piece: of its spots with every neighbour of the fill's lattice a
## spot too (room for the attacker behind in any direction), the one nearest its spots' middle.
func _places() -> Dictionary[String, Vector3]:
	var by_piece: Dictionary[String, Array] = {}
	for column: Vector2i in _columns:
		for spot: Vector3 in _columns[column]:
			var cell := Vector3i(column.x, roundi(spot.y / BAND_M), column.y)
			var piece: String = _spots[cell]
			if not by_piece.has(piece):
				by_piece[piece] = []
			by_piece[piece].append(spot)
	var found: Dictionary[String, Vector3] = {}
	for piece: String in WALKABLE:
		var spots: Array = by_piece.get(piece, [])
		if spots.is_empty():
			continue
		var middle := Vector3.ZERO
		for spot: Vector3 in spots:
			middle += spot
		middle /= spots.size()
		var best := INF
		for spot: Vector3 in spots:
			var distance := Vector2(spot.x - middle.x, spot.z - middle.z).length()
			if distance < best and _open(spot):
				best = distance
				found[piece] = spot
	return found


## Whether every lattice neighbour of `spot` (the diagonals too) is a spot within a step's height.
func _open(spot: Vector3) -> bool:
	var column := Vector2i(roundi(spot.x / STEP_M), roundi(spot.z / STEP_M))
	for dx: int in [-1, 0, 1]:
		for dz: int in [-1, 0, 1]:
			var near := false
			for other: Vector3 in _columns.get(column + Vector2i(dx, dz), []):
				if absf(other.y - spot.y) <= _rules.step_height_m:
					near = true
			if not near:
				return false
	return true


## A melee fixture match (the base mode with the Round's strike) on the House in the host's
## world, its ten peers joined, readied and loaded into the round (house_knife_launch_test.gd's
## _house_round).
func _round() -> void:
	_game = Match.new(_mode, 7, _world, _layouts)
	assert_array(Array(_game.refusals)).is_empty()
	_game.state.map = HOUSE
	_game.keep_history = true
	_game.start(0)
	for peer: int in PEERS:
		FixtureBaseMode.join(_game, peer)
	for peer: int in PEERS:
		FixtureBaseMode.ready(_game, peer)
	for i in 1000:
		if _game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(_game, 1)
	for peer: int in PEERS:
		FixtureBaseMode.load_ack(_game, peer)
	for i in 1000:
		if _game.phase_id() == &"round":
			break
		FixtureModes.run_ticks(_game, 1)
	assert_str(_game.phase_id()).is_equal("round")
	_seen = _game.emitted().size()


## Each target's attacker (the peer before it) strikes it along `towards`, `cooldown` ticks
## between blows, until every target is down.
func _knock_down_all(targets: Array[int], towards: Vector3, cooldown: int) -> void:
	for blow in MOST_BLOWS:
		for target: int in targets:
			FixtureCombatModes.use(_game, target - 1, towards)
		_carry_out()
		var down := true
		for target: int in targets:
			down = down and _game.state.player(target).life == PlayerState.Life.DOWNED
		if down:
			break
		FixtureModes.run_ticks(_game, cooldown)
	for target: int in targets:
		(
			assert_int(_game.state.player(target).life)
			. override_failure_message("peer %d not knocked down" % target)
			. is_equal(PlayerState.Life.DOWNED)
		)
		assert_array(FixtureModes.rejections(_game, target - 1)).is_empty()


## The host's loop until every target's motion ends: physics frames, and every FRAMES_PER_TICK of
## them a host tick headed by the bodies' reports.
func _until_rest(targets: Array[int]) -> void:
	var limit := (int(_rules.longest_motion_s * Ticks.RATE) + 10) * FRAMES_PER_TICK
	var frame := 0
	while frame < limit and not _all_at_rest(targets):
		await get_tree().physics_frame
		frame += 1
		if frame % FRAMES_PER_TICK == 0:
			_host_tick()


func _all_at_rest(targets: Array[int]) -> bool:
	for target: int in targets:
		if _game.state.player(target).motion != null:
			return false
	return true


## One host tick: the reports, stamped with it, then the tick, then the directives.
func _host_tick() -> void:
	var at_tick := _game.ticked_through() + 1
	for report: MatchCommand in _world.bodies.reports():
		report.tick = at_tick
		_game.apply(report)
	_carry_out()
	_game.tick(at_tick)
	_carry_out()


## LaunchBody and StopBody emitted since the last call, carried out as HostSession does.
func _carry_out() -> void:
	var emitted := _game.emitted()
	for i in range(_seen, emitted.size()):
		var event := emitted[i].event
		if event is LaunchBodyEvent:
			var launch := event as LaunchBodyEvent
			_world.bodies.launch(launch.peer, launch.epoch, launch.origin, launch.velocity)
		elif event is StopBodyEvent:
			_world.bodies.stop((event as StopBodyEvent).peer)
	_seen = emitted.size()


## Puts `peer` at `at` with an item of `kind_id` in its hand, straight into the match state.
func _arm(peer: int, kind_id: StringName, at: Vector3) -> void:
	FixtureItemModes.stand(_game, peer, at)
	var item := FixtureItemModes.lay(_game, kind_id, at)
	item.where = ItemState.Where.HAND
	item.holder = peer
	_game.state.player(peer).held_item = item.id
