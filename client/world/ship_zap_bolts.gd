class_name ShipZapBolts
extends RefCounted
## The lightning's shapes (#1556), ported from the art's charger reference `godot/charger/zap.gd`
## (prime-game-art): jagged bolts by midpoint displacement, the camera-facing ribbons
## `assets/environment/ship/charger_arc.gdshader` turns, and a crystal's radius by height. Pure
## geometry: ShipChargerZap (the charger's arcs) draws with it.


## One ribbon: its points, its half width (m) and its alpha from its start to its end.
class Strip:
	var pts: PackedVector3Array
	var hw: float
	var a0: float
	var a1: float

	func _init(points: PackedVector3Array, half_width: float, alpha0: float, alpha1: float) -> void:
		pts = points
		hw = half_width
		a0 = alpha0
		a1 = alpha1


## A crystal's radius by height (its own frame: the axis +Y through the origin): the vertices'
## largest distance from the axis per STEP band, from `lo` to `hi` (m).
class Profile:
	const STEP := 0.005
	var lo := 0.0
	var hi := 0.0
	var r := PackedFloat32Array()

	## The radius at height `h`, clamped to the ends.
	func radius(h: float) -> float:
		var k: int = clampi(int((h - lo) / STEP), 0, r.size() - 1)
		return maxf(r[k], r[maxi(k - 1, 0)])


## A bolt from `a` to `b`: midpoint displacement `levels` times (2^levels segments), each level's
## sideways step at most `rough` x its segment's length, the ends fixed.
static func bolt(
	rng: RandomNumberGenerator, a: Vector3, b: Vector3, levels: int, rough: float
) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var dir: Vector3 = (b - a).normalized()
	var s1: Vector3 = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var s2: Vector3 = dir.cross(s1)
	for level: int in levels:
		var next := PackedVector3Array()
		for i: int in pts.size() - 1:
			var p: Vector3 = pts[i]
			var q: Vector3 = pts[i + 1]
			var amp: float = p.distance_to(q) * rough
			next.append(p)
			next.append(
				(p + q) * 0.5 + s1 * rng.randf_range(-amp, amp) + s2 * rng.randf_range(-amp, amp)
			)
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


## One camera-facing ribbon (the arc shader turns it): two triangles per segment, the joints
## shared.
static func strip(im: ImmediateMesh, s: Strip) -> void:
	var n: int = s.pts.size()
	var tang := PackedVector3Array()
	for i: int in n:
		var t: Vector3 = s.pts[mini(i + 1, n - 1)] - s.pts[maxi(i - 1, 0)]
		tang.append(t.normalized() if t.length() > 1e-6 else Vector3.UP)
	var corners: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1)
	]
	for i: int in n - 1:
		for c: Vector2i in corners:
			var k: int = i + c.x
			var f: float = float(k) / float(n - 1)
			im.surface_set_normal(tang[k])
			im.surface_set_uv(Vector2(f, float(c.y)))
			im.surface_set_uv2(Vector2(s.hw * lerpf(1.0, 0.7, f), 0.0))
			im.surface_set_color(Color(1, 1, 1, lerpf(s.a0, s.a1, f)))
			im.surface_add_vertex(s.pts[k])


## Draws `strips` into `im` as one surface; clears it first. Returns the vertex count (0: nothing
## drawn).
static func draw(im: ImmediateMesh, strips: Array[Strip]) -> int:
	im.clear_surfaces()
	var verts := 0
	for s: Strip in strips:
		verts += maxi(0, s.pts.size() - 1) * 6
	if verts == 0:
		return 0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: Strip in strips:
		if s.pts.size() > 1:
			strip(im, s)
	im.surface_end()
	return verts


## The profile of the meshes under `crystal`, in its frame.
static func profile(crystal: Node3D) -> Profile:
	var pts := PackedVector3Array()
	for m: Node in crystal.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if mesh.mesh == null:
			continue
		var t := ShipStationLooks.relative(mesh, crystal)
		for s: int in mesh.mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				pts.append(t * v)
	var p := Profile.new()
	if pts.is_empty():
		p.r.resize(1)
		return p
	p.lo = INF
	p.hi = -INF
	for v: Vector3 in pts:
		p.lo = minf(p.lo, v.y)
		p.hi = maxf(p.hi, v.y)
	p.r.resize(maxi(1, ceili((p.hi - p.lo) / Profile.STEP) + 1))
	for v: Vector3 in pts:
		var k: int = int((v.y - p.lo) / Profile.STEP)
		p.r[k] = maxf(p.r[k], Vector2(v.x, v.z).length())
	return p
