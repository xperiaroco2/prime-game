extends GdUnitTestSuite
## The forest estate's box greybox (#1158) can be walked (docs/design/estate-map.md §3-§5d):
## both loops and the spokes of §4 through the buildings' doors, the house's links between its
## four levels (§5, §5c) with the library's bookcase stair and the chimney's drop from the roof,
## the ship's ramp into its hall and wings (§5a), and the creek crossed only at its crossings (the
## east road included). Each walk: from point to point every rise is a step the player can take
## (rules.step_height_m, 0.3 m) and the player's capsule fits, in the host's collision world of
## the level (LevelWorld), as house_stairs_test walks the House; and from each round spawn to the
## bonfire (#1374).

const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const RADIUS := 0.4
const HEIGHT := 1.8
const STEP := 0.3
const JUMP := 1.0
const SPACING := 0.1
const BONFIRE := Vector2(65.3, 41)
## §2: the east road's far edge (the road runs x 135..141).
const ROAD_EAST_EDGE := 141.0
## The roof terrace's floor, the chimney shaft's centre and a point on its lip (§5c: the house at
## (68.4, 11), the stack on the roof's west side).
const ROOF := 6.4
const CHIMNEY := Vector2(63.3, 8)
const CHIMNEY_LIP := Vector2(64.1, 8)
## Walks in map metres (x, level height, z) through their corners; they end at the last corner's
## height. A bonfire end starts 3.6 m out from its centre, past the fire pit.
const WALKS := {
	"upper loop":
	[
		Vector3.ZERO,
		Vector3(53, 0, 29),
		Vector3(43, 0, 29),
		Vector3(30, 0, 16.5),
		Vector3(30, 0, 13),
		Vector3(33, 0, 12),
		Vector3(36, 0, 12),
		Vector3(61, 0, 11),
		Vector3(64, 0, 11),
		Vector3(64, 0, 14.5),
		Vector3(72.8, 0, 14.5),
		Vector3(72.8, 0, 11),
		Vector3(76, 0, 11),
		Vector3(98.1, 0, 17),
		Vector3(98.1, 0, 13),
		Vector3(104, 0, 13),
		Vector3(108, 0, 11),
		Vector3(114.9, 0, 34),
		Vector3(82.8, 0, 30),
		Vector3(78, 0, 30),
		Vector3(0, 0, 0),
	],
	"house spoke":
	[
		Vector3(68.4, 0, 13.5),
		Vector3(68.4, 0, 17),
		Vector3(0, 0, 0),
	],
	"lower loop, well and trunk":
	[
		Vector3(27, 0, 72),
		Vector3(80, 0, 79.5),
		Vector3(92, 0, 79.5),
		Vector3(100, 0, 60),
		Vector3(113, 0, 59.5),
	],
	"gate spoke to the road":
	[
		Vector3(82, 0, 79.5),
		Vector3(80, 0, 79.5),
		Vector3(67.5, 0, 90),
		Vector3(67.5, 0, 94),
	],
	"driveway to the road": [Vector3(104, 0, 11), Vector3(140, 0, 11)],
	"ship, ramp to hall":
	[
		Vector3(116, 0, 57.5),
		Vector3(116, 0, 64),
		Vector3(116, 1.2, 71.6),
	],
	"ship, hall to the east lens room": [Vector3(116, 1.2, 71.6), Vector3(126.5, 1.2, 73.2)],
	"ship, hall to the west lens room": [Vector3(116, 1.2, 71.6), Vector3(105.5, 1.2, 73.2)],
	"house, stairs down to the laboratory":
	[
		Vector3(69.4, 0, 14),
		Vector3(69.4, 0, 12.5),
		Vector3(69.4, 0, 7.5),
		Vector3(69.4, 0, 6.7),
		Vector3(67.4, 0, 6.7),
		Vector3(67.4, -3.2, 16),
	],
	"house, stairs up to the library":
	[
		Vector3(67.4, 0, 14),
		Vector3(67.4, 0, 12.5),
		Vector3(67.4, 0, 7.5),
		Vector3(67.4, 0, 6.7),
		Vector3(69.4, 0, 6.7),
		Vector3(69.4, 3.2, 12),
	],
	"house, library ladder to the roof":
	[
		Vector3(73.4, 3.2, 14),
		Vector3(73.4, 3.2, 12.5),
		Vector3(73.4, 3.2, 7.5),
		Vector3(73.4, 3.2, 6.7),
		Vector3(70, 3.2, 6.7),
		Vector3(70, 6.4, 12),
	],
	"house, library by the balcony's stairs to the yard":
	[
		Vector3(68.4, 3.2, 14),
		Vector3(68.4, 3.2, 17),
		Vector3(72, 3.2, 17),
		Vector3(79, 0, 17),
	],
	"house, cellar door to the cellar, the hall and the laboratory":
	[
		Vector3(56.5, 0, 7.5),
		Vector3(63.9, 0, 7.5),
		Vector3(64.5, 0, 9.5),
		Vector3(67.4, 0, 9.5),
		Vector3(67.4, -3.2, 16),
	],
	"house, the library's bookcase stair to the cellar":
	[
		Vector3(69.4, 3.2, 7),
		Vector3(69.4, 3.2, 5.3),
		Vector3(68.6, 3.2, 5.3),
		Vector3(59.6, 0, 5.3),
		Vector3(59.1, 0, 5.3),
		Vector3(59.1, 0, 9.5),
		Vector3(62.4, -3.2, 9.5),
	],
	"house, hall to the security room and the laboratory":
	[
		Vector3(67.4, -3.2, 9.5),
		Vector3(67.4, -3.2, 7),
		Vector3(73, -3.2, 7),
		Vector3(74.4, -3.2, 10),
		Vector3(74.4, -3.2, 16),
	],
}
## Walks over the creek: from a bonfire end, or a point, over a crossing's banks to a point.
const OVER_THE_CREEK := {
	"lower loop, bonfire by the stepping stones to the well":
	["", "stepping stones", Vector2(27, 72)],
	"lower loop, ship by the drainage pipe to the bonfire":
	[Vector2(113, 59.5), "drainage pipe", ""],
	"pantry by the log bridge to the well": [Vector2(43, 29), "log bridge", Vector2(27, 69.8)],
	"gazebo by the plank footbridge to the ship":
	[Vector2(114.9, 34), "plank footbridge", Vector2(116, 58)],
}

