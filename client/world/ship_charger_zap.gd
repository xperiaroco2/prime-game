class_name ShipChargerZap
extends RefCounted
## The charger's lightning (#1556), ported from the art's reference `godot/charger/zap.gd`
## (prime-game-art, the crystal_charger HANDOFF: "the lightning ... and the crystal's glow are the
## game's"): arcs from the two inner prongs' electrodes into the seated crystal while it charges,
## sparks where they land, wrap arcs, crawlers, glints and halo loops round the crystal, one big
## flash at the end of a charge, then quiet. Its constants are the art's. Left out: the lens
## alcove's conduit pulses (a ship level piece, `charger_conduit.gdshader`).
## - Gating (step): arcs only while charging with 0 < charge < 1, or while `flash` > 0; none idle
##   or charged, none while the crystal is not drawn. Sparks live out their short life.
## - The art gates its flash on the look's state "charging"; here the caller passes the flash
##   (ShipStationLooks: the edge from CHARGING to WAITING) and whether it charges.
## - Arcs, sparks and lights live under the charger's root, in its frame; their shapes re-roll
##   every TICK s from a generator seeded per charger and are rebuilt every frame on the
##   electrodes' and the crystal's current places, so they follow the turning ring and the rising
##   crystal. The randomness is cosmetic: every peer shows arcs at the same moments, not the same
##   arcs.

const ARC_SHADER := preload("res://assets/environment/ship/charger_arc.gdshader")
## The electrodes on the track ring (r, h, er) in cm, placed at u = ±(r cos(HALF_DEG / 3) -
## 0.45 er), h, AXIS_D out of the wall: 0 the tip electrode (antennas-2b), 1 the low one.
const HALF_DEG := 12.0
const ELECTRODES: Array[Vector3] = [Vector3(14.84, 117.0, 0.9), Vector3(16.8, 101.0, 1.0)]
const AXIS_D := 0.38
## Per electrode: where on the crystal its arcs land (m up from the electrode) and the jitter.
const LIFT: Array[float] = [-0.045, 0.09]
const LIFT_JITTER: Array[float] = [0.04, 0.045]
const ANGLE_JITTER := 0.7
## Per electrode: the share of ticks it does not arc (the flicker's gaps).
const SKIP: Array[float] = [0.1, 0.45]
const TICK: Array[float] = [0.05, 0.08]
const FLASH_TICK := 0.03
const HALF_WIDTH: Array[float] = [0.02, 0.015]
const BRANCH_WIDTH := 0.55
const ROUGH := 0.28
const FLASH_WIDTH := 2.2
const FLASH_BRANCHES := 4
const LIGHT_COLOUR := Color(0.78, 0.88, 1.0)
const LIGHT_ENERGY: Array[float] = [0.7, 0.45]
const LIGHT_RANGE := 0.32
const FLASH_ENERGY := 2.4
const FLASH_RANGE := 0.6
const SPARKS_HIT: Array[int] = [2, 5]
const SPARK_ELECTRODE := 0.18
const SPARK_SPEED: Array[float] = [0.35, 1.1]
const SPARK_LIFE: Array[float] = [0.15, 0.4]
const SPARK_BURST := 60
const SPARK_HALF_WIDTH := 0.006
const GRAVITY := 5.0
const MAX_SPARKS := 320
const WRAP_SWEEP: Array[float] = [1.2, 3.0]
const WRAP_RISE := 0.05
const WRAP_OUT: Array[float] = [1.5, 2.3]
const CRAWL_CHANCE := 0.7
const GLINTS: Array[int] = [6, 10]
const GLINT_SPEED: Array[float] = [5.0, 10.0]
const GLINT_LIFE: Array[float] = [0.4, 0.9]
const GLINT_BURST := 70
const GLINT_HALF_WIDTH := 0.012
const GLINT_TRAIL := 0.7
const HALOS: Array[int] = [3, 5]
const FLASH_HALOS := 8
const HALO_SWEEP: Array[float] = [1.2, 2.6]
const HALO_OUT: Array[float] = [2.0, 3.4]
const HALO_RISE := 0.12
const HALO_SPIN := 9.0

