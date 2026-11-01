extends GdUnitTestSuite
## No throw at the base mode's numbers leaves an item on the art ship's skin under open sky out of
## every player's reach (#1543, follow-up of #1534; the throwing ADR, TD5 (a)): the hull's low wing
## edges, 2 to 3 m over the ground, are under a throw's arc from the ground beside them, and no
## player stands on them (no way up). The ship's top is the roof sweep's
## (estate_roof_throw_test.gd); the rests inside the hull are #1551's: it widens _in_scope and
## _skin (the topmost floor of a column, off the ship's top) to the floors under the roof.
## From every spot of the roof sweep round and under the ship (EstateThrows.spots: the ground on two
## rings round its outline, the deck and the ground under it), the roof sweep's fan of throws is
## flown as FlightTicks flies it (HouseThrows.rest_of), with the Throw rule's own ThrowItem numbers
## and the mode's PlayerRules; only the throws whose plan path passes over the skin within a
## throw's range are flown (_skin, _yaws: a flight rests on its plan path, and on the skin only
## within that range). Each rest on the skin (over the highest spot, off its top) must be within
## the PickUp rule's InReach of a player's feet: on a floor a player stands on (_stand_spots). A
## later change of the numbers or of the ship that leaves an item on a wing out of reach turns this
## red; so does the ship without its wing edge fences (the Hull's EdgeFence shapes, #1543).

const EstateThrows := preload("res://tests/integration/levels/estate_throws.gd")
const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
const SHIP := "Ship"
## The ship piece's wing edge fences (Hull's shapes named so), turned off for the unfenced check.
const FENCE_PREFIX := "EdgeFence"
## The feet a player stands on round and under the ship: every floor no higher than the roof
## sweep's highest spot by the ship (the deck, 1.2 m; the wing edges are 2 m and more), on columns
## this far apart over the ship's outline grown by the reach and a capsule.
const STAND_STEP_M := 0.25
## A floor whose height under a player's footprint varies more than this is no place to stand
## (estate_tops_reach_test.gd's rule): the curved skin is none.
const STAND_FLAT_M := 0.3
## The buckets of the feet, for the nearest feet to a rest.
const BUCKET_M := 1.0
## The plan grid the skin is read on (_skin).
const SKIN_STEP_M := 0.25
## A ray up this far from a rest that meets nothing: the rest is under open sky.
const SKY_M := 30.0
## The west wing edge the unfenced ship holds an item out of reach on (#1543: 2.04 to 2.21 m from
## the nearest feet), and how far from it the spots it is thrown from lie and the rest falls.
const WING_EDGE := Vector3(107.6, 2.45, 68.9)
const WING_EDGE_SPOTS_M := 3.0
const WING_EDGE_NEAR_M := 0.5
## The probe ledge's height (a wing edge's, 2.4 m) and how far from it the spots it is thrown
## onto from lie.
const LEDGE_M := 2.4
const LEDGE_SPOTS_M := 3.0

var _world: HostWorldQuery
var _rules: PlayerRules
var _throw: ThrowItem
var _reach_m := 0.0
var _ship := Rect2()
var _ship_top := 0.0
## Feet by bucket (Vector2i of x, z floored by BUCKET_M).
var _feet: Dictionary[Vector2i, Array] = {}
## The roof sweep's spots round and under the ship, thrown from.
var _spots: Array = []


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
	_world = HostWorldQuery.new(_rules.capsule_radius_m)
	_world.add_level(LevelWorld.build(EstateDoc.MAP))
	_world.use_level(EstateDoc.MAP)
	var tops := EstateThrows.tops(_world)
	if tops.has(SHIP):
		_ship = tops[SHIP]["rect"]
		_ship_top = tops[SHIP]["y"]
	_feet = _stand_spots()
	# The throwers' own feet: the roof sweep's spots, a passage's sloped floor under the ship's
	# west side among them, which the flat footprint rule misses.
	_spots = EstateThrows.spots(_world, _rules.eye_height_m).get(SHIP, [])
	for feet: Vector3 in _spots:
		var cell := Vector2i(floori(feet.x / BUCKET_M), floori(feet.z / BUCKET_M))
		if not _feet.has(cell):
			_feet[cell] = []
		_feet[cell].append(feet)


