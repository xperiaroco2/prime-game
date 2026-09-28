extends CharacterBody3D

@export var speed: float = 5.0
var untyped = 3

func _physics_process(delta: float) -> void:
	var v: Vector3 = velocity
	v.x = "oops"
	move_and_slide(v)
