extends SceneTree
## The estate ship's #1560 caps, probed from the estate itself and written as trimeshes of thin
## boxes (backfaced like the skin) under its `Hull` body, in the ship lot's frame:
## - `cap_belly_skirt_col.tres`: a skirt along the line where the belly's clearance over the ground
##   falls to LOW_M (a crawl space no player enters), so an item thrown under it drops at its foot.
##   The belly's underside is probed every STEP_M; a hit under PAD_M is a landing leg's pad (solid,
##   left outside); the edge where the probe finds nothing in front of the throat (z under OPEN_Z)
##   is the solid ramp, left open. The contour is simplified to within SKIRT_TOL_M and its first
##   half mirrored about x 0, so both sides match.
## - `cap_lens_panes_{west,east}_col.tres`: panes just inside each lens room's wall panels, from
##   PANE_BOTTOM_M up to PANE_UNDER_SKIN_M under the skin, over ARCS (the east room's degrees from
##   its centre, +z 0, +x 90; the west room's mirrored): round the room but its alcove's lintel
##   and its corridor's mouth, which #1551's caps hold. Each degree is probed (the panel's face,
##   its top, the skin over it); a degree whose top or skin the probe misses is dropped.
## The caps it wrote last time (OWN_CAPS) are off while it probes; it stops with an error when the
## belly's contour does not meet the open edge exactly once.
## Run it after a new ship package or a moved skin:
## `tools/run.sh run tests/fixtures/ship_cap_colliders.gd --headless`; then run
## `tests/integration/levels/estate_ship_hull_throw_test.gd`, whose ground pass and pane tests go
## red when a cap falls short.

const MAP := "res://levels/estate/estate.tscn"
const SHIP := "Ship"
const OUT := "res://levels/estate/rooms/ship_hull/%s_col.tres"
const STEP_M := 0.1
const HALF_X := 140
const HALF_Z := 120
const LOW_M := 1.1
const PAD_M := 0.3
const OPEN_Z := -8.0
const SKIRT_TOL_M := 0.1
const SKIRT_BOTTOM_M := -0.1
const SKIRT_TOP_M := 1.15
const SKIRT_HALF_M := 0.05
const LENS_CENTRE := Vector2(10.5, 1.2)
const ARCS: Array[Vector2i] = [Vector2i(18, 221), Vector2i(302, 327)]
const FACE_AT_M: Array[float] = [3.40, 3.45]
const PANE_BOTTOM_M := 3.40
const PANE_UNDER_SKIN_M := 0.06
const PANE_IN_M := 0.03
const PANE_HALF_M := 0.02
const PANE_TOL_M := 0.01
## The saved vertices are snapped to a tenth of a millimetre (ship_hull_colliders.gd's).
const SNAP_M := 0.0001

## The CollisionShape3D names (find_children patterns) of the caps this script writes.
const OWN_CAPS: Array[String] = ["CapBellySkirt", "CapLensPanes*"]

var _space: PhysicsDirectSpaceState3D
var _at := Transform3D.IDENTITY


func _initialize() -> void:
	var root := (load(MAP) as PackedScene).instantiate()
	_at = LevelWorld.transform_in_scene(root.get_node(SHIP) as Node3D, root)
	# The probe must not meet the caps it wrote last time (#1551's caps stay: they are geometry).
	for own: String in OWN_CAPS:
		for found: Node in root.find_children(own, "CollisionShape3D", true, false):
			(found as CollisionShape3D).disabled = true
	var level := LevelWorld.from_scene(root, MAP)
	root.free()
	_space = level.space_state()
	var skirt := _skirt()
	if skirt.is_empty():
		_space = null
		quit(1)
		return
	_save("cap_belly_skirt", skirt)
	for side: int in [-1, 1]:
		_save("cap_lens_panes_%s" % ("east" if side > 0 else "west"), _panes(side))
	_space = null
	level = null
	quit()


