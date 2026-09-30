class_name RemotePlayerBody
extends AnimatableBody3D
## Another living player as the local client sees it: a kinematic capsule on the living layer.
## Only its owner's data moves it (interpolation comes in 4b; a dev room places it by hand). The
## local player never collides with it like a wall and never moves it: it pushes into it, and is
## pushed out of it when it comes into the local player (§7.1 "Pushing apart"). The origin is at
## the feet, like the local player's.

@export var tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
@export var color: Color = Color(0.25, 0.45, 0.85)

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	collision_layer = PhysicsLayers.LIVING
	collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.capsule_radius
	capsule.height = tuning.capsule_height
	_shape.shape = capsule
	var mesh := CapsuleMesh.new()
	mesh.radius = tuning.capsule_radius
	mesh.height = tuning.capsule_height
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	_mesh.mesh = mesh
	var center := Vector3(0.0, tuning.capsule_height * 0.5, 0.0)
	_shape.position = center
	_mesh.position = center
