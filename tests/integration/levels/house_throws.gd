extends RefCounted
## Throws against House's host collision world, for house_roof_throw_test.gd (#646; the throwing
## ADR, TD5): from every standable spot near the roof that is not on it, a fan of throws in every
## direction, each flown as FlightTicks flies it (ItemFlight.point's arc, WorldQuery.sweep with the
## item's radius, the first contact ends it, the longest flight stops it, then floor_below of the
## stop lifted, or the fallback below the thrower's feet), and where each one rests.
##
## No player stops a flight here: a living player only ends one earlier, and lower.
##
## The spots: columns (x, z) by area, each giving every floor in it below the roof with room for
## a player's eye above it (_add_column), so the balcony's columns give the balcony and the terrace
## under it, and a crate or a raised floor added at a column is swept from its top:
## - `balcony`: the balcony (30..40, 21..24 at 3.2 m), every metre, 0.5 m clear of its railing;
## - `balcony_railing`: the tops of the balcony's three railings (1 m high, so at 4.2 m, centred on
##   the balcony's edges z 21, x 30 and x 40; the house's wall is its fourth side): a player's
##   1 m jump (PlayerRules.jump_height_m) may land a player on the 0.1 m edge (the playtest
##   checks it), and a thrower whose footprint touches it throws from 1 m higher (Items.eye_of
##   takes the highest floor under its footprint). The highest spot near the roof, so the one
##   that decides the speed (#646);
## - `external_stairs`: the art's flight from the yard up to the balcony (x 39, z 15.5..20.9);
## - `terrace`: the terrace below the balcony (22..42, 16..24 at 0 m), every 2 m;
## - `around_the_house`: the yard, the path and the garden 1.5 m outside the house's walls (house
##   x 18..42, z 24..44; the terrace is its north side), every 2 m;
## - `second_floor`: inside the second floor's rooms (3.2 m), every 2 m: walls and the roof's
##   underside stop their throws, unless a level change opens a window. A throw up the attic
##   hatch lands in the attic, which is not the roof.
## Not swept: the roof itself (the art's pitched roof over the attic, its eaves at about 8.3 m),
## and the attic, whose way out to the roof is locked in the design (docs/design/house-map.md,
## decision 11: the dormer window).

const MAP := "res://levels/house/house.tscn"
## The attic's floor (house.tscn places the Attic at 6.4 m): a rest at or above it, less this
## tolerance, is on the roof, its eaves, gutters or chimney, unless it lies inside the attic
## (on_roof).
const ROOF_Y := 6.4
const ROOF_TOLERANCE_M := 0.05
## The attic's footprint (house.tscn: the Attic at x 18, z 24, size_m 24 x 20), less half its
## knee wall: a rest inside it that sees the attic's floor below it (or near, ATTIC_LOOK_M) is in
## the attic.
const ATTIC := Rect2(18.0, 24.0, 24.0, 20.0)
const ATTIC_WALL_HALF_M := 0.15
## How far around a rest's column on_roof looks for the attic's floor, on a ring of this many
## points inside the attic's footprint: a rest on the rail of the hatch's balustrade (art #188,
## #1080), which hides the floor straight below, sees it beside the rail; one on the roof sees no
## attic floor anywhere near (the roof is between).
const ATTIC_LOOK_M := 1.0
const ATTIC_LOOK_POINTS := 8
## The fan from each spot: a yaw every 10 degrees, a pitch every 5 from level to 85 up (648
## throws). A throw below level reaches no higher than its eye.
const YAW_STEP_DEG := 10
const PITCH_STEP_DEG := 5
const PITCH_TOP_DEG := 85
## Each column of spots is read from this far under the roof (below its eave and the second
## floor's ceiling), then from this far under each floor it finds.
const COLUMN_TOP_BELOW_ROOF_M := 0.3
const COLUMN_STEP_M := 0.3