var _root: Node3D
var _ring: Node3D
var _crystal: Node3D
var _locals := PackedVector3Array()
var _radii: Array[float] = []
var _mesh: ImmediateMesh
var _node: MeshInstance3D
var _mat: ShaderMaterial
var _lights: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _next := 0.0
var _arcs: Array[Arc] = []
var _sparks: Array[Spark] = []
var _halos: Array[Halo] = []
var _flashed := false
var _profile: ShipZapBolts.Profile
var _arcing := false
var _flashing := false
var _ends: Array[PackedVector3Array] = []
var _sense := -1.0
var _ring_y := 0.0
var _centre := Vector3.ZERO


## One electrode's arc this tick.
class Arc:
	var on := false
	var seed_of := 0
	var lift := 0.0
	var angle := 0.0
	var flicker := 1.0


## A spark (flying at `v` from `p`) or a glint (orbiting the crystal's axis: angle `a`, radius
## `rr`, height `h`, turning `w` rad/s, spiralling out `dr` and up `dh` per second).
class Spark:
	var orbit := false
	var p := Vector3.ZERO
	var v := Vector3.ZERO
	var a := 0.0
	var rr := 0.0
	var h := 0.0
	var w := 0.0
	var dr := 0.0
	var dh := 0.0
	var age := 0.0
	var life := 0.0


## A halo loop of a tick: its seed, start angle, the tick's start, sweep, height, rise and bulge.
class Halo:
	var seed_of := 0
	var a := 0.0
	var t0 := 0.0
	var sweep := 0.0
	var h := 0.0
	var dh := 0.0
	var out := 0.0


## Builds the arcs' mesh `ChargerZap` and a light per electrode under the charger's `root`, for
## the track `ring` (at its angle 0 now: the inner prongs left and right) and the seated
## `crystal`; `zap_seed` the generator's.
static func bind(root: Node3D, ring: Node3D, crystal: Node3D, zap_seed: int) -> ShipChargerZap:
	var zap := ShipChargerZap.new()
	zap._root = root
	zap._ring = ring
	zap._crystal = crystal
	zap._ring_y = ring.rotation.y
	var ring_t := ShipStationLooks.relative(ring, root)
	for side: float in [-1.0, 1.0]:
		for e: Vector3 in ELECTRODES:
			var u: float = side * (e.x * cos(deg_to_rad(HALF_DEG / 3.0)) - 0.45 * e.z) / 100.0
			zap._locals.append(ring_t.affine_inverse() * Vector3(u, e.y / 100.0, AXIS_D))
			zap._radii.append(e.z / 100.0)
	zap._mat = ShaderMaterial.new()
	zap._mat.shader = ARC_SHADER
	zap._mesh = ImmediateMesh.new()
	zap._node = MeshInstance3D.new()
	zap._node.name = "ChargerZap"
	zap._node.mesh = zap._mesh
	zap._node.material_override = zap._mat
	zap._node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zap._node.custom_aabb = AABB(Vector3(-0.6, 0.6, -0.3), Vector3(1.2, 1.2, 1.4))
	root.add_child(zap._node)
	for i: int in zap._locals.size():
		var l := OmniLight3D.new()
		l.name = "ZapLight%d" % i
		l.light_color = LIGHT_COLOUR
		l.omni_range = LIGHT_RANGE
		l.omni_attenuation = 2.0
		l.shadow_enabled = false
		l.visible = false
		root.add_child(l)
		zap._lights.append(l)
		zap._arcs.append(Arc.new())
	zap._rng.seed = zap_seed
	zap._profile = ShipZapBolts.profile(crystal)
	return zap


