class_name PinballTableView
extends Node3D
## The pinball's table as every window near the machine draws it (#1400; ARCHITECTURE §4.7.63):
## the host's table scene (§7.1.22's scene contract, `levels/pinball/pinball_table.tscn`) read
## once and drawn as plain meshes, one per collision shape, with no physics body anywhere in the
## client's tree (a collider here would stop the own player's rays and body); the two flippers
## turned toward the held state the host told everyone (PinballState's `left` and `right`) at the
## host's swing and speed; the ball where PinballBallTrack puts it. PinballViews places it on the
## level's table marker and feeds it; it reads nothing itself.
##
## The look is a placeholder in the Toy style (flat colours; provisional, not a decision): the
## engineer's art replaces the greybox and keeps the contract.

## The table scene (a levels/ path, never server/'s PinballTable.SCENE: the client names no
## server/ path, E18).
const SCENE := "res://levels/pinball/pinball_table.tscn"
## The flippers' swing and turning speed and the ball's radius, as the host's PinballTableSpec
## ships them (levels/pinball/pinball_table_spec.tres; a test fails when they part): the client
## draws, the host decides, so these are the look of the host's numbers.
const SWING_DEG := 50.0
const SPEED_DEG_S := 1500.0
const BALL_RADIUS_M := 0.03
## The flippers' nodes in the scene and the way each turns about its own Y (the host's turn_sign).
const FLIPPERS: Dictionary[StringName, float] = {&"FlipperLeft": 1.0, &"FlipperRight": -1.0}
## The playfield's thickness under the table's floor (y 0), metres.
const FIELD_M := 0.01
## The placeholder colours (Toy style, provisional, not a decision).
const FIELD_COLOUR := Color(0.11, 0.2, 0.42)
const RAIL_COLOUR := Color(0.93, 0.9, 0.82)
const TARGET_COLOUR := Color(1.0, 0.55, 0.15)
const FLIPPER_COLOUR := Color(0.95, 0.25, 0.3)
const BALL_COLOUR := Color(0.92, 0.93, 0.95)

## The held state as the host told it; step() turns the flippers toward it.
var left := false
var right := false
var ball := MeshInstance3D.new()

## The flippers' pivots (FLIPPERS' order), their rest transforms and their angles (radians).
var _pivots: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _angles: Array[float] = []
var _built := false


func _init() -> void:
	name = "PinballTable"
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS_M
	sphere.height = BALL_RADIUS_M * 2.0
	sphere.material = _material(BALL_COLOUR)
	ball.mesh = sphere
	ball.visible = false
	add_child(ball)


## Whether the table is drawn (the scene was read and held a flipper pair).
func built() -> bool:
	return _built


## Reads the table scene and draws it, once; whether it is drawn.
func build() -> bool:
	if _built:
		return true
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("pinball: no table scene at %s" % SCENE)
		return false
	var source := packed.instantiate() as Node3D
	var field := AABB()
	var first := true
	for shape: CollisionShape3D in _shapes(source):
		var owner_body := shape.get_parent() as Node3D
		var sign_of: float = FLIPPERS.get(owner_body.name, 0.0)
		var mesh := _mesh_of(shape, owner_body, sign_of != 0.0)
		if mesh == null:
			continue
		var at := _in_scene(shape, source)
		var box := at * mesh.mesh.get_aabb()
		field = box if first else field.merge(box)
		first = false
		if sign_of != 0.0:
			_add_flipper(owner_body, shape, mesh, source)
		else:
			mesh.transform = at
			add_child(mesh)
	source.free()
	if _pivots.size() != FLIPPERS.size():
		push_error("pinball: the table scene has not both flippers")
		return false
	_add_field(field)
	_built = true
	return true