var _level: LevelWorld


func before() -> void:
	_level = LevelWorld.build(EstateDoc.MAP)


func after() -> void:
	_level = null


func test_the_map_builds_into_the_host_s_world_without_errors() -> void:
	assert_array(Array(_level.errors)).is_empty()
	assert_int(_level.body_count()).is_greater(0)


func test_each_walk_can_be_walked() -> void:
	for walk: String in WALKS:
		var corners: Array = (WALKS[walk] as Array).duplicate()
		if corners[0] == Vector3.ZERO:
			corners[0] = _from_bonfire(corners[1] as Vector3)
		if corners[-1] == Vector3.ZERO:
			corners[-1] = _from_bonfire(corners[-2] as Vector3)
		_walk(walk, corners, (corners[-1] as Vector3).y)


func test_each_round_spawn_walks_to_the_bonfire_where_every_walk_starts() -> void:
	# The base mode's round spawns (#1374, the Markers piece): a player spawned at any of them
	# reaches the ring round the bonfire, so every lot by the walks above.
	var map: Node3D = auto_free((load(EstateDoc.MAP) as PackedScene).instantiate())
	var spawns := 0
	for node in map.find_children("*", "Marker3D", true, false):
		if not node.is_in_group(&"spawn_round_player"):
			continue
		var at := (node.get_parent() as Node3D).transform * (node as Node3D).position
		_walk("from %s" % node.name, [at, _from_bonfire(at)], 0.0)
		spawns += 1
	assert_int(spawns).is_greater(0)


func test_each_crossing_carries_a_walk_over_the_creek() -> void:
	for walk: String in OVER_THE_CREEK:
		var plan: Array = OVER_THE_CREEK[walk]
		var crossing := EstateDoc.crossings()[plan[1] as String] as Vector2
		var n := EstateDoc.creek_normal(crossing)
		var north := crossing - n * 4.0
		var south := crossing + n * 4.0
		var first: Vector2 = plan[0] if plan[0] is Vector2 else BONFIRE
		var last: Vector2 = plan[2] if plan[2] is Vector2 else BONFIRE
		# Over the banks from the start's side.
		var banks: Array[Vector2] = [north, south]
		if first.distance_to(south) < first.distance_to(north):
			banks.reverse()
		var corners: Array = []
		for point: Vector2 in [first, banks[0], banks[1], last]:
			corners.append(Vector3(point.x, 0, point.y))
		if plan[0] is not Vector2:
			corners[0] = _from_bonfire(corners[1] as Vector3)
		if plan[2] is not Vector2:
			corners[-1] = _from_bonfire(corners[-2] as Vector3)
		_walk(walk, corners, 0.0)


func test_the_chimney_drops_from_the_roof_to_the_fireplace() -> void:
	# §5, §5c: the roof terrace's second way down, at once and down only: over a lip a jump
	# clears, straight down the shaft to the living room's floor, out by the fireplace's mouth.
	var lip := _top_at(CHIMNEY_LIP.x, CHIMNEY_LIP.y)
	assert_float(lip).is_greater(ROOF)
	assert_float(lip).is_less_equal(ROOF + JUMP + STEP)
	(
		assert_float(_top_at(CHIMNEY.x, CHIMNEY.y))
		. override_failure_message("something stops the drop down the chimney")
		. is_equal_approx(0.0, 0.01)
	)
	var out := [
		Vector3(CHIMNEY.x, 0, CHIMNEY.y),
		Vector3(65.5, 0, CHIMNEY.y),
		Vector3(65.5, 0, 14),
	]
	_walk("chimney, the fireplace to the living room", out, 0.0)


