extends RefCounted
## What the dev previews build alike (#1254): a coloured box for their floor and walls, and a
## station folded into their fake ClientModel. Dev only: nothing here reaches the game.


## A box of `size` and `colour` centred at `at` under `parent`; with `solid` also a StaticBody3D
## of its shape, for a preview a thrown or dropped item lands on.
static func box(parent: Node, at: Vector3, size: Vector3, colour: Color, solid := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = at
	parent.add_child(view)
	if not solid:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


## Folds a white station `id` of `kind` at `at` into `model`, as the host's StationPlaced reads.
static func place(model: ClientModel, id: int, kind: StringName, at: Vector3) -> void:
	model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)