## The first hit of the ray from `from` to `to` (ship frame) on the world layer, in the ship frame;
## Vector3.INF on none.
func _hit(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(_at * from, _at * to, LevelWorld.WORLD_LAYER)
	query.hit_back_faces = true
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return _at.affine_inverse() * (hit["position"] as Vector3)


func _skirt() -> PackedVector3Array:
	var under: Dictionary[Vector2i, float] = {}
	for i in range(-HALF_X, HALF_X + 1):
		for j in range(-HALF_Z, HALF_Z + 1):
			var hit := _hit(
				Vector3(i * STEP_M, 0.02, j * STEP_M), Vector3(i * STEP_M, 3.0, j * STEP_M)
			)
			if hit != Vector3.INF:
				under[Vector2i(i, j)] = hit.y
	var contour := _open_contour(under)
	if contour.is_empty():
		return PackedVector3Array()
	var line := _simplified(contour, SKIRT_TOL_M)
	var half: Array[Vector2] = []
	for point: Vector2 in line:
		if signf(point.x) != signf(line[0].x):
			break
		half.append(point)
	var mirrored: Array[Vector2] = half.duplicate()
	for k in range(half.size() - 1, -1, -1):
		mirrored.append(Vector2(-half[k].x, half[k].y))
	var faces := PackedVector3Array()
	for k in mirrored.size() - 1:
		var from := mirrored[k]
		var to := mirrored[k + 1]
		_box(faces, from, to, SKIRT_TOP_M, SKIRT_TOP_M, SKIRT_BOTTOM_M, SKIRT_HALF_M)
	return faces


## The boundary of the cells under the belly lower than LOW_M (a pad's cells are not), traced with
## the low side on the left and joined across a diagonal (the rightmost turn first), the longest
## loop, opened where it runs along the open edge (OPEN_Z): the points from one end to the other.
func _open_contour(under: Dictionary[Vector2i, float]) -> Array[Vector2]:
	var low := func(cell: Vector2i) -> bool:
		return under.has(cell) and under[cell] >= PAD_M and under[cell] < LOW_M
	var out: Dictionary[Vector2i, Array] = {}
	var sides: Array[Array] = [
		[Vector2i(1, 0), Vector2i(1, -1), Vector2i(1, 1)],
		[Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(-1, -1)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)],
		[Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)],
	]
	for cell: Vector2i in under:
		if not low.call(cell):
			continue
		for side: Array in sides:
			var next: Vector2i = cell + (side[0] as Vector2i)
			if low.call(next):
				continue
			var from: Vector2i = cell * 2 + (side[1] as Vector2i)
			var to: Vector2i = cell * 2 + (side[2] as Vector2i)
			if not out.has(from):
				out[from] = []
			out[from].append([to, not under.has(next)])
	var best: Array = []
	var used: Dictionary[String, bool] = {}
	for start: Vector2i in out:
		for edge: Array in out[start]:
			if used.has("%s>%s" % [start, edge[0]]):
				continue
			var loop: Array = []
			var previous := start
			var at := edge[0] as Vector2i
			used["%s>%s" % [start, at]] = true
			loop.append([start, edge[1]])
			while at != start:
				var way := at - previous
				var turn := INF
				var pick: Array = []
				for option: Array in out[at]:
					if used.has("%s>%s" % [at, option[0]]):
						continue
					var next_way := (option[0] as Vector2i) - at
					var cross := float(way.x * next_way.y - way.y * next_way.x)
					if cross < turn:
						turn = cross
						pick = option
				if pick.is_empty():
					push_error("the belly's contour does not close at %s" % at)
					return []
				used["%s>%s" % [at, pick[0]]] = true
				loop.append([at, pick[1]])
				previous = at
				at = pick[0]
			if loop.size() > best.size():
				best = loop
	var open: Dictionary[int, bool] = {}
	for k in best.size():
		var vertex := best[k][0] as Vector2i
		if best[k][1] and vertex.y * STEP_M / 2.0 < OPEN_Z:
			open[k] = true
	var ends: Array[int] = []
	for k: int in open:
		if not open.has((k + 1) % best.size()):
			ends.append(k)
	if ends.size() != 1:
		push_error("the belly's contour meets the open edge %d times, not once" % ends.size())
		return []
	var last := ends[0]
	var points: Array[Vector2] = []
	var k := (last + 1) % best.size()
	while true:
		points.append(Vector2(best[k][0] as Vector2i) * STEP_M / 2.0)
		if open.has(k):
			break
		k = (k + 1) % best.size()
	return points


