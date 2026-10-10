extends RefCounted
## Throws against House's host collision world, for house_roof_throw_test.gd (#646; the throwing
## ADR, TD5): from every standable spot near the roof that is not on it, a fan of throws in every
## direction, each flown as FlightTicks flies it (ItemFlight.point's arc, WorldQuery.sweep with the
## item's radius, the first contact ends it, the longest flight stops it, then floor_below of the
## stop lifted, or the fallback below the thrower's feet), and where each one rests.
##
## No player stops a flight here: a living player only ends one earlier, and lower.
##
## The spots (feet positions, each snapped to the floor below it):
## - `balcony`: the balcony (30..40, 21..24 at 3.2 m), every metre, 0.5 m clear of its railing;
## - `balcony_railing`: the tops of the balcony's railings (1 m high, so at 4.2 m): a player's
##   1 m jump (PlayerRules.jump_height_m) may land a player on the 0.1 m edge (the playtest
##   checks it), and a thrower whose footprint touches it throws from 1 m higher (Items.eye_of
##   takes the highest floor under its footprint). The highest spot near the roof, so the one
##   that decides the speed (#646);
## - `external_stairs`: the stairs from the terrace up to the balcony (x 39, z 17.25..20.85);
## - `terrace`: the terrace below the balcony (22..42, 16..24 at 0 m), every 2 m;
## - `around_the_house`: the yard, the path and the garden 1.5 m outside the house's walls (house
##   x 18..42, z 24..44; the terrace is its north side), every 2 m;
## - `second_floor`: inside the second floor's rooms (3.2 m), every 2 m: walls and the roof's
##   underside stop their throws, unless a level change opens a window. A throw up the attic
##   stairs' well lands in the attic, which is not the roof.
## Not swept: the roof itself, and the attic, whose door to the roof is locked in the design
## (docs/design/house-map.md, decision 11; the greybox has no door there yet).

const MAP := "res://levels/house/house.tscn"
## The roof's floor and the attic's (house.tscn places AtticAndRoof's pieces at 6.4 m): a rest at
## or above it, less this tolerance, is on the roof, its parapet or the attic's top, unless it lies
## inside the attic (on_roof).
const ROOF_Y := 6.4
const ROOF_TOLERANCE_M := 0.05
## The attic's inside (house.tscn: x 20..40, z 26..40, its ceiling's underside at 8.6 m): a rest
## there is in a room players reach by its stairs.
const ATTIC_MIN := Vector2(20.0, 26.0)
const ATTIC_MAX := Vector2(40.0, 40.0)
const ATTIC_CEILING_Y := 8.6
## The fan from each spot: a yaw every 10 degrees, a pitch every 5 from level to 85 up (648
## throws). A throw below level reaches no higher than its eye.
const YAW_STEP_DEG := 10
const PITCH_STEP_DEG := 5
const PITCH_TOP_DEG := 85


## Every spot by area, each an Array of feet positions on a floor of `world`.
static func spots(world: HostWorldQuery) -> Dictionary[String, Array]:
	var balcony: Array[Vector3] = []
	for x in range(0, 10):
		for z: float in [21.5, 22.5, 23.5]:
			_add(balcony, world, Vector3(30.5 + x, 3.2, z))
	var railing: Array[Vector3] = []
	for x in range(0, 8):
		_add(railing, world, Vector3(30.5 + x, 4.2, 21.05))
	for k in range(0, 5):
		_add(railing, world, Vector3(30.05, 4.2, 21.5 + 0.5 * k))
	for x: float in [30.3, 31.0, 33.0, 34.0, 35.0, 36.0, 37.0, 38.0, 39.0, 39.7]:
		_add(railing, world, Vector3(x, 4.2, 23.95))
	var stairs: Array[Vector3] = []
	for k in range(0, 7):
		_add(stairs, world, Vector3(39.0, 3.2, 17.25 + 0.6 * k))
	var terrace: Array[Vector3] = []
	for x in range(23, 42, 2):
		for z: int in [17, 19, 21, 23]:
			_add(terrace, world, Vector3(x, 0.0, z))
	var around: Array[Vector3] = []
	for x in range(18, 43, 2):
		_add(around, world, Vector3(x, 0.0, 45.5))
	for z in range(24, 45, 2):
		_add(around, world, Vector3(16.5, 0.0, z))
		_add(around, world, Vector3(43.5, 0.0, z))
	var second_floor: Array[Vector3] = []
	for x in range(19, 42, 2):
		for z in range(25, 44, 2):
			_add(second_floor, world, Vector3(x, 3.2, z))
	return {
		"balcony": balcony,
		"balcony_railing": railing,
		"external_stairs": stairs,
		"terrace": terrace,
		"around_the_house": around,
		"second_floor": second_floor,
	}


