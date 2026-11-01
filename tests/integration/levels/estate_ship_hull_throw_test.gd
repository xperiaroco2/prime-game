extends GdUnitTestSuite
## No throw from a floor a player walks in or by the art ship's hull leaves an item out of every
## player's pick-up inside the hull's outline (#1551, follow-up of #1543; the throwing ADR, TD5
## (a)): the ramp, the throat, the hall, its corridors and the lens rooms are walked, and a ledge or
## a gap there (a wall top, a gap behind a wall, an alcove's lintel, the jaw's flank over the ramp)
## could hold a thrown item where no player picks it up. The ship's top is the roof sweep's
## (estate_roof_throw_test.gd), its low wing edges the wing sweep's
## (estate_ship_wing_throw_test.gd).
## The floors walked (_walk): a flood fill of the crouched capsule (house_body_reach_test.gd's
## fit) from the ground at the four sides of the ship's outline grown by WALK_BOX_M, WALK_STEP_M
## apart, each move a step or a jump up (PlayerRules' jump, with the headroom for it) or any drop.
## The throwers: one walked floor per THROWER_CELL_M cell and THROWER_BAND_M band, at least
## THROWER_LOWEST_M up; and from the ground (below THROWER_LOWEST_M: the walked ground by and under
## the ship and the roof sweep's spots on its rings, EstateThrows.spots), one per GROUND_CELL_M
## cell, whose rests count only in the hull: under its roof (the ray up from them meets the ship:
## the wing sweep has those under open sky) and THROWER_LOWEST_M or more up (the ground under the
## belly, a crawl space no player enters, still holds an item out of reach: #1560). From each (its
## standing eye, or its crouched one where a player only crouches, _stands_up), the roof sweep's
## fan (HouseThrows) is flown as FlightTicks flies it, with the Throw rule's ThrowItem numbers,
## toward the outline only (a rest lies on its throw's plan path, _towards).
## Each rest inside the outline, off the ship's top, must pass the PickUp rule as it is (#507's
## answer: InSight and the jump included) from a walked floor: InReach (reach_m) from the feet
## lifted by up to the jump, the headroom allowing, and InSight from the standing or the crouched
## eye (Items.eye_of). A later change of the numbers or of the ship that holds an item out of reach
## inside the hull turns this red; so does the ship without its hull caps (Hull's shapes named
## CAP_PREFIX, #1551).

const EstateThrows := preload("res://tests/integration/levels/estate_throws.gd")
const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
const SHIP := "Ship"
## The hull's invisible caps (Hull's shapes named so), turned off for the uncapped check.
const CAP_PREFIX := "Cap"
## The walk's lattice and its box: the ship's outline grown by this much.
const WALK_STEP_M := 0.25
const WALK_BOX_M := 1.0
## Walked floors this far apart in height are two floors of a column.
const WALK_BAND_M := 0.5
## The throwers' thinning (one per cell and band) and the lowest of them.
const THROWER_CELL_M := 2.0
const THROWER_BAND_M := 0.5
const THROWER_LOWEST_M := 0.4
## The ground's throwers are thinned coarser: its floors are flat, so a cell's fan rests much as
## its neighbours' (about 14 s at 2 m against 6 at 3 m).
const GROUND_CELL_M := 3.0
## A rest's ray up this long, for whether it lies under the hull's roof.
const SKY_M := 30.0
## A throw's plan path, for whether it can rest inside the outline: longer than any throw's reach,
## sampled this finely.
const PLAN_M := 40.0
const PLAN_STEP_M := 0.1
## The buckets of the walked feet, for the feet near a rest.
const BUCKET_M := 1.0
## Rests closer than this share a pick-up check.
const REST_GRID_M := 0.1
## A red rest is reported once per cell of this size.
const RED_CELL_M := 0.5
## The hall's middle and the two lens rooms' floors (docs/design/estate-map.md §5a), each walked.
const HALL := Vector3(114.5, 1.2, 72.0)
const LENS_WEST := Vector3(105.0, 1.2, 73.0)
const LENS_EAST := Vector3(127.0, 1.2, 73.0)
## A corridor's thrower by the gap behind its wall (#1551: without the caps an item thrown from
## here falls behind the wall or rests on its top), and how far from it the sweep's throwers are
## taken.
const CORRIDOR := Vector3(111.0, 1.2, 73.0)
const CORRIDOR_SPOTS_M := 1.5