func after() -> void:
	_world = null
	_rules = null
	_throw = null
	_feet.clear()


func test_the_numbers_the_ship_and_its_feet_are_read() -> void:
	assert_array(Array(_world.errors)).is_empty()
	assert_object(_throw).is_not_null()
	assert_float(_reach_m).is_greater(0.0)
	assert_bool(_ship.has_area()).is_true()
	assert_bool(_feet.is_empty()).is_false()
	assert_bool(_spots.is_empty()).is_false()


func test_no_throw_leaves_an_item_on_the_ship_s_skin_out_of_reach() -> void:
	var red := _red_rests(_world, _spots)
	assert_array(red).override_failure_message("\n".join(red.slice(0, 40))).is_empty()


func test_without_the_edge_fences_the_west_wing_edge_holds_an_item_out_of_reach() -> void:
	# The sweep is not blind where it was red (#1543): the ship with its fences off, thrown from
	# the spots by the west wing edge, rests an item on it out of reach.
	var root := (load(EstateDoc.MAP) as PackedScene).instantiate()
	var fences := 0
	for found: Node in root.find_children(FENCE_PREFIX + "*", "CollisionShape3D", true, false):
		(found as CollisionShape3D).disabled = true
		fences += 1
	var unfenced := _world_of(root)
	root.free()
	assert_int(fences).is_greater(0)
	var spots: Array = []
	for feet: Vector3 in _spots:
		if Vector2(feet.x - WING_EDGE.x, feet.z - WING_EDGE.z).length() <= WING_EDGE_SPOTS_M:
			spots.append(feet)
	var on_edge := 0
	for rest: Vector3 in _out_of_reach(unfenced, spots):
		if rest.distance_to(WING_EDGE) <= WING_EDGE_NEAR_M:
			on_edge += 1
	assert_int(on_edge).is_greater(0)


func test_a_rest_on_the_ship_s_top_is_out_of_reach_and_one_beside_the_ship_is_in_it() -> void:
	# The check is not blind: the top's middle is far over every floor, the ground by the ramp's
	# foot is a floor.
	var top := Vector3(_ship.get_center().x, _ship_top, _ship.get_center().y)
	assert_float(_nearest_feet(top)).is_greater(_reach_m)
	var beside := _world.floor_below(Vector3(_ship.get_center().x, 5.0, _ship.position.y - 2.0))
	assert_float(_nearest_feet(beside)).is_less_equal(_reach_m)


func test_a_ledge_as_high_as_a_wing_edge_in_the_ship_s_outline_turns_the_sweep_red() -> void:
	# A 1 m block LEDGE_M high in the outline's north-west corner, off the hull: thrown from the
	# spots by it at the rule's own speed, an item rests on its top out of reach, or the sweep
	# could never fail.
	var base := Vector3(_ship.position.x + 0.5, 0.0, _ship.position.y + 0.5)
	base.y = _world.floor_below(base + Vector3.UP * 5.0).y
	var root := (load(EstateDoc.MAP) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, LEDGE_M, 1.0)
	shape.shape = box
	body.add_child(shape)
	body.position = base + Vector3.UP * (LEDGE_M / 2.0)
	root.add_child(body)
	var ledge_world := _world_of(root)
	root.free()
	var spots: Array = []
	for feet: Vector3 in _spots:
		if Vector2(feet.x - base.x, feet.z - base.z).length() <= LEDGE_SPOTS_M:
			spots.append(feet)
	assert_array(_red_rests(ledge_world, spots)).is_not_empty()


## The estate's host world built from `root`, an instance of the map.
func _world_of(root: Node) -> HostWorldQuery:
	var level := LevelWorld.from_scene(root, EstateDoc.MAP)
	var world := HostWorldQuery.new(_rules.capsule_radius_m)
	world.add_level(level)
	world.use_level(EstateDoc.MAP)
	return world


