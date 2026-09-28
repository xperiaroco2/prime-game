extends SceneTree
func _init() -> void:
	for i in 6:
		print(ResourceUID.id_to_text(ResourceUID.create_id()))
	quit()
