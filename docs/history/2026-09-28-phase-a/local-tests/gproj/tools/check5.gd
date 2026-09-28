extends SceneTree


func _initialize() -> void:
	for f: String in DirAccess.get_files_at("res://src"):
		if f.get_extension() != "gd":
			continue
		var p: String = "res://src".path_join(f)
		printerr("load-ignore ", p)
		var s: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		printerr("  null=", s == null)
	printerr("done")
	quit(0)
