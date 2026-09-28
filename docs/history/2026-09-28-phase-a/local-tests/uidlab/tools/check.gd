extends SceneTree
func _init() -> void:
	for p: String in ["res://levels/dup_ref.tscn", "res://levels/stale.tscn", "res://levels/wrong.tscn", "res://levels/no_uid_scene.tscn"]:
		var ps: PackedScene = load(p)
		var n: Node = ps.instantiate()
		var r: Resource = n.get_meta("item")
		print("SCENE ", p, " -> item ", r.resource_path, " name=", r.get("display_name"))
		n.free()
	for p: String in ["res://content/a.tres", "res://content/b.tres", "res://content/no_uid.tres", "uid://cljv4llohlgi1"]:
		var r2: Resource = load(p)
		print("RES ", p, " -> ", r2.resource_path, " name=", r2.get("display_name"), " uid=", ResourceUID.id_to_text(ResourceLoader.get_resource_uid(r2.resource_path)))
	quit()
