class_name RemotePlayerBody
extends StaticBody3D
## Another player as the local client sees it: a capsule on the living layer while that player is
## living, else on the downed layer, which no push searches (a downed player pushes nobody and
## nobody pushes it, §7.1; `set_living`). A downed player's mesh lies on its side (`set_downed`, the
## M4 ADR's D8; its collision capsule stays standing, and the crosshair's search for a downed
## player to raise finds it on the downed layer); an invulnerable one wears a pulsing white shell
## (`set_invulnerable`, the avatar's flag). It has the size of the client's own copy of the
## mode's PlayerRules (`rules`), with a head that turns and nods. Only its owner's data moves it:
## AvatarViews places it each physics frame at SnapshotBuffer's interpolated pose (ARCHITECTURE
## §4.7), the yaw on the body and the pitch on the head, both already guarded against a degenerate
## facing. The local player never collides with it like a wall and never moves it: it pushes into
## it, and is pushed out of it when it comes into the local player (§7.1 "Pushing apart"). The
## origin is at the feet.
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
@export var color: Color = LifeLooks.PLAYER_COLOUR
## The player it shows; 0 when none (the controller's tests).
var peer := 0

var _head: Node3D
var _shell: MeshInstance3D
var _downed := false
var _watched := false

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	collision_layer = PhysicsLayers.LIVING
	collision_mask = 0
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	_shell.visible = false
	add_child(_shell)
	set_process(false)
	if rules != null:
		_apply_rules()


func set_rules(value: PlayerRules) -> void:
	rules = value
	if rules != null and is_node_ready():
		_apply_rules()


## Puts the body on the living layer (`living`) or the downed layer, where no push finds it.
func set_living(living: bool) -> void:
	collision_layer = PhysicsLayers.LIVING if living else PhysicsLayers.DOWNED


## Lays the mesh down (the downed pose) or stands it up, and hides the head while it lies.
func set_downed(downed: bool) -> void:
	if downed == _downed:
		return
	_downed = downed
	_show_looks()


## Whether the mesh lies (the downed pose).
func is_downed() -> bool:
	return _downed


## Shows the invulnerable shell (the avatar's flag): it pulses while shown.
func set_invulnerable(invulnerable: bool) -> void:
	_shell.visible = invulnerable and not _watched
	set_process(invulnerable)


func is_invulnerable() -> bool:
	return _shell.visible


## Hides the meshes while the spectate camera looks out of this player's eyes, which would sit
## inside the capsule behind the visor; the body stays where it is (a downed target's is watched
## from above and stays drawn). The node's own `visible` belongs to SightHider.
func set_watched(watched: bool) -> void:
	_watched = watched
	_show_looks()
	_shell.visible = _shell.visible and not watched


## The point SightHider casts its ray at: the capsule's middle, or the lying capsule's.
func sight_point() -> Vector3:
	var up := rules.capsule_radius_m if _downed else rules.capsule_height_m * 0.5
	return global_position + Vector3.UP * up


## Whether the body is on the living layer.
func is_living() -> bool:
	return collision_layer == PhysicsLayers.LIVING


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


func _process(_delta: float) -> void:
	LifeLooks.pulse(_shell, Time.get_ticks_msec() / 1000.0)


## Stands or lays the mesh and the shell, and shows the head standing only, unless watched.
func _show_looks() -> void:
	if rules == null:
		return
	var pose := LifeLooks.lying(rules) if _downed else LifeLooks.standing(rules)
	_mesh.transform = pose
	_shell.transform = pose
	_mesh.visible = not _watched
	_head.visible = not _downed and not _watched


func _apply_rules() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m
	_shape.shape = capsule
	_mesh.mesh = LifeLooks.capsule(rules, color)
	_shell.mesh = LifeLooks.shell(rules)
	_shape.position = Vector3(0.0, rules.capsule_height_m * 0.5, 0.0)
	_show_looks()
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
