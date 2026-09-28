extends CharacterBody3D

@export var speed: float = 5.0

func _physics_process(delta: float) -> void:
	velocity.x = speed * delta
	move_and_slide()
