class_name MugLooks
extends RefCounted
## The look of the bar's mug of beer, full and empty (#1678; the base mode's kind ids `mug` and
## `mug_empty`, #1408): the art's mug when its package is here (#1697, art#392's contract: GLB, its
## Beer hidden for an empty mug, held by its Grip), else a placeholder built from primitives, a
## plain cylinder in a neutral colour with a handle on its +X side, no label, held round its
## middle; both kinds alike, the HUD's name tag tells them apart. The origin is the resting point,
## the bottom of the body. The placeholder's sizes and colour are looks, "not a decision": the
## body is a half-litre beer mug's.

const KINDS: Array[StringName] = [&"mug", &"mug_empty"]
## The body: its width (the diameter) and height in metres; the handle sticks out past it.
const SIZE := Vector3(0.085, 0.14, 0.085)
const COLOUR := Color(0.78, 0.77, 0.74)
## The handle, a ring standing on the body's +X side with its middle on the body's wall, half sunk
## into it: the tube's inner and outer radii in metres.
const HANDLE_INNER := 0.024
const HANDLE_OUTER := 0.036
## Where a held mug's origin sits from the body's hand point (ItemViews): half its height lower,
## so the hand closes round its middle instead of carrying it on the fist.
const IN_HAND := Vector3(0.0, -SIZE.y * 0.5, 0.0)
## The art's mug (art#392's contract, #1697): one GLB for both kinds, its origin the base's middle,
## the handle on +X; `Mug` always shown, `Beer` hidden for `mug_empty`, `Grip` the handle's middle.
## Until its package lands the placeholder stands in.
const GLB := "res://assets/props/mug/mug.glb"
const BODY := "Mug"
const BEER := "Beer"
const GRIP := "Grip"

static var _model: PackedScene


static func has(kind: StringName) -> bool:
	return KINDS.has(kind)


static func size_of(_kind: StringName) -> Vector3:
	return SIZE


## The look of `kind`: the art's mug (`model`, by default GLB when it is there, #1697) with its
## Beer shown for a full mug and hidden for an empty one; else the placeholder.
static func build(kind: StringName, model: PackedScene = null) -> Node3D:
	var scene := model if model != null else _art()
	if scene != null:
		var node := scene.instantiate()
		var made := node as Node3D
		if made != null and made.find_child(BODY, true, false) != null:
			made.name = "Mug"
			var beer := made.find_child(BEER, true, false) as Node3D
			if beer != null:
				beer.visible = kind != &"mug_empty"
			# A mug lights nothing and sees nothing: an exported light would glow through walls
			# with no shadow, and the item's layers never cover it.
			# One nested in another goes with it: freed twice it would error.
			for type: String in ["Light3D", "Camera3D"]:
				for extra: Node in made.find_children("*", type, true, false):
					if is_instance_valid(extra):
						extra.free()
			return made
		if node != null:
			node.free()
	return placeholder()


## The grip of the look `look` (one ItemView's, or build()'s node), in `look`'s frame: the point
## that lands on a hand (the art's `Grip`, its +Y up the handle, its -Z from the handle to the
## mug's axis), else the placeholder's middle (#1678's hold round the middle).
static func grip_of(look: Node3D) -> Transform3D:
	var grip := look.find_child(GRIP, true, false) as Node3D
	if grip == null:
		return Transform3D(Basis.IDENTITY, -IN_HAND)
	var out := Transform3D.IDENTITY
	var at: Node = grip
	while at != null and at != look:
		if at is Node3D:
			out = (at as Node3D).transform * out
		at = at.get_parent()
	return out


## The art's mug scene, loaded once; null without it (until its package lands; CI's LFS stand-in
## has no `Mug` node and is dropped by build()).
static func _art() -> PackedScene:
	if _model == null and ResourceLoader.exists(GLB):
		_model = load(GLB) as PackedScene
	return _model


## The placeholder: "Body" and "Handle" under one node, one material.
static func placeholder() -> Node3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR
	material.roughness = 0.4
	var mug := Node3D.new()
	mug.name = "Mug"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = SIZE.x * 0.5
	body_mesh.bottom_radius = SIZE.x * 0.5
	body_mesh.height = SIZE.y
	body_mesh.material = material
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	body.position = Vector3.UP * SIZE.y * 0.5
	mug.add_child(body)
	var handle_mesh := TorusMesh.new()
	handle_mesh.inner_radius = HANDLE_INNER
	handle_mesh.outer_radius = HANDLE_OUTER
	handle_mesh.material = material
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	handle.mesh = handle_mesh
	# A TorusMesh lies round Y; turned round X it stands in the body's XY plane.
	handle.transform = Transform3D(
		Basis(Vector3.RIGHT, PI * 0.5), Vector3(SIZE.x * 0.5, SIZE.y * 0.5, 0.0)
	)
	mug.add_child(handle)
	return mug