## One frame: the clock moves on by `delta`, the arcs re-roll every TICK s and follow the
## electrodes and the crystal, the sparks fly and die, the lights flicker. `charging` whether the
## charger charges, `charge` its share 0..1, `flash` the end-of-charge flash 1..0 (0: none).
func step(delta: float, charging: bool, charge: float, flash: float) -> void:
	var seated: bool = _crystal.visible
	_flashing = seated and flash > 0.0
	_arcing = _flashing or (charging and seated and charge > 0.0 and charge < 1.0)
	var ring_y := _ring.rotation.y
	var turned := wrapf(ring_y - _ring_y, -PI, PI)
	if delta > 0.0 and absf(turned) > 1e-5:
		_sense = signf(turned)
	_ring_y = ring_y
	_centre = ShipStationLooks.relative(_crystal, _root).origin
	_clock += minf(delta, 0.1)
	if not _arcing:
		_next = _clock
	while _arcing and _clock >= _next:
		_reroll()
		_next += FLASH_TICK if _flashing else _rng.randf_range(TICK[0], TICK[1])
	if _flashing and not _flashed:
		_flashed = true
		for k: int in SPARK_BURST:
			var ends := _arc_ends(k % _locals.size())
			_spark(ends[1], (ends[0] - ends[1]).normalized(), 1.4)
		for k: int in GLINT_BURST:
			_glint()
	if not _flashing:
		_flashed = false
	_fly(delta)
	var ramp: float = smoothstep(0.0, 0.03, charge) if not _flashing else 1.0 + 1.2 * flash
	_mat.set_shader_parameter("strength", ramp)
	_draw(flash, ramp)


## Whether the arcs run this frame.
func arcing() -> bool:
	return _arcing


## Whether the end-of-charge flash runs this frame.
func flashing() -> bool:
	return _flashing


## The arcs' current [start, hit] per electrode that arcs this tick (the charger root's frame).
func ends() -> Array[PackedVector3Array]:
	return _ends


## The electrodes' points in the ring's frame (tip left, low left, tip right, low right).
func electrodes() -> PackedVector3Array:
	return _locals


## The live sparks and glints.
func spark_count() -> int:
	return _sparks.size()


## The lights at the hits, one per electrode.
func lights() -> Array[OmniLight3D]:
	return _lights


## The arcs' mesh node.
func node() -> MeshInstance3D:
	return _node


func _reroll() -> void:
	for i: int in _arcs.size():
		var a := _arcs[i]
		var kind: int = i % ELECTRODES.size()
		a.seed_of = _rng.randi()
		a.on = _flashing or _rng.randf() >= SKIP[kind]
		a.lift = LIFT[kind] + _rng.randf_range(-1.0, 1.0) * LIFT_JITTER[kind]
		a.angle = _rng.randf_range(-ANGLE_JITTER, ANGLE_JITTER)
		a.flicker = _rng.randf_range(0.55, 1.0)
		if not a.on:
			continue
		var ends := _arc_ends(i)
		var out: Vector3 = (ends[0] - ends[1]).normalized()
		for k: int in _rng.randi_range(SPARKS_HIT[0], SPARKS_HIT[1]):
			_spark(ends[1], out, 1.0)
		if _rng.randf() < SPARK_ELECTRODE:
			_spark(ends[0], -out, 0.7)
	for k: int in _rng.randi_range(GLINTS[0], GLINTS[1]) * (3 if _flashing else 1):
		_glint()
	_halos.clear()
	for k: int in FLASH_HALOS if _flashing else _rng.randi_range(HALOS[0], HALOS[1]):
		var halo := Halo.new()
		halo.seed_of = _rng.randi()
		halo.a = _rng.randf_range(0.0, TAU)
		halo.t0 = _clock
		halo.sweep = _rng.randf_range(HALO_SWEEP[0], HALO_SWEEP[1]) * (1.4 if _flashing else 1.0)
		halo.h = _rng.randf_range(_profile.lo + 0.02, _profile.hi - 0.02)
		halo.dh = _rng.randf_range(-HALO_RISE, HALO_RISE)
		halo.out = _rng.randf_range(HALO_OUT[0], HALO_OUT[1]) * (1.2 if _flashing else 1.0)
		_halos.append(halo)


