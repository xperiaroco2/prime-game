class_name ItemView
extends Node3D
## One item as the client draws it (ARCHITECTURE §4.7, M4-8; the M4 ADR's D7 (a)): a greybox look
## chosen by the item kind's id, with a labelled box for a kind the client has no look for, so a
## new item kind still shows up. Placeholders until the art pass: the sizes and colours here are
## looks, never game numbers. The origin is the item's resting point, the bottom of its look.
##
## ItemViews places it and shows or hides its look (`show_look`); the root's own `visible` is left
## to whatever hides views out of sight (the downed camera's sight hiding, M4-9), which reads
## `sight_point()`. A label over an unknown kind is drawn in the world and hidden by the level like
## the item (no `no_depth_test`, the M4 ADR's §3 item 5).

## The look's sizes in metres, by kind id; any other kind gets UNKNOWN_SIZE and its id as a label.
const SIZES: Dictionary[StringName, Vector3] = {
	&"knife": Vector3(0.05, 0.04, 0.32),
	&"package": Vector3(0.45, 0.45, 0.45),
}
const UNKNOWN_SIZE := Vector3(0.3, 0.3, 0.3)
const KNIFE_COLOUR := Color(0.7, 0.72, 0.75)
const UNKNOWN_COLOUR := Color(0.85, 0.3, 0.85)
## How far above the box an unknown kind's label floats, in metres.
const LABEL_ABOVE := 0.15

var item_id := -1
var kind: StringName

var _look: Node3D


## A view of item `id` of `kind`; `colour` is a package's circle colour (white for other items).
static func make(id: int, item_kind: StringName, colour: Color) -> ItemView:
	var view := ItemView.new()
	view.name = "Item%d" % id
	view.item_id = id
	view.kind = item_kind
	view._build(colour)
	return view


## The look's size in metres for `item_kind`.
static func size_of(item_kind: StringName) -> Vector3:
	return SIZES.get(item_kind, UNKNOWN_SIZE)


## The middle of the look above the resting point `at`: where the crosshair aims at it.
static func centre_of(item_kind: StringName, at: Vector3) -> Vector3:
	return at + Vector3.UP * size_of(item_kind).y * 0.5


## Where the sight hiding looks at it (M4-9's SightHider).
func sight_point() -> Vector3:
	return centre_of(kind, global_position)


## Shows or hides the look (held by the own player, or by a player with no body drawn).
func show_look(on: bool) -> void:
	_look.visible = on


func is_look_shown() -> bool:
	return _look.visible


## The look's materials and labels, for the tests (no `no_depth_test` anywhere).
func look() -> Node3D:
	return _look


func _build(colour: Color) -> void:
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var size := size_of(kind)
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	match kind:
		&"knife":
			material.albedo_color = KNIFE_COLOUR
			material.metallic = 0.6
		&"package":
			material.albedo_color = colour
		_:
			material.albedo_color = UNKNOWN_COLOUR
	mesh.material = material
	var box := MeshInstance3D.new()
	box.name = "Box"
	box.mesh = mesh
	box.position = Vector3.UP * size.y * 0.5
	_look.add_child(box)
	if not SIZES.has(kind):
		var label := Label3D.new()
		label.name = "Label"
		label.text = String(kind)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3.UP * (size.y + LABEL_ABOVE)
		_look.add_child(label)