var _level: LevelWorld
var _world: HostWorldQuery
var _rules: PlayerRules
var _throw: ThrowItem
var _reach_m := 0.0
var _ship := Rect2()
## Walked floors by lattice cell (x, band, z) and by bucket (x, z floored by BUCKET_M).
var _walked: Dictionary[Vector3i, Vector3] = {}
var _feet: Dictionary[Vector2i, Array] = {}
var _throwers: Array[Vector3] = []
var _ground_throwers: Array[Vector3] = []


func before() -> void:
	var mode := load(BASE_MODE) as GameMode
	_rules = mode.player_rules
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			for effect: RuleEffect in rule.effects:
				if effect is ThrowItem:
					_throw = effect as ThrowItem
		var picks := false
		var reach := 0.0
		for condition: Condition in rule.conditions:
			if condition is ItemOnGround:
				picks = true
			if condition is InReach:
				reach = (condition as InReach).reach_m
		if picks and reach > 0.0:
			_reach_m = reach
	_level = LevelWorld.build(EstateDoc.MAP)
	_world = _world_of_level(_level)
	var tops := EstateThrows.tops(_world)
	if tops.has(SHIP):
		_ship = tops[SHIP]["rect"]
	_walk()
	var high: Array[Vector3] = []
	var ground: Array[Vector3] = []
	for at: Vector3 in _walked.values():
		if at.y < THROWER_LOWEST_M:
			ground.append(at)
		else:
			high.append(at)
	for at: Vector3 in EstateThrows.spots(_world, _rules.eye_height_m).get(SHIP, []):
		if at.y < THROWER_LOWEST_M:
			ground.append(at)
	_throwers = _thinned(high, THROWER_CELL_M)
	_ground_throwers = _thinned(ground, GROUND_CELL_M)


func after() -> void:
	_world = null
	_level = null
	_rules = null
	_throw = null
	_walked.clear()
	_feet.clear()
	_throwers.clear()
	_ground_throwers.clear()


func test_the_numbers_the_ship_and_the_walk_are_read() -> void:
	assert_array(Array(_world.errors)).is_empty()
	assert_object(_throw).is_not_null()
	assert_float(_reach_m).is_greater(0.0)
	assert_bool(_ship.has_area()).is_true()
	assert_bool(_throwers.is_empty()).is_false()
	assert_bool(_ground_throwers.is_empty()).is_false()


func test_the_walk_reaches_the_hall_and_both_lens_rooms() -> void:
	# The sweep is not blind inside: its walk climbs the ramp into the hall and its wings.
	for floor_point: Vector3 in [HALL, LENS_WEST, LENS_EAST]:
		(
			assert_bool(_walked_near(floor_point))
			. override_failure_message("no walked floor by %s" % floor_point)
			. is_true()
		)


func test_no_throw_inside_the_hull_rests_out_of_reach() -> void:
	var red := _red_rests(_level, _world, _throwers)
	assert_array(red).override_failure_message("\n".join(red.slice(0, 40))).is_empty()


func test_no_throw_from_the_ground_rests_out_of_reach_under_the_hull_s_roof() -> void:
	# The ground by and under the ship throws into the mouth, the throat and onto the jaw's flanks
	# from below; its rests under open sky are the wing sweep's, and those on the ground under the
	# belly are #1560's.
	var red := _red_rests(_level, _world, _ground_throwers, true)
	assert_array(red).override_failure_message("\n".join(red.slice(0, 40))).is_empty()


func test_without_the_caps_a_corridor_holds_an_item_out_of_reach() -> void:
	# The sweep is not blind where it was red (#1551): the ship with its hull caps off, thrown
	# from the corridor's floor by the gap behind its wall, holds an item out of reach.
	var root := (load(EstateDoc.MAP) as PackedScene).instantiate()
	var caps := 0
	for found: Node in root.find_children(CAP_PREFIX + "*", "CollisionShape3D", true, false):
		(found as CollisionShape3D).disabled = true
		caps += 1
	var level := LevelWorld.from_scene(root, EstateDoc.MAP)
	root.free()
	assert_int(caps).is_greater(0)
	var spots: Array[Vector3] = []
	for feet: Vector3 in _throwers:
		if feet.distance_to(CORRIDOR) <= CORRIDOR_SPOTS_M:
			spots.append(feet)
	assert_array(spots).is_not_empty()
	assert_array(_red_rests(level, _world_of_level(level), spots)).is_not_empty()


## The estate's host world over `level`.
func _world_of_level(level: LevelWorld) -> HostWorldQuery:
	var world := HostWorldQuery.new(_rules.capsule_radius_m)
	world.add_level(level)
	world.use_level(EstateDoc.MAP)
	return world


