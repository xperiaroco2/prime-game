class_name RemotePlayerBody
extends StaticBody3D
## Another living player as the local client sees it: a capsule on the living layer, of
## the size of the client's own copy of the mode's PlayerRules (`rules`), with a head that turns
## and nods. Only its owner's data moves it: AvatarViews places it each physics frame at
## SnapshotBuffer's interpolated pose (ARCHITECTURE §4.7), the yaw on the body and the pitch on
## the head, both already guarded against a degenerate facing. The local player never collides
## with it like a wall and never moves it: it pushes into it, and is pushed out of it when it comes
## into the local player (§7.1 "Pushing apart"). The origin is at the feet.
##
## It is teleported, and the push search of the same physics frame must see where (§4.7): so it is
## a static body, placed with force_update_transform(). Checked on 4.7.2 with Jolt: a transform
## set in `_physics_process` reaches the physics server only after the whole pass unless the
## node forces it, and a kinematic body (an AnimatableBody3D, `sync_to_physics` on or off, or a
## CharacterBody3D) shows a teleport to shape queries only after the physics step, even when set
## on the server directly; a static body shows it at once. Nothing collides with it as a wall: the
## local player's mask is the world, and its push search reads the living layer.

## The visor's size and how far it sits in front of the eyes, in metres (greybox looks).
const VISOR_SIZE := Vector3(0.3, 0.1, 0.12)
const VISOR_AHEAD := 0.25

## The client's own copy of the mode's PlayerRules: the capsule and the eyes. Applied at once
## when set in the tree.
@export var rules: PlayerRules:
	set = set_rules
@export var color: Color = Color(0.25, 0.45, 0.85)

var _head: Node3D

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	collision_layer = PhysicsLayers.LIVING
	collision_mask = 0
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	if rules != null:
		_apply_rules()


func set_rules(value: PlayerRules) -> void:
	rules = value
	if rules != null and is_node_ready():
		_apply_rules()


## Places the body at `pose`: its position, the yaw on the body and the pitch on the head.
func set_pose(pose: SnapshotBuffer.Pose) -> void:
	global_position = pose.position
	rotation = Vector3(0.0, pose.yaw, 0.0)
	_head.rotation = Vector3(pose.pitch, 0.0, 0.0)
	# Now, not after the pass: the local player's push search (priority 0) reads it this frame.
	force_update_transform()


## The head: it holds the pitch (tests read it).
func head() -> Node3D:
	return _head


func _apply_rules() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m
	_shape.shape = capsule
	var mesh := CapsuleMesh.new()
	mesh.radius = rules.capsule_radius_m
	mesh.height = rules.capsule_height_m
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	_mesh.mesh = mesh
	var center := Vector3(0.0, rules.capsule_height_m * 0.5, 0.0)
	_shape.position = center
	_mesh.position = center
	_head.position = Vector3(0.0, rules.eye_height_m, 0.0)
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = VISOR_SIZE
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	visor_mesh.material = dark
	var old := _head.get_node_or_null(^"Visor")
	if old != null:
		old.free()
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 0.0, -VISOR_AHEAD)
	_head.add_child(visor)
