extends Node

signal hit(amount: int)

func _ready() -> void:
	yield(get_tree().create_timer(1.0), "timeout")