## The rests out of reach inside the outline, a line each (one per RED_CELL_M cell), of the fan
## of throws from `throwers`; with `under_roof`, only those in the hull: under its roof
## (_under_roof) and THROWER_LOWEST_M or more up.
func _red_rests(
	level: LevelWorld, world: HostWorldQuery, throwers: Array[Vector3], under_roof := false
) -> Array[String]:
	var red: Array[String] = []
	var tops := EstateThrows.tops(world)
	var outline := _ship.grow(EstateThrows.EAVE_M)
	var down := Vector3(0.0, -_throw.gravity_mps2, 0.0)
	var ticks := maxi(1, Ticks.from_seconds(_throw.longest_flight_s))
	var checked: Dictionary[Vector3i, bool] = {}
	var reported: Dictionary[Vector3i, bool] = {}
	for feet: Vector3 in throwers:
		var eye := _eye(world, feet, not _stands_up(world, feet))
		var fallback := world.floor_below(Items.lifted(feet))
		for yaw_deg in range(0, 360, HouseThrows.YAW_STEP_DEG):
			var yaw := deg_to_rad(yaw_deg)
			if not _towards(outline, feet, yaw):
				continue
			for pitch_deg in range(0, HouseThrows.PITCH_TOP_DEG + 1, HouseThrows.PITCH_STEP_DEG):
				var pitch := deg_to_rad(pitch_deg)
				var facing := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				var rest := HouseThrows.rest_of(
					world, eye, facing * _throw.speed_mps, down, _throw.radius_m, ticks, fallback
				)
				if not outline.has_point(Vector2(rest.x, rest.z)):
					continue
				if EstateThrows.on_a_top(tops, rest) != "":
					continue
				if under_roof and (rest.y < THROWER_LOWEST_M or not _under_roof(world, rest)):
					continue
				var key := Vector3i((rest / REST_GRID_M).floor())
				if checked.has(key):
					continue
				checked[key] = _picked(level, world, rest)
				var cell := Vector3i((rest / RED_CELL_M).floor())
				if not checked[key] and not reported.has(cell):
					reported[cell] = true
					red.append(
						"%s, thrown from %s at yaw %d, pitch %d" % [rest, feet, yaw_deg, pitch_deg]
					)
	return red


## Whether a throw from `feet` at `yaw` can rest inside `outline`: its plan path (a straight line,
## the rest on it) meets the outline within PLAN_M, sampled every PLAN_STEP_M.
func _towards(outline: Rect2, feet: Vector3, yaw: float) -> bool:
	var at := Vector2(feet.x, feet.z)
	var way := Vector2(sin(yaw), cos(yaw)) * PLAN_STEP_M
	for step in range(ceili(PLAN_M / PLAN_STEP_M) + 1):
		if outline.has_point(at + way * step):
			return true
	return false


## Whether `rest` lies under the hull's roof: the ray up from it, one way or the other, meets the
## ship (the inverse of the wing sweep's _in_scope).
func _under_roof(world: HostWorldQuery, rest: Vector3) -> bool:
	var from := Items.lifted(rest)
	var up := from + Vector3.UP * SKY_M
	return not (world.line_of_sight(from, up) and world.line_of_sight(up, from))


## Whether a walked floor picks up an item resting at `rest` under the PickUp rule: within the
## reach of the feet lifted by up to the jump (the headroom allowing), and in sight from the
## standing or the crouched eye.
func _picked(level: LevelWorld, world: HostWorldQuery, rest: Vector3) -> bool:
	var cell := Vector2i(floori(rest.x / BUCKET_M), floori(rest.z / BUCKET_M))
	var span := ceili(_reach_m / BUCKET_M) + 1
	var target := Items.lifted(rest)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for feet: Vector3 in _feet.get(cell + Vector2i(dx, dz), []):
				if Vector2(feet.x - rest.x, feet.z - rest.z).length() > _reach_m:
					continue
				var lift := clampf(rest.y - feet.y, 0.0, _jump_room(level, feet))
				if (feet + Vector3.UP * lift).distance_to(rest) > _reach_m:
					continue
				for crouched: bool in [false, true]:
					if world.line_of_sight(_eye(world, feet, crouched), target):
						return true
	return false


## Whether a player stands up at `feet`: the standing capsule's height is clear over them (both
## ways: a ray misses a shape it starts in). Under a lower ceiling (the nose's belly over the
## ground) a player only crouches, so it throws and looks from the crouched eye.
func _stands_up(world: HostWorldQuery, feet: Vector3) -> bool:
	var from := Items.lifted(feet)
	var head := from + Vector3.UP * _rules.capsule_height_m
	return world.line_of_sight(from, head) and world.line_of_sight(head, from)


