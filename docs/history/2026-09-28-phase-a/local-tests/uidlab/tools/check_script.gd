extends SceneTree
func _init() -> void:
	# c.tres's ext_resource has a stale script uid now; use the regenerated one via a fresh resource text
	var r: Resource = load("res://content/d.tres")
	print("d.tres script -> ", (r.get_script() as Script).resource_path)
	print("uid://b1amlyk8cof6q -> ", ResourceUID.uid_to_path("uid://b1amlyk8cof6q"))
	quit()