## Arc i's start (on its electrode's surface, toward the hit) and its hit on the crystal's
## surface, in the root's frame, now.
func _arc_ends(i: int) -> PackedVector3Array:
	var e: Vector3 = ShipStationLooks.relative(_ring, _root) * _locals[i]
	var ct := ShipStationLooks.relative(_crystal, _root)
	var ec: Vector3 = ct.affine_inverse() * e
	var a := _arcs[i]
	var lift: float = a.lift + (0.04 if _flashing else 0.0)
	var h: float = clampf(ec.y + lift, _profile.lo + 0.01, _profile.hi - 0.01)
	var dir := Vector2(ec.x, ec.z).normalized().rotated(a.angle)
	var r: float = _profile.radius(h) * 0.97
	var hit: Vector3 = ct * Vector3(dir.x * r, h, dir.y * r)
	var start: Vector3 = e + (hit - e).normalized() * _radii[i]
	return PackedVector3Array([start, hit])


func _spark(at: Vector3, out: Vector3, speed: float) -> void:
	if _sparks.size() >= MAX_SPARKS:
		return
	var rand := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	var s := Spark.new()
	s.p = at
	s.v = (
		(out + rand * 0.9).normalized() * _rng.randf_range(SPARK_SPEED[0], SPARK_SPEED[1]) * speed
	)
	s.life = _rng.randf_range(SPARK_LIFE[0], SPARK_LIFE[1])
	_sparks.append(s)


## A glint: a bright speck orbiting the crystal's axis the ring's way, spiralling out and drifting
## up or down.
func _glint() -> void:
	if _sparks.size() >= MAX_SPARKS:
		return
	var s := Spark.new()
	s.orbit = true
	s.h = _rng.randf_range(_profile.lo + 0.02, _profile.hi - 0.02)
	s.a = _rng.randf_range(0.0, TAU)
	s.rr = _profile.radius(s.h) * _rng.randf_range(1.1, 1.5)
	s.w = _sense * _rng.randf_range(GLINT_SPEED[0], GLINT_SPEED[1])
	s.dr = _rng.randf_range(0.03, 0.12)
	s.dh = _rng.randf_range(-0.03, 0.06)
	s.life = _rng.randf_range(GLINT_LIFE[0], GLINT_LIFE[1])
	_sparks.append(s)


func _orbit_at(s: Spark, a: float) -> Vector3:
	return _centre + Basis(Vector3.UP, a) * Vector3(s.rr, 0.0, 0.0) + Vector3(0.0, s.h, 0.0)


func _fly(delta: float) -> void:
	var keep: Array[Spark] = []
	for s: Spark in _sparks:
		s.age += delta
		if s.age >= s.life:
			continue
		if s.orbit:
			s.a += s.w * delta
			s.rr += s.dr * delta
			s.h += s.dh * delta
		else:
			s.v.y -= GRAVITY * delta
			s.v *= maxf(0.0, 1.0 - 2.0 * delta)
			s.p += s.v * delta
		keep.append(s)
	_sparks = keep


