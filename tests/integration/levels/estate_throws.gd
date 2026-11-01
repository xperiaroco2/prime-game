## Throws against the estate's host collision world, for estate_roof_throw_test.gd (#1374; the
## throwing ADR, TD5 (a), the House's house_throws.gd): from every standable spot around and
## under each flat top no player stands on (the outbuildings' roofs, the gazebo's, the ship's, the
## fallen trunk's), a fan of throws flown as FlightTicks flies it (HouseThrows.rest_of), and where
## each one rests. An item on such a top is out of every player's reach (PickUp's InReach, 2 m from
## the feet, and no way up), so none may rest there.
##
## The tops (TOPS): each lot's footprint from docs/design/estate-map.md §3 (EstateDoc) at its
## centre, grown by EAVE_M; its height is read from the world, the first floor straight down onto
## the lot's centre, so a raised roof is swept at its new height.
##
## The spots: columns (x, z) on two rings around each top (RING_M out from its footprint, a column
## every RING_STEP_M) and a grid under it (INSIDE_STEP_M), each giving every floor in it below the
## top with room for a player's eye above it (_add_column), so a bench, a counter, a station box or
## the ship's deck at a sampled column is thrown from at its own height.
## Not swept: the House's lot, whose roof the roof ladder reaches (estate-map.md §5c), so an item
## on it is in reach; the open ground, which has no top over it.

const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
## The doc's modules (§3) whose top no player stands on.
const TOPS: Array[String] = [
	"Summer kitchen", "Pantry", "Greenhouse", "Garage", "Gazebo", "Ship", "Fallen trunk"
]
## The gazebo is round (r 3.5, no footprint in §3): its square roof's side (gazebo.tscn's Roof01).
const GAZEBO_ROOF_M := 7.4
## How far past a footprint a rest still lies on its top: the roof slab's overhang and an item's
## radius over its edge.
const EAVE_M := 0.5
## A rest at most this far under a top's surface is on it (the slabs are 0.2 m thick; every floor
## under a top is a metre and more below it).
const TOP_TOLERANCE_M := 0.3
## The rings of columns around a top, out from its footprint: by the wall (a player's capsule is
## 0.4 m) and a step back.
const RINGS_M: Array[float] = [0.5, 1.5]
const RING_STEP_M := 1.0
const INSIDE_STEP_M := 2.0
## Each column is read from this far under its top (below the slab), then from this far under
## each floor it finds.
const COLUMN_TOP_BELOW_M := 0.3
const COLUMN_STEP_M := 0.3
## The highest floor a player stands on round and under a top, by top (#1499): the
## ship has one deck, 1.2 m up (estate-map.md §5a); over it the art hull's curved skin, which
## no player reaches (no way up, the wing edges 1.5 m and more over the ground), drops more than
## COLUMN_TOP_BELOW_M below its top, so its own floors are no spots.
const HIGHEST_SPOT_M: Dictionary[String, float] = {"Ship": 1.5}


## The top of each module in TOPS: its plan rect (the footprint, not grown) and its height, read
## in `world`. A module whose centre has no floor above COLUMN_TOP_BELOW_M is left out (the test
## says so).
static func tops(world: HostWorldQuery) -> Dictionary[String, Dictionary]:
	var found: Dictionary[String, Dictionary] = {}
	for module in EstateDoc.modules():
		if not TOPS.has(module.name):
			continue
		var size := Vector2(module.size)
		if module.name == "Gazebo":
			size = Vector2(GAZEBO_ROOF_M, GAZEBO_ROOF_M)
		var top := world.floor_below(Vector3(module.centre.x, 20.0, module.centre.y))
		if top == WorldQuery.NO_FLOOR:
			continue
		found[module.name] = {
			"rect": Rect2(module.centre - size / 2.0, size),
			"y": top.y,
		}
	return found


## Every spot by top, each an Array of feet positions on a floor of `world` with `headroom` clear
## above it, below that top.
static func spots(world: HostWorldQuery, headroom: float) -> Dictionary[String, Array]:
	var found: Dictionary[String, Array] = {}
	var all_tops := tops(world)
	for top_name: String in all_tops:
		var rect: Rect2 = all_tops[top_name]["rect"]
		var below: float = (all_tops[top_name]["y"] as float) - COLUMN_TOP_BELOW_M
		below = minf(below, HIGHEST_SPOT_M.get(top_name, INF) as float)
		var into: Array[Vector3] = []
		for ring: float in RINGS_M:
			var around := rect.grow(ring)
			for column in _ring(around):
				_add_column(into, world, column, below, headroom)
		var x := rect.position.x + INSIDE_STEP_M / 2.0
		while x < rect.end.x:
			var z := rect.position.y + INSIDE_STEP_M / 2.0
			while z < rect.end.y:
				_add_column(into, world, Vector2(x, z), below, headroom)
				z += INSIDE_STEP_M
			x += INSIDE_STEP_M
		found[top_name] = into
	return found