func _panes(side: int) -> PackedVector3Array:
	var centre := Vector3(side * LENS_CENTRE.x, 0.0, LENS_CENTRE.y)
	var faces := PackedVector3Array()
	for arc: Vector2i in ARCS:
		var line: Array[Vector3] = []
		var first := arc.x if side > 0 else 360 - arc.y
		var past := arc.y if side > 0 else 360 - arc.x
		for degree in range(first, past + 1):
			var way := Vector3(sin(deg_to_rad(degree)), 0.0, cos(deg_to_rad(degree)))
			var face := -1.0
			for height: float in FACE_AT_M:
				var at := centre + Vector3.UP * height
				var hit := _hit(at, at + way * 6.0)
				if hit != Vector3.INF:
					face = Vector2(hit.x - centre.x, hit.z - centre.z).length()
			if face < 0.0:
				continue
			var behind := centre + way * (face + 0.04)
			var top := _hit(behind + Vector3.UP * 3.8, behind + Vector3.UP * 1.3)
			if top == Vector3.INF:
				continue
			var over := _hit(top + Vector3.UP * 0.01, top + Vector3.UP * 3.0)
			var inside := centre + way * (face - PANE_IN_M)
			var above := _hit(inside + Vector3.UP * 3.0, inside + Vector3.UP * 6.0)
			var skin := over.y if over != Vector3.INF else -1.0
			if above != Vector3.INF and above.y >= top.y + 0.1:
				skin = minf(skin, above.y) if skin > 0.0 else above.y
			if skin < top.y + 0.1:
				continue
			var pane := centre + way * (face - PANE_IN_M)
			line.append(Vector3(pane.x, skin - PANE_UNDER_SKIN_M, pane.z))
		var kept := _simplified_tops(line, PANE_TOL_M)
		for k in kept.size() - 1:
			var from := Vector2(kept[k].x, kept[k].z)
			var to := Vector2(kept[k + 1].x, kept[k + 1].z)
			_box(faces, from, to, kept[k].y, kept[k + 1].y, PANE_BOTTOM_M, PANE_HALF_M)
	return faces


## `points` simplified to within `tolerance_m` (Douglas-Peucker on the plan).
func _simplified(points: Array[Vector2], tolerance_m: float) -> Array[Vector2]:
	var flat: Array[Vector3] = []
	for point: Vector2 in points:
		flat.append(Vector3(point.x, 0.0, point.y))
	var kept: Array[Vector2] = []
	for point: Vector3 in _simplified_tops(flat, tolerance_m):
		kept.append(Vector2(point.x, point.z))
	return kept


## `points` simplified to within `tolerance_m` on the plan (x, z) and in height (y, each kept
## point's own, a dropped one's read along the line between its kept neighbours).
func _simplified_tops(points: Array[Vector3], tolerance_m: float) -> Array[Vector3]:
	if points.size() < 3:
		return points
	var from := Vector2(points[0].x, points[0].z)
	var to := Vector2(points[-1].x, points[-1].z)
	var worst := 0.0
	var at := 0
	for k in range(1, points.size() - 1):
		var point := Vector2(points[k].x, points[k].z)
		var on := Geometry2D.get_closest_point_to_segment_uncapped(point, from, to)
		var along := from.distance_to(on) / maxf(from.distance_to(to), 0.0001)
		var height := lerpf(points[0].y, points[-1].y, along)
		var off := maxf(on.distance_to(point), absf(points[k].y - height))
		if off > worst:
			worst = off
			at = k
	if worst <= tolerance_m:
		return [points[0], points[-1]]
	var head := _simplified_tops(points.slice(0, at + 1), tolerance_m)
	head.pop_back()
	head.append_array(_simplified_tops(points.slice(at), tolerance_m))
	return head


## Appends to `faces` the 12 triangles of a box `half_m` either side of the plan segment from
## `from` to `to` (lengthened by `half_m` at each end, so neighbours overlap), from `bottom_m` up
## to `from_top_m` at its start and `to_top_m` at its end.
func _box(
	faces: PackedVector3Array,
	from: Vector2,
	to: Vector2,
	from_top_m: float,
	to_top_m: float,
	bottom_m: float,
	half_m: float
) -> void:
	var along := (to - from).normalized()
	var across := Vector2(-along.y, along.x) * half_m
	var start := from - along * half_m
	var end := to + along * half_m
	var corners: Array[Vector3] = []
	for end_at: Array in [[start, from_top_m], [end, to_top_m]]:
		for sign_of: float in [-1.0, 1.0]:
			var plan: Vector2 = (end_at[0] as Vector2) + across * sign_of
			corners.append(Vector3(plan.x, bottom_m, plan.y))
			corners.append(Vector3(plan.x, end_at[1] as float, plan.y))
	var quads: Array[Array] = [
		[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]
	]
	for quad: Array in quads:
		for k: int in [0, 1, 2, 0, 2, 3]:
			faces.append(corners[quad[k] as int].snapped(Vector3.ONE * SNAP_M))


func _save(stem: String, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var error := ResourceSaver.save(shape, OUT % stem)
	print("%s: %d triangles, %s" % [OUT % stem, faces.size() / 3, error])
