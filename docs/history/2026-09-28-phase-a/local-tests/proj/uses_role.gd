extends Node

func _ready() -> void:
	var r: NewRole = NewRole.new()
	print(r.power())