## The rests on any top of the fan of throws from `feet`, flown with these numbers.
static func top_rests(
	world: HostWorldQuery,
	all_tops: Dictionary[String, Dictionary],
	feet: Vector3,
	eye_height: float,
	speed: float,
	gravity: float,
	radius: float,
	max_ticks: int
) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var lowest := INF
	for top_name: String in all_tops:
		lowest = minf(lowest, (all_tops[top_name]["y"] as float) - TOP_TOLERANCE_M)
	var ground := world.stand_floor_below(Items.lifted(feet))
	var eye := Vector3(feet.x, ground.y if ground != WorldQuery.NO_FLOOR else feet.y, feet.z)
	eye += Vector3.UP * eye_height
	var down := Vector3(0.0, -gravity, 0.0)
	var fallback := world.floor_below(Items.lifted(feet))
	for yaw_deg in range(0, 360, HouseThrows.YAW_STEP_DEG):
		for pitch_deg in range(0, HouseThrows.PITCH_TOP_DEG + 1, HouseThrows.PITCH_STEP_DEG):
			var yaw := deg_to_rad(yaw_deg)
			var pitch := deg_to_rad(pitch_deg)
			var facing := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			var velocity := facing * speed
			# The arc's top: a rest is floor_below of a point on the arc lifted, so a flight whose
			# top stays under the lowest top's tolerance rests on none (saves the sweeps).
			var top := eye.y + velocity.y * velocity.y / (2.0 * gravity)
			if top + Items.SURFACE_CLEARANCE_M < lowest:
				continue
			var rest := HouseThrows.rest_of(world, eye, velocity, down, radius, max_ticks, fallback)
			if on_a_top(all_tops, rest) != "":
				found.append(rest)
	return found


## The name of the top a rest at `at` lies on, or "" for none: inside its footprint grown by
## EAVE_M, at most TOP_TOLERANCE_M under its surface.
static func on_a_top(all_tops: Dictionary[String, Dictionary], at: Vector3) -> String:
	for top_name: String in all_tops:
		var rect: Rect2 = all_tops[top_name]["rect"]
		if not rect.grow(EAVE_M).has_point(Vector2(at.x, at.z)):
			continue
		if at.y >= (all_tops[top_name]["y"] as float) - TOP_TOLERANCE_M:
			return top_name
	return ""


## The columns on the edge of `rect`, every RING_STEP_M, corners included.
static func _ring(rect: Rect2) -> Array[Vector2]:
	var columns: Array[Vector2] = []
	var steps_x := ceili(rect.size.x / RING_STEP_M)
	var steps_z := ceili(rect.size.y / RING_STEP_M)
	for k in steps_x:
		var x := rect.position.x + rect.size.x * k / steps_x
		columns.append(Vector2(x, rect.position.y))
		columns.append(Vector2(rect.end.x - (x - rect.position.x), rect.end.y))
	for k in steps_z:
		var z := rect.position.y + rect.size.y * k / steps_z
		columns.append(Vector2(rect.end.x, z))
		columns.append(Vector2(rect.position.x, rect.end.y - (z - rect.position.y)))
	return columns


## Every floor in the column at `column` (x, z), top down from `from_y`: each next ray starts
## COLUMN_STEP_M under the last hit (a ray ignores a shape it starts inside), down to the ground. A
## floor with `headroom` clear above it is a spot (HouseThrows._add_column's rule).
static func _add_column(
	into: Array[Vector3], world: HostWorldQuery, column: Vector2, from_y: float, headroom: float
) -> void:
	var from := Vector3(column.x, from_y, column.y)
	while true:
		var floor_point := world.floor_below(from)
		if floor_point == WorldQuery.NO_FLOOR:
			return
		# Both ways: a ray misses a shape it starts in.
		var feet := Items.lifted(floor_point)
		var head := feet + Vector3.UP * headroom
		if world.line_of_sight(feet, head) and world.line_of_sight(head, feet):
			into.append(floor_point)
		from = floor_point + Vector3.DOWN * COLUMN_STEP_M


## Every flat box top of a layer-1 StaticBody3D in the level scene under `root` (the shapes the
## host's LevelWorld builds), each {"piece" (the root's child it is in), "body" (its path),
## "centre" (the top's centre), "narrow" and "long" (its sides, metres), "across" and "along" (the
## unit plan directions across its narrow side and along it)}. A box tilted off the vertical has
## no flat top and is left out. For estate_tops_reach_test.gd.
static func box_tops(root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	_add_box_tops(found, root, root)
	return found


static func _add_box_tops(into: Array[Dictionary], node: Node, root: Node) -> void:
	for child in node.get_children():
		_add_box_tops(into, child, root)
	var shape_node := node as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D or shape_node.disabled:
		return
	var body := shape_node.get_parent() as StaticBody3D
	if body == null or body.collision_layer & LevelWorld.WORLD_LAYER == 0:
		return
	var at := LevelWorld.transform_in_scene(shape_node, root)
	if not at.basis.y.normalized().is_equal_approx(Vector3.UP):
		return
	var size := (shape_node.shape as BoxShape3D).size * at.basis.get_scale()
	var across_local := Vector3.RIGHT if size.x <= size.z else Vector3.BACK
	var across := at.basis * across_local
	across.y = 0.0
	var piece := body as Node
	while piece.get_parent() != root and piece.get_parent() != null:
		piece = piece.get_parent()
	(
		into
		. append(
			{
				"piece": String(piece.name),
				"body": String(root.get_path_to(body)),
				"centre": at * Vector3(0.0, (shape_node.shape as BoxShape3D).size.y / 2.0, 0.0),
				"narrow": minf(size.x, size.z),
				"long": maxf(size.x, size.z),
				"across": across.normalized(),
				"along": Vector3.UP.cross(across).normalized(),
			}
		)
	)