## Items.eye_of at `feet`: the floor stood on raised by the standing or the crouched eye.
func _eye(world: HostWorldQuery, feet: Vector3, crouched: bool) -> Vector3:
	var ground := world.stand_floor_below(Items.lifted(feet))
	var y := ground.y if ground != WorldQuery.NO_FLOOR else feet.y
	return Vector3(feet.x, y + _rules.eye_height_of(crouched), feet.z)


## How high a player standing at `feet` rises: the jump, less what a ceiling over its head takes.
func _jump_room(level: LevelWorld, feet: Vector3) -> float:
	var head := Items.lifted(feet) + Vector3.UP * _rules.capsule_height_m
	var query := PhysicsRayQueryParameters3D.create(
		Items.lifted(feet), head + Vector3.UP * _rules.jump_height_m, LevelWorld.WORLD_LAYER
	)
	var hit := level.space_state().intersect_ray(query)
	if hit.is_empty():
		return _rules.jump_height_m
	return clampf((hit["position"] as Vector3).y - head.y, 0.0, _rules.jump_height_m)


## The flood fill of the floors walked in and by the ship (the suite's comment), into _walked and
## _feet.
func _walk() -> void:
	var box := _ship.grow(WALK_BOX_M)
	var queue: Array[Vector3] = []
	for start: Vector2 in [
		Vector2(box.get_center().x, box.position.y),
		Vector2(box.get_center().x, box.end.y),
		Vector2(box.position.x, box.get_center().y),
		Vector2(box.end.x, box.get_center().y),
	]:
		var at := _world.stand_floor_below(
			Vector3(snappedf(start.x, WALK_STEP_M), WALK_BAND_M, snappedf(start.y, WALK_STEP_M))
		)
		if _visit(at):
			queue.append(at)
	var ways: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var head := 0
	while head < queue.size():
		var from := queue[head]
		head += 1
		var climb := maxf(_rules.step_height_m, _jump_room(_level, from))
		for way: Vector2 in ways:
			var to_xz := Vector2(from.x, from.z) + way * WALK_STEP_M
			if not box.has_point(to_xz):
				continue
			var to := _world.stand_floor_below(Vector3(to_xz.x, from.y + climb, to_xz.y))
			if _visit(to):
				queue.append(to)


## Adds `at` to the walk if it is a floor not walked yet that the crouched capsule fits on.
func _visit(at: Vector3) -> bool:
	if at == WorldQuery.NO_FLOOR:
		return false
	var cell := Vector3i(
		roundi(at.x / WALK_STEP_M), roundi(at.y / WALK_BAND_M), roundi(at.z / WALK_STEP_M)
	)
	if _walked.has(cell) or not _crouched_fits(at):
		return false
	_walked[cell] = at
	var bucket := Vector2i(floori(at.x / BUCKET_M), floori(at.z / BUCKET_M))
	if not _feet.has(bucket):
		_feet[bucket] = []
	_feet[bucket].append(at)
	return true


## Whether the crouched capsule fits on `at` (house_body_reach_test.gd's _crouched_fits).
func _crouched_fits(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = _rules.capsule_radius_m - Items.SURFACE_CLEARANCE_M
	capsule.height = _rules.crouch_height_m
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := at + Vector3.UP * (_rules.crouch_height_m / 2.0 + Items.SURFACE_CLEARANCE_M)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return _level.space_state().intersect_shape(query, 1).is_empty()


## The throwers of `floors`: the one nearest the middle of each `size_m` cell in each
## THROWER_BAND_M band.
func _thinned(floors: Array[Vector3], size_m: float) -> Array[Vector3]:
	var by_cell: Dictionary[Vector3i, Vector3] = {}
	for at: Vector3 in floors:
		var cell := Vector3i(
			floori(at.x / size_m), floori(at.y / THROWER_BAND_M), floori(at.z / size_m)
		)
		var middle := (Vector2(cell.x, cell.z) + Vector2(0.5, 0.5)) * size_m
		if (
			not by_cell.has(cell)
			or (
				Vector2(at.x, at.z).distance_to(middle)
				< Vector2(by_cell[cell].x, by_cell[cell].z).distance_to(middle)
			)
		):
			by_cell[cell] = at
	var found: Array[Vector3] = []
	found.assign(by_cell.values())
	return found


## Whether a walked floor lies within half a metre of `floor_point`.
func _walked_near(floor_point: Vector3) -> bool:
	var bucket := Vector2i(floori(floor_point.x / BUCKET_M), floori(floor_point.z / BUCKET_M))
	for feet: Vector3 in _feet.get(bucket, []):
		if feet.distance_to(floor_point) <= 0.5:
			return true
	return false