## Every spot by area, each an Array of feet positions on a floor of `world` with `headroom` clear
## above it. Each area is a set of columns (x, z); every floor in a column below the roof is a spot
## (_add_column), so a raised floor, a crate or a railing at a sampled column is thrown from at
## its own height, and a level change that adds one there is swept (#646 review).
static func spots(world: HostWorldQuery, headroom: float) -> Dictionary[String, Array]:
	var balcony: Array[Vector3] = []
	for x in range(0, 10):
		for z: float in [21.5, 22.5, 23.5]:
			_add_column(balcony, world, Vector2(30.5 + x, z), headroom)
	var railing: Array[Vector3] = []
	for x in range(0, 8):
		_add_column(railing, world, Vector2(30.5 + x, 21.0), headroom)
	for k in range(0, 5):
		_add_column(railing, world, Vector2(30.0, 21.5 + 0.5 * k), headroom)
		_add_column(railing, world, Vector2(40.0, 21.5 + 0.5 * k), headroom)
	var stairs: Array[Vector3] = []
	for k in range(0, 10):
		_add_column(stairs, world, Vector2(39.0, 15.5 + 0.6 * k), headroom)
	var terrace: Array[Vector3] = []
	for x in range(23, 42, 2):
		for z: int in [17, 19, 21, 23]:
			_add_column(terrace, world, Vector2(x, z), headroom)
	var around: Array[Vector3] = []
	for x in range(18, 43, 2):
		_add_column(around, world, Vector2(x, 45.5), headroom)
	for z in range(24, 45, 2):
		_add_column(around, world, Vector2(16.5, z), headroom)
		_add_column(around, world, Vector2(43.5, z), headroom)
	var second_floor: Array[Vector3] = []
	for x in range(19, 42, 2):
		for z in range(25, 44, 2):
			_add_column(second_floor, world, Vector2(x, z), headroom)
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
			if on_roof(world, rest):
				found.append(rest)
	return found


## Whether a rest at `at` is on the roof: at the attic floor's height or above, and not inside the
## attic: outside its footprint, or above something that hides the attic's floor below it and
## within ATTIC_LOOK_M around (the roof's slope, an eave, a gutter; also the top of a box in the
## attic wider than that).
static func on_roof(world: HostWorldQuery, at: Vector3) -> bool:
	if at.y < ROOF_Y - ROOF_TOLERANCE_M:
		return false
	if not ATTIC.grow(-ATTIC_WALL_HALF_M).has_point(Vector2(at.x, at.z)):
		return true
	var attic_floor := Vector3(at.x, ROOF_Y + ROOF_TOLERANCE_M, at.z)
	if at.y <= attic_floor.y:
		return false
	var lifted := Items.lifted(at)
	for k in ATTIC_LOOK_POINTS + 1:
		var below := attic_floor
		if k > 0:
			var angle := TAU * k / ATTIC_LOOK_POINTS
			below += Vector3(cos(angle), 0.0, sin(angle)) * ATTIC_LOOK_M
			if not ATTIC.grow(-ATTIC_WALL_HALF_M).has_point(Vector2(below.x, below.z)):
				continue
		# Both ways: a ray misses a shape it starts in.
		if world.line_of_sight(lifted, below) and world.line_of_sight(below, lifted):
			return false
	return true


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


## Every floor in the column at `column` (x, z), top down: the first downward ray starts
## COLUMN_TOP_BELOW_ROOF_M under the roof, each next one COLUMN_STEP_M under the last hit (a ray
## ignores a shape it starts inside, so a slab thicker than that is passed, not hit twice), down to
## the ground. A floor with `headroom` clear above it is a spot; one under a ceiling (a wall's top,
## the inside of a slab) is not, since no player stands there.
static func _add_column(
	into: Array[Vector3], world: HostWorldQuery, column: Vector2, headroom: float
) -> void:
	var from := Vector3(column.x, ROOF_Y - COLUMN_TOP_BELOW_ROOF_M, column.y)
	while true:
		var floor_point := world.floor_below(from)
		if floor_point == WorldQuery.NO_FLOOR:
			return
		# Both ways: a ray misses a shape it starts in, so the upward one misses a crate standing
		# on this floor and the downward one a ceiling slab its top ends in.
		var feet := Items.lifted(floor_point)
		var head := feet + Vector3.UP * headroom
		if world.line_of_sight(feet, head) and world.line_of_sight(head, feet):
			into.append(floor_point)
		from = floor_point + Vector3.DOWN * COLUMN_STEP_M
