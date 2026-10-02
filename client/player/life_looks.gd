class_name LifeLooks
extends RefCounted
## The greybox looks of the life states (the M4 ADR's D8 (a), placeholders "distinct at a glance in
## a `shot`"): a downed player is their capsule lying on its side in their colour; a body the same
## in grey with a dark cross; invulnerability a translucent white shell that pulses. Shared by the
## own PlayerController, RemotePlayerBody and the body views (client/world/body_views.gd), sized
## from the client's own copy of the mode's PlayerRules.

## A player's colour until players have colours of their own.
const PLAYER_COLOUR := Color(0.25, 0.45, 0.85)
const BODY_COLOUR := Color(0.55, 0.55, 0.55)
const CROSS_COLOUR := Color(0.08, 0.08, 0.1)
const SHELL_COLOUR := Color(1.0, 1.0, 1.0, 0.35)
## How much bigger than the capsule the shell is, in metres, and how fast it pulses.
const SHELL_MARGIN := 0.08
const SHELL_PULSES_PER_S := 2.0
## The cross's bars: long, wide and thick, in metres.
const CROSS_BAR := Vector3(0.9, 0.02, 0.12)


## A capsule of the rules' size in `colour`.
static func capsule(rules: PlayerRules, colour: Color, margin := 0.0) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = rules.capsule_radius_m + margin
	mesh.height = rules.capsule_height_m + margin * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	return mesh


## Where a capsule mesh lies, from the feet: on its side along the body's forward axis (-Z), its
## lowest point on the floor.
static func lying(rules: PlayerRules) -> Transform3D:
	var along_z := Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(along_z, Vector3(0.0, rules.capsule_radius_m, 0.0))


## Where a capsule mesh stands, from the feet.
static func standing(rules: PlayerRules) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, rules.capsule_height_m * 0.5, 0.0))


## A body (Died): the grey lying capsule with a dark cross on top, as one node, from the feet.
static func body(rules: PlayerRules) -> Node3D:
	var root := Node3D.new()
	var lying_mesh := MeshInstance3D.new()
	lying_mesh.name = "Capsule"
	lying_mesh.mesh = capsule(rules, BODY_COLOUR)
	lying_mesh.transform = lying(rules)
	root.add_child(lying_mesh)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = CROSS_COLOUR
	var top := rules.capsule_radius_m * 2.0 + CROSS_BAR.y * 0.5
	for turn: float in [PI * 0.25, -PI * 0.25]:
		var bar := BoxMesh.new()
		bar.size = CROSS_BAR
		bar.material = dark
		var instance := MeshInstance3D.new()
		instance.name = "Cross%d" % root.get_child_count()
		instance.mesh = bar
		instance.transform = Transform3D(Basis(Vector3.UP, turn), Vector3(0.0, top, 0.0))
		root.add_child(instance)
	return root


## The invulnerable shell: a translucent white capsule a little larger than the body, unshaded,
## whose alpha pulse() moves.
static func shell(rules: PlayerRules) -> CapsuleMesh:
	var mesh := capsule(rules, SHELL_COLOUR, SHELL_MARGIN)
	var material := mesh.material as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mesh


## The shell's alpha at `seconds`: between a third and the whole of SHELL_COLOUR's.
static func shell_alpha(seconds: float) -> float:
	var wave := 0.5 + 0.5 * sin(seconds * TAU * SHELL_PULSES_PER_S)
	return SHELL_COLOUR.a * lerpf(0.35, 1.0, wave)


## Sets `shell`'s alpha for `seconds` (its material is its own).
static func pulse(shell_mesh: MeshInstance3D, seconds: float) -> void:
	var capsule_mesh := shell_mesh.mesh as CapsuleMesh
	var material := capsule_mesh.material as StandardMaterial3D
	material.albedo_color.a = shell_alpha(seconds)
