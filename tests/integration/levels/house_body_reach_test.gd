extends GdUnitTestSuite
## A launched body never rests out of everyone's reach on the House (728f, #850; the knockdown
## rework's KD12 (a), KD11, KD14 (a); levels/CLAUDE.md's "Thrown items", bodies too): kept
## by the level, with no rule in core/. In the host's world of the House (LevelWorld and
## HostWorldQuery, as house_knife_launch_test.gd builds them, and HostBodies), with the base mode's
## own data: every Strike of its item kinds that launches, the raise rule's TargetInReach, the
## PlayerRules' capsule, step and crouched eye.
##
## The spots a player can walk to: the floors of the House's pieces WALKABLE names (their Floor and
## stair-step colliders, never a crate's, a table's or the locked roof's top), reached on foot from
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
const BASE_MODE := "res://content/modes/base_mode.tres"
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
## The House's pieces no player walks: the roof, whose door is locked in the design
## (docs/design/house-map.md, decision 11).
const LOCKED: Array[String] = ["AtticAndRoof/Roof"]
## The flood fill's spacing, each step taken in two halves (a stair's tread is 0.3 m).
const STEP_M := 0.5
## How far a floor's top may lie from a spot's height, and the height band of the fill's cells.
const TOP_TOLERANCE_M := 0.02
const BAND_M := 0.05
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
## The walkable tops: per height band, an Array of [piece, AABB] whose top lies in it.
var _tops: Dictionary[int, Array] = {}
## The flood fill: each spot's piece by its cell, and the spots by their column.
var _spots: Dictionary[Vector3i, String] = {}
var _columns: Dictionary[Vector2i, Array] = {}
var _rejected: Dictionary[Vector3i, bool] = {}
var _pieces_in_scene: Array[String] = []


func before() -> void:
	_mode = load(BASE_MODE) as GameMode
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
	_mode = null
	_rules = null


func test_every_piece_of_the_house_is_listed_walkable_or_locked() -> void:
	var listed: Array[String] = WALKABLE + LOCKED
	listed.sort()
	var found := _pieces_in_scene.duplicate()
	found.sort()
	assert_array(found).is_equal(listed)


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
					if HouseThrows.on_roof(body.position):
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


## The walkable tops of house.tscn's pieces (their Floor and Stairs...Step box colliders, the
## scene read, never added to a tree, then freed), and every piece's name.
func _read_tops() -> void:
	var root := (load(HOUSE) as PackedScene).instantiate()
	for group: Node in root.get_children():
		for piece: Node in group.get_children():
			var key := "%s/%s" % [group.name, piece.name]
			_pieces_in_scene.append(key)
			if not WALKABLE.has(key):
				continue
			for node: Node in piece.find_children("*", "CollisionShape3D", true, false):
				var shape := node as CollisionShape3D
				var box := shape.shape as BoxShape3D
				var shape_name := String(shape.name)
				var walked := (
					shape_name.begins_with("Floor")
					or (shape_name.begins_with("Stairs") and shape_name.contains("Step"))
				)
				if box == null or not walked:
					continue
				var xf := LevelWorld.transform_in_scene(shape, root)
				var aabb := xf * AABB(-box.size / 2.0, box.size)
				var band := roundi(aabb.end.y / BAND_M)
				if not _tops.has(band):
					_tops[band] = []
				_tops[band].append([key, aabb])
	root.free()


## The piece whose walkable top `at` stands on (within a capsule's radius of its edge, as
## stand_floor_below reads the footprint), or "" for none.
func _piece_under(at: Vector3) -> String:
	var band := roundi(at.y / BAND_M)
	var found := ""
	var best := INF
	for b: int in [band - 1, band, band + 1]:
		for top: Array in _tops.get(b, []):
			var aabb: AABB = top[1]
			var off := absf(aabb.end.y - at.y)
			if off > TOP_TOLERANCE_M:
				continue
			# A top the point lies over beats one within a radius of it, then the nearer height
			# wins: the garden's plate lies 0.02 m over the yard's floor.
			if not _over(aabb, at, _rules.capsule_radius_m):
				continue
			if not _over(aabb, at, 0.0):
				off += 1.0
			if off < best:
				best = off
				found = top[0]
	return found


## Whether `at`'s x and z lie over `aabb`'s footprint grown by `grow`.
func _over(aabb: AABB, at: Vector3, grow: float) -> bool:
	return (
		at.x >= aabb.position.x - grow
		and at.x <= aabb.end.x + grow
		and at.z >= aabb.position.z - grow
		and at.z <= aabb.end.z + grow
	)


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
	# The roof's side of the attic's locked door (house_throws.gd's on_roof) is no spot either.
	if piece.is_empty() or HouseThrows.on_roof(at) or not _crouched_fits(at):
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


## A base-mode match on the House in the host's world, its ten peers joined, readied and loaded
## into the round (house_knife_launch_test.gd's _house_round).
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
