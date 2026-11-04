class_name ShipBoardSmoke
extends RefCounted
## The smoke at a breaker board's tripped cores (#1556, ARCHITECTURE §9.5.27): GDD §8's breakers
## "pop out and smoke", and the art package leaves the effect to the game ("their point is the
## core's centre", breaker_board HANDOFF.md). Per core an emitter `TrippedCore<i>` under the board's
## root at the core's centre with one CPUParticles3D `CoreSmoke`, rising and growing, its puffs
## fading out when the core stops. Values only: ShipBoardLook switches a core on and off as
## ShipStationLooks says. Every number here is a placeholder look, "not a decision" (#507).

const SMOKE_COLOUR := Color(0.32, 0.32, 0.34, 0.55)

var _emitters: Array[Node3D] = []
var _smoke: Array[CPUParticles3D] = []


## An emitter under `root` at each of `centres` (the cores' centres in root's frame), all quiet.
static func build(root: Node3D, centres: Array[Vector3]) -> ShipBoardSmoke:
	var smoke := ShipBoardSmoke.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.07, 0.07)
	mesh.material = _smoke_material()
	for i: int in centres.size():
		var at := Node3D.new()
		at.name = "TrippedCore%d" % i
		at.position = centres[i]
		root.add_child(at)
		smoke._emitters.append(at)
		smoke._smoke.append(_smoke_emitter(mesh, at))
	return smoke


## Core `index` smoking or not: off stops the emitting, and what is up fades out.
func set_smoking(index: int, on: bool) -> void:
	_smoke[index].emitting = on


## Whether core `index`'s smoke is emitting (its particles outlive it).
func smoking(index: int) -> bool:
	return _smoke[index].emitting


func emitter(index: int) -> Node3D:
	return _emitters[index]


func size() -> int:
	return _smoke.size()


static func _smoke_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Else billboarding drops each puff's scale and the grow curve does nothing.
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	# A soft round puff, not a square: white in the middle, clear at the rim.
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 32
	puff.height = 32
	var soft := Gradient.new()
	soft.set_color(0, Color.WHITE)
	soft.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	puff.gradient = soft
	m.albedo_texture = puff
	return m


static func _smoke_emitter(mesh: QuadMesh, at: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "CoreSmoke"
	p.mesh = mesh
	p.emitting = false
	p.amount = 10
	p.lifetime = 2.5
	p.randomness = 0.4
	p.direction = Vector3(0.0, 1.0, 0.3)
	p.spread = 20.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	p.damping_min = 0.05
	p.damping_max = 0.1
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, SMOKE_COLOUR)
	fade.set_color(1, Color(SMOKE_COLOUR, 0.0))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	at.add_child(p)
	return p