## The rests on the roof of the fan of throws from `feet`, flown with these numbers.
static func roof_rests(
	world: HostWorldQuery,
	feet: Vector3,
	eye_height: float,
	speed: float,
	gravity: float,
	radius: float,
	max_ticks: int
) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var ground := world.stand_floor_below(Items.lifted(feet))
	var eye := Vector3(feet.x, ground.y if ground != WorldQuery.NO_FLOOR else feet.y, feet.z)
	eye += Vector3.UP * eye_height
	var down := Vector3(0.0, -gravity, 0.0)
	var fallback := world.floor_below(Items.lifted(feet))
	for yaw_deg in range(0, 360, YAW_STEP_DEG):
		for pitch_deg in range(0, PITCH_TOP_DEG + 1, PITCH_STEP_DEG):
			var yaw := deg_to_rad(yaw_deg)
			var pitch := deg_to_rad(pitch_deg)
			var facing := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			var velocity := facing * speed
			# The arc's top: a rest is floor_below of a point on the arc lifted, so no rest of a
			# flight whose top stays that far below the roof can be on it (saves the sweeps).
			var vertical := velocity.y
			var top := eye.y + vertical * vertical / (2.0 * gravity)
			if top + Items.SURFACE_CLEARANCE_M < ROOF_Y - ROOF_TOLERANCE_M:
				continue
			var rest := rest_of(world, eye, velocity, down, radius, max_ticks, fallback)
			if on_roof(rest):
				found.append(rest)
	return found


## Whether a rest at `at` is on the roof: at the roof's height or above, outside the attic.
static func on_roof(at: Vector3) -> bool:
	if at.y < ROOF_Y - ROOF_TOLERANCE_M:
		return false
	var in_attic := (
		at.x > ATTIC_MIN.x
		and at.x < ATTIC_MAX.x
		and at.y < ATTIC_CEILING_Y
		and at.z > ATTIC_MIN.y
		and at.z < ATTIC_MAX.y
	)
	return not in_attic


## Where a flight from `eye` rests, as FlightTicks flies it with no player in the way.
static func rest_of(
	world: HostWorldQuery,
	eye: Vector3,
	velocity: Vector3,
	down: Vector3,
	radius: float,
	max_ticks: int,
	fallback: Vector3
) -> Vector3:
	var stop := eye
	for n in range(1, max_ticks + 1):
		var from := ItemFlight.point(eye, velocity, down, n - 1)
		var to := ItemFlight.point(eye, velocity, down, n)
		stop = world.sweep(from, to, radius)
		if stop != to:
			break
	var rest := world.floor_below(Items.lifted(stop))
	return rest if rest != WorldQuery.NO_FLOOR else fallback


## `at` snapped to the floor below it (asked from 0.5 m above its height), when there is one within
## a storey's reach below.
static func _add(into: Array[Vector3], world: HostWorldQuery, at: Vector3) -> void:
	var floor_point := world.floor_below(at + Vector3.UP * 0.5)
	if floor_point != WorldQuery.NO_FLOOR and floor_point.y > at.y - 3.5:
		into.append(floor_point)
