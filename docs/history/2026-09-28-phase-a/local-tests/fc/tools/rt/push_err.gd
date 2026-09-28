extends SceneTree

func _initialize() -> void:
	push_error("boom from push_error")
	quit(0)