func test_the_creek_cannot_be_crossed_but_at_its_crossings() -> void:
	# §3: about 3 m wide, not crossable except at the crossings: higher than a jump and a step from
	# the highest floor beside it, a crossing's top. A crossing's gap is 3 m: 1.5 m each side.
	var line := EstateDoc.creek()
	var crossings := EstateDoc.crossings().values()
	assert_int(line.size()).is_greater(1)
	var reach := JUMP + STEP
	for c: Vector2 in crossings:
		reach = maxf(reach, _top_at(c.x, c.y) + JUMP + STEP)
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var length := a.distance_to(b)
		var s := 0.5
		while s < length - 0.5:
			var p := a.lerp(b, s / length)
			s += 1.0
			var near_crossing := false
			for c: Vector2 in crossings:
				if (
					Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(p) < 2.0
					and EstateDoc.distance_to_segment(c, a, b) < 2.0
				):
					near_crossing = true
			if not near_crossing:
				_assert_creek_blocks(p, reach)
	# §2: the creek's end at the fence meets the east road (x 135..141); the road is no crossing.
	var end := line[line.size() - 1]
	var x := end.x + 0.5
	while x < ROAD_EAST_EDGE:
		_assert_creek_blocks(Vector2(x, end.y), reach)
		x += 1.0


func _assert_creek_blocks(p: Vector2, reach: float) -> void:
	var top := _top_at(p.x, p.y)
	(
		assert_float(top)
		. override_failure_message(
			"the creek at (%.1f, %.1f) is %.2f m high, a jump crosses it" % [p.x, p.y, top]
		)
		. is_greater(reach)
	)


## The bonfire's end of a walk: 3.6 m out from its centre toward `toward`, past the fire pit.
func _from_bonfire(toward: Vector3) -> Vector3:
	var out := (Vector2(toward.x, toward.z) - BONFIRE).normalized() * 3.6 + BONFIRE
	return Vector3(out.x, 0, out.y)


## Walks `corners`: every rise a step, the capsule fitting all the way, ending at `end`.
func _walk(walk: String, corners: Array, end: float) -> void:
	var floor_y := (corners[0] as Vector3).y
	var start := true
	for at in _points(corners):
		var found := _rest_height(at.x, at.z, floor_y)
		(
			assert_bool(is_nan(found))
			. override_failure_message("%s: no floor under (%.2f, %.2f)" % [walk, at.x, at.z])
			. is_false()
		)
		if is_nan(found):
			return
		if not start:
			(
				assert_float(found - floor_y)
				. override_failure_message(
					"%s: a %.2f m rise at (%.2f, %.2f)" % [walk, found - floor_y, at.x, at.z]
				)
				. is_less_equal(STEP)
			)
		floor_y = found
		start = false
		var fits := _fits(Vector3(at.x, floor_y, at.z))
		(
			assert_bool(fits)
			. override_failure_message(
				"%s: the player does not fit at (%.2f, %.2f, %.2f)" % [walk, at.x, floor_y, at.z]
			)
			. is_true()
		)
		if not fits:
			return
	(
		assert_float(floor_y)
		. override_failure_message("%s ends at %.2f, not at %.2f" % [walk, floor_y, end])
		. is_equal_approx(end, 0.01)
	)


## The walk's points every SPACING metres along its corners.
func _points(corners: Array) -> Array[Vector3]:
	var out: Array[Vector3] = [corners[0] as Vector3]
	for i in range(1, corners.size()):
		var a := corners[i - 1] as Vector3
		var b := corners[i] as Vector3
		var n := ceili(Vector2(b.x - a.x, b.z - a.z).length() / SPACING)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


## How high the player's capsule rests at (x, z): on the highest floor under its circle; NAN when
## there is no floor under it at all.
func _rest_height(x: float, z: float, last: float) -> float:
	var top := _floor_under(x, z, last)
	for ring: float in [RADIUS / 2, RADIUS * 0.98]:
		for k in 8:
			var angle := TAU * k / 8
			var under := _floor_under(x + cos(angle) * ring, z + sin(angle) * ring, last)
			if not is_nan(under) and (is_nan(top) or under > top):
				top = under
	return top


## The top of the floor under (x, z), searched from a step above the last floor down to 1 m
## below it; NAN when there is none.
func _floor_under(x: float, z: float, last: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(x, last + STEP + 0.05, z), Vector3(x, last - 1.0, z), LevelWorld.WORLD_LAYER
	)
	var hit := _level.space_state().intersect_ray(ray)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


## The top of whatever stands at (x, z), from 10 m down to the ground.
func _top_at(x: float, z: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(x, 10, z), Vector3(x, -0.5, z), LevelWorld.WORLD_LAYER
	)
	var hit := _level.space_state().intersect_ray(ray)
	return -1.0 if hit.is_empty() else (hit["position"] as Vector3).y


## Whether the player's capsule, resting with its feet at `feet`, touches nothing.
func _fits(feet: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, HEIGHT / 2 + 0.02, 0))
	return _level.space_state().intersect_shape(query, 1).is_empty()