## Turns the flippers toward the held state over `delta` seconds, at the host's speed.
func step(delta: float) -> void:
	var held: Array[bool] = [left, right]
	for i in _pivots.size():
		var goal := deg_to_rad(SWING_DEG) if held[i] else 0.0
		_angles[i] = move_toward(_angles[i], goal, deg_to_rad(SPEED_DEG_S) * delta)
		var turn := FLIPPERS.values()[i] as float * _angles[i]
		_pivots[i].transform = _rest[i] * Transform3D(Basis(Vector3.UP, turn))


## A flipper's angle now, radians (0 at rest); `index` 0 is the left.
func flipper_angle(index: int) -> float:
	return _angles[index]


## Draws the ball at `place` (table-local), or hides it for null.
func show_ball(place: Variant) -> void:
	ball.visible = place != null
	if place != null:
		ball.position = place as Vector3


## Rests the flippers and hides the ball (the session or the match ended).
func rest() -> void:
	left = false
	right = false
	for i in _pivots.size():
		_angles[i] = 0.0
		_pivots[i].transform = _rest[i]
	show_ball(null)


## One pivot per flipper body, at the body's place in the scene (nested or not), with a mesh per
## shape under it: a body with two shapes turns both.
func _add_flipper(
	body: Node3D, shape: CollisionShape3D, mesh: MeshInstance3D, source: Node3D
) -> void:
	# FLIPPERS' order, whatever the scene's.
	var index := FLIPPERS.keys().find(body.name)
	while _pivots.size() <= index:
		_pivots.append(null)
		_rest.append(Transform3D.IDENTITY)
		_angles.append(0.0)
	var pivot := _pivots[index]
	if pivot == null:
		pivot = Node3D.new()
		pivot.name = body.name
		_rest[index] = _in_scene(body, source)
		pivot.transform = _rest[index]
		add_child(pivot)
		_pivots[index] = pivot
	mesh.transform = _in_scene(shape, body)
	mesh.name = "Mesh"
	pivot.add_child(mesh)


## The playfield under the shapes' footprint, its top at the table's floor.
func _add_field(field: AABB) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Playfield"
	var box := BoxMesh.new()
	box.size = Vector3(field.size.x, FIELD_M, field.size.z)
	box.material = _material(FIELD_COLOUR)
	mesh.mesh = box
	var centre := field.get_center()
	mesh.position = Vector3(centre.x, -FIELD_M / 2.0, centre.z)
	add_child(mesh)


## A mesh of `shape`'s size (a box or a cylinder), coloured by what its body is; null for another
## shape.
func _mesh_of(shape: CollisionShape3D, body: Node3D, flipper: bool) -> MeshInstance3D:
	var made: PrimitiveMesh
	var box := shape.shape as BoxShape3D
	var cylinder := shape.shape as CylinderShape3D
	if box != null:
		var cube := BoxMesh.new()
		cube.size = box.size
		made = cube
	elif cylinder != null:
		var tube := CylinderMesh.new()
		tube.top_radius = cylinder.radius
		tube.bottom_radius = cylinder.radius
		tube.height = cylinder.height
		made = tube
	else:
		return null
	var colour := RAIL_COLOUR
	if flipper:
		colour = FLIPPER_COLOUR
	elif body.has_meta(&"target_id"):
		colour = TARGET_COLOUR
	made.material = _material(colour)
	var mesh := MeshInstance3D.new()
	mesh.name = body.name
	mesh.mesh = made
	return mesh


## Every CollisionShape3D under `root`, in tree order.
static func _shapes(root: Node) -> Array[CollisionShape3D]:
	var found: Array[CollisionShape3D] = []
	for child: Node in root.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.get_parent() is Node3D:
			found.append(shape)
		found.append_array(_shapes(child))
	return found


## `node`'s transform in `root`'s frame (the scene is off the tree: no global_transform).
static func _in_scene(node: Node3D, root: Node3D) -> Transform3D:
	var at := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != root:
		var spatial := walk as Node3D
		if spatial != null:
			at = spatial.transform * at
		walk = walk.get_parent()
	return at


static func _material(colour: Color) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.albedo_color = colour
	made.roughness = 0.6
	return made