## Each rest out of reach, as a line, of the fan of throws from each of `spots`.
func _red_rests(world: HostWorldQuery, spots: Array) -> Array[String]:
	var red: Array[String] = []
	var tops := EstateThrows.tops(world)
	var skin := _skin(world, tops)
	for feet: Vector3 in spots:
		for rest in _rests(world, feet, tops, skin):
			var nearest := _nearest_feet(rest)
			if nearest > _reach_m:
				red.append(
					"%s, thrown from %s: the nearest feet %.2f m off" % [rest, feet, nearest]
				)
	return red


## The rests out of reach of the fan of throws from each of `spots`.
func _out_of_reach(world: HostWorldQuery, spots: Array) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var tops := EstateThrows.tops(world)
	var skin := _skin(world, tops)
	for feet: Vector3 in spots:
		for rest in _rests(world, feet, tops, skin):
			if _nearest_feet(rest) > _reach_m:
				found.append(rest)
	return found


## The ship's skin in `world`: on a SKIN_STEP_M grid over the ship's outline grown by the eave,
## the topmost floor over the highest spot (no player stands on it) and off the ship's top.
func _skin(world: HostWorldQuery, tops: Dictionary[String, Dictionary]) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var area := _ship.grow(EstateThrows.EAVE_M)
	var above := Vector3.UP * (_ship_top + 1.0)
	var lowest: float = EstateThrows.HIGHEST_SPOT_M[SHIP]
	var x := area.position.x
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			var top := world.floor_below(Vector3(x, 0.0, z) + above)
			if (
				top != WorldQuery.NO_FLOOR
				and top.y > lowest
				and EstateThrows.on_a_top(tops, top) == ""
			):
				found.append(top)
			z += SKIN_STEP_M
		x += SKIN_STEP_M
	return found


## The rests on the skin, in scope (_in_scope), of the roof sweep's fan of throws from `feet`: only
## the yaws whose plan path passes over a cell of `skin` within reach of a throw (_yaws).
func _rests(
	world: HostWorldQuery, feet: Vector3, tops: Dictionary[String, Dictionary], skin: Array[Vector3]
) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var ground := world.stand_floor_below(Items.lifted(feet))
	var eye := Vector3(feet.x, ground.y if ground != WorldQuery.NO_FLOOR else feet.y, feet.z)
	eye += Vector3.UP * _rules.eye_height_m
	var down := Vector3(0.0, -_throw.gravity_mps2, 0.0)
	var fallback := world.floor_below(Items.lifted(feet))
	var ticks := maxi(1, Ticks.from_seconds(_throw.longest_flight_s))
	var lowest: float = EstateThrows.HIGHEST_SPOT_M[SHIP]
	var outline := _ship.grow(EstateThrows.EAVE_M)
	for yaw_deg in _yaws(eye, skin):
		var yaw := deg_to_rad(yaw_deg)
		for pitch_deg in range(0, HouseThrows.PITCH_TOP_DEG + 1, HouseThrows.PITCH_STEP_DEG):
			var pitch := deg_to_rad(pitch_deg)
			var facing := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			var rest := HouseThrows.rest_of(
				world, eye, facing * _throw.speed_mps, down, _throw.radius_m, ticks, fallback
			)
			if rest.y <= lowest or not outline.has_point(Vector2(rest.x, rest.z)):
				continue
			if EstateThrows.on_a_top(tops, rest) != "":
				continue
			if _in_scope(world, rest):
				found.append(rest)
	return found


