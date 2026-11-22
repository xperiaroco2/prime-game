class_name MugLooks
extends RefCounted
## The look of the bar's mug of beer, full and empty (#1678; the base mode's kind ids `mug` and
## `mug_empty`, #1408): a placeholder built from primitives until the art track's model, a plain
## cylinder in a neutral colour with a handle on its +X side, no label. Both kinds look alike; the
## HUD's name tag tells them apart. The origin is the resting point, the bottom of the body. The
## sizes and colour are looks, "not a decision": the body is a half-litre beer mug's.

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


static func has(kind: StringName) -> bool:
	return KINDS.has(kind)


static func size_of(_kind: StringName) -> Vector3:
	return SIZE


## The placeholder: "Body" and "Handle" under one node, one material.
static func build(_kind: StringName) -> Node3D:
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