## Rebuilds the ribbons: per arc a jagged bolt with its branches, per spark a short streak; places
## the lights.
func _draw(flash: float, ramp: float) -> void:
	var strips: Array[ShipZapBolts.Strip] = []
	_ends = []
	for i: int in _arcs.size():
		_lights[i].visible = _arcing and _arcs[i].on
		if _lights[i].visible:
			_draw_arc(i, strips, flash, ramp)
	if _arcing:
		for h: Halo in _halos:
			_draw_halo(h, strips)
	for s: Spark in _sparks:
		if s.orbit:
			var g: float = (1.0 - s.age / s.life) * minf(1.0, s.age * 20.0)
			var tw: float = GLINT_TRAIL * signf(s.w)
			var trail := PackedVector3Array()
			for k: int in 6:
				trail.append(_orbit_at(s, s.a - tw * (1.0 - k / 5.0)))
			strips.append(ShipZapBolts.Strip.new(trail, GLINT_HALF_WIDTH, 0.0, g))
			continue
		var tail: Vector3 = s.v * 0.02 if s.v.length() * 0.02 > 0.004 else s.v.normalized() * 0.004
		var fade: float = 1.0 - s.age / s.life
		var streak := PackedVector3Array([s.p - tail, s.p])
		strips.append(ShipZapBolts.Strip.new(streak, SPARK_HALF_WIDTH, 0.3 * fade, fade))
	ShipZapBolts.draw(_mesh, strips)


func _draw_arc(i: int, strips: Array[ShipZapBolts.Strip], flash: float, ramp: float) -> void:
	var a := _arcs[i]
	var l := _lights[i]
	var kind: int = i % ELECTRODES.size()
	var ends := _arc_ends(i)
	_ends.append(ends)
	var rng := RandomNumberGenerator.new()
	rng.seed = a.seed_of
	var w: float = HALF_WIDTH[kind] * (FLASH_WIDTH if _flashing else 1.0)
	var main := ShipZapBolts.bolt(rng, ends[0], ends[1], 4, ROUGH)
	strips.append(ShipZapBolts.Strip.new(main, w, 1.0, 1.0))
	var along: Vector3 = ends[1] - ends[0]
	for b: int in FLASH_BRANCHES if _flashing else rng.randi_range(0, 2):
		var j: int = rng.randi_range(int(main.size() * 0.2), int(main.size() * 0.75))
		var from: Vector3 = main[j]
		var side := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var reach: float = along.length() * rng.randf_range(0.3, 0.6) * (1.4 if _flashing else 1.0)
		var to: Vector3 = (
			from + (along.normalized() * 0.5 + side.normalized() * 0.8).normalized() * reach
		)
		var branch := ShipZapBolts.bolt(rng, from, to, 3, ROUGH * 1.3)
		strips.append(ShipZapBolts.Strip.new(branch, w * BRANCH_WIDTH, 0.85, 0.0))
	strips.append(ShipZapBolts.Strip.new(_wrap(rng, ends[0]), w * 0.8, 1.0, 0.25))
	if kind == 0 and (_flashing or rng.randf() < CRAWL_CHANCE):
		strips.append(ShipZapBolts.Strip.new(_crawl(rng), w * 0.6, 0.9, 0.9))
	var out: Vector3 = (ends[0] - ends[1]).normalized()
	l.position = ends[1] + out * 0.015
	l.omni_range = lerpf(LIGHT_RANGE, FLASH_RANGE, flash) if _flashing else LIGHT_RANGE
	l.light_energy = (
		FLASH_ENERGY * flash if _flashing else LIGHT_ENERGY[kind] * a.flicker * minf(ramp, 1.0)
	)


func _draw_halo(h: Halo, strips: Array[ShipZapBolts.Strip]) -> void:
	var hw: float = HALF_WIDTH[0] * 0.8 * (FLASH_WIDTH * 0.7 if _flashing else 1.0)
	var loop := _halo(h)
	strips.append(ShipZapBolts.Strip.new(loop, hw, 0.95, 0.95))
	# a fork off the loop's apex into the air, outward and up or down, so it reads as lightning
	var frng := RandomNumberGenerator.new()
	frng.seed = h.seed_of + 1
	if _flashing or frng.randf() < 0.6:
		var from: Vector3 = loop[loop.size() / 2 + frng.randi_range(-3, 3)]
		var out := Vector3(from.x - _centre.x, 0.0, from.z - _centre.z).normalized()
		var to: Vector3 = (
			from
			+ out * frng.randf_range(0.025, 0.05)
			+ Vector3(0.0, frng.randf_range(-0.035, 0.035), 0.0)
		)
		var fork := ShipZapBolts.bolt(frng, from, to, 2, ROUGH * 1.4)
		strips.append(ShipZapBolts.Strip.new(fork, hw * BRANCH_WIDTH, 0.9, 0.0))