## The fan's yaws (HouseThrows.YAW_STEP_DEG apart, degrees) whose plan path from `eye` passes
## within an item's radius and half a skin cell's diagonal of a cell of `skin` that a throw from
## `eye` can rest on: no higher than its arc's top, no farther than its longest reach down to the
## highest spot (v * sqrt(v^2 + 2 g h) / g, h the eye over that spot). A flight rests on its plan
## path, under its stop, so no other yaw rests on the skin.
func _yaws(eye: Vector3, skin: Array[Vector3]) -> Array[int]:
	var v := _throw.speed_mps
	var g := _throw.gravity_mps2
	var lowest: float = EstateThrows.HIGHEST_SPOT_M[SHIP]
	var drop := eye.y - lowest
	var found: Array[int] = []
	if v * v + 2.0 * g * drop < 0.0:
		return found
	var farthest := v * sqrt(v * v + 2.0 * g * drop) / g
	var apex := eye.y + v * v / (2.0 * g)
	var near := _throw.radius_m + SKIN_STEP_M * sqrt(0.5)
	var step := HouseThrows.YAW_STEP_DEG
	var meets: Dictionary[int, bool] = {}
	for cell: Vector3 in skin:
		if cell.y > apex:
			continue
		var plan := Vector2(cell.x - eye.x, cell.z - eye.z)
		var distance := plan.length()
		if distance > farthest + near:
			continue
		if distance <= near:
			for yaw_deg in range(0, 360, step):
				meets[yaw_deg] = true
			continue
		# A yaw measured as the fan's: sin(yaw) along x, cos(yaw) along z.
		var toward := rad_to_deg(atan2(plan.x, plan.y))
		var spread := rad_to_deg(asin(near / distance))
		for yaw_deg in range(
			ceili((toward - spread) / step) * step,
			floori((toward + spread) / step) * step + 1,
			step
		):
			meets[posmod(yaw_deg, 360)] = true
	for yaw_deg in range(0, 360, step):
		if meets.has(yaw_deg):
			found.append(yaw_deg)
	return found


## Whether `rest` is this sweep's: under open sky (the ray up from it, both ways, meets nothing).
## #1551 sweeps the hull's inside: it widens this and _skin, whose cells (the topmost floor of a
## column, off the ship's top) decide which yaws are flown.
func _in_scope(world: HostWorldQuery, rest: Vector3) -> bool:
	var from := Items.lifted(rest)
	var up := from + Vector3.UP * SKY_M
	return world.line_of_sight(from, up) and world.line_of_sight(up, from)


## The distance from `rest` to the nearest feet of _feet.
func _nearest_feet(rest: Vector3) -> float:
	var nearest := INF
	var cell := Vector2i(floori(rest.x / BUCKET_M), floori(rest.z / BUCKET_M))
	var span := ceili(_reach_m / BUCKET_M) + 1
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for feet: Vector3 in _feet.get(cell + Vector2i(dx, dz), []):
				nearest = minf(nearest, feet.distance_to(rest))
	return nearest


## Every floor a player stands on round and under the ship, by bucket: on columns STAND_STEP_M
## apart over the ship's outline grown by the reach and a capsule, each floor no higher than the
## roof sweep's highest spot by the ship, flat under the capsule's footprint (STAND_FLAT_M) and
## with a crouching player's height clear above it.
func _stand_spots() -> Dictionary[Vector2i, Array]:
	var found: Dictionary[Vector2i, Array] = {}
	var area := _ship.grow(_reach_m + _rules.capsule_radius_m + EstateThrows.EAVE_M)
	var top: float = EstateThrows.HIGHEST_SPOT_M[SHIP] + Items.SURFACE_CLEARANCE_M
	var x := area.position.x
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			var from := Vector3(x, top, z)
			while true:
				var floor_point := _world.floor_below(from)
				if floor_point == WorldQuery.NO_FLOOR:
					break
				if _stands(floor_point):
					var cell := Vector2i(floori(x / BUCKET_M), floori(z / BUCKET_M))
					if not found.has(cell):
						found[cell] = []
					found[cell].append(floor_point)
				from = floor_point + Vector3.DOWN * EstateThrows.COLUMN_STEP_M
			z += STAND_STEP_M
		x += STAND_STEP_M
	return found


## Whether a player stands on `floor_point`: the floor under each edge of the capsule's footprint
## within STAND_FLAT_M of it, and a crouching player's height clear above it (both ways: a ray
## misses a shape it starts in).
func _stands(floor_point: Vector3) -> bool:
	var r := _rules.capsule_radius_m
	var above := floor_point + Vector3.UP * 0.05
	for offset: Vector3 in [
		Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)
	]:
		var edge := _world.floor_below(above + offset)
		if edge == WorldQuery.NO_FLOOR or absf(edge.y - floor_point.y) > STAND_FLAT_M:
			return false
	var feet := Items.lifted(floor_point)
	var head := feet + Vector3.UP * _rules.crouch_height_m
	return _world.line_of_sight(feet, head) and _world.line_of_sight(head, feet)
