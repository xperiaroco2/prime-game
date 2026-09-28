extends SceneTree

func _initialize() -> void:
	var s: GDScript = load("res://src/abs_broken.gd") as GDScript
	print("DBG broken-abstract can_inst=", s.can_instantiate(), " is_abstract=", s.is_abstract())
	quit(0)