## A wrap arc: from the electrode's start round the crystal's surface (WRAP_OUT of its radius),
## the ring's way, jagged; in the root's frame.
func _wrap(rng: RandomNumberGenerator, start: Vector3) -> PackedVector3Array:
	var ct := ShipStationLooks.relative(_crystal, _root)
	var lo := _profile.lo + 0.01
	var hi := _profile.hi - 0.01
	var ec: Vector3 = ct.affine_inverse() * start
	var a0: float = atan2(ec.z, ec.x)
	var sweep: float = (
		rng.randf_range(WRAP_SWEEP[0], WRAP_SWEEP[1]) * (1.5 if _flashing else 1.0) * -_sense
	)
	var h0: float = clampf(ec.y - 0.01, lo, hi)
	var dh: float = rng.randf_range(-WRAP_RISE, WRAP_RISE)
	var out: float = rng.randf_range(WRAP_OUT[0], WRAP_OUT[1])
	var pts := PackedVector3Array([start])
	var n := 14
	for k: int in range(1, n + 1):
		var f: float = float(k) / n
		var h: float = clampf(h0 + dh * f, lo, hi)
		var r: float = (
			_profile.radius(h) * out * (1.0 + 0.12 * sin(3.0 * PI * f + out * 7.0))
			+ rng.randf_range(-0.006, 0.008)
		)
		var a: float = a0 + sweep * f
		pts.append(ct * Vector3(cos(a) * r, h + rng.randf_range(-0.006, 0.006), sin(a) * r))
	return pts


## A halo loop: from the crystal's surface out into the air and back onto it `sweep` rad round,
## turned round the axis the ring's way at HALO_SPIN rad/s since its tick began.
func _halo(h: Halo) -> PackedVector3Array:
	var ct := ShipStationLooks.relative(_crystal, _root)
	var lo := _profile.lo + 0.01
	var hi := _profile.hi - 0.01
	var rng := RandomNumberGenerator.new()
	rng.seed = h.seed_of
	var a0: float = h.a - _sense * HALO_SPIN * (_clock - h.t0)
	var sweep: float = h.sweep * -_sense
	var pts := PackedVector3Array()
	var n := 14
	for k: int in n + 1:
		var f: float = float(k) / n
		var hh: float = clampf(h.h + h.dh * f, lo, hi)
		var bulge: float = sin(PI * f)
		var r: float = (
			_profile.radius(hh) * lerpf(1.0, h.out, bulge) + rng.randf_range(-0.014, 0.014) * bulge
		)
		var a: float = a0 + sweep * f
		pts.append(
			ct * Vector3(cos(a) * r, hh + rng.randf_range(-0.018, 0.018) * bulge, sin(a) * r)
		)
	return pts


## A crawler: a short jagged bolt between two points on the crystal's surface, a quarter to half a
## turn apart.
func _crawl(rng: RandomNumberGenerator) -> PackedVector3Array:
	var ct := ShipStationLooks.relative(_crystal, _root)
	var ends := PackedVector3Array()
	var a: float = rng.randf_range(0.0, TAU)
	for k: int in 2:
		var h: float = rng.randf_range(_profile.lo + 0.02, _profile.hi - 0.02)
		var r: float = _profile.radius(h) * 1.03
		ends.append(ct * Vector3(cos(a) * r, h, sin(a) * r))
		a += rng.randf_range(0.8, 1.8)
	return ShipZapBolts.bolt(rng, ends[0], ends[1], 3, ROUGH)
