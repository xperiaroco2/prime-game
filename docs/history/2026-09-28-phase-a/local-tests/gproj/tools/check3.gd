extends SceneTree


func _initialize() -> void:
	var failed: int = 0
	for f: String in DirAccess.get_files_at("res://src"):
		if f.get_extension() != "gd":
			continue
		var path: String = "res://src".path_join(f)
		var s: GDScript = load(path) as GDScript
		var ok: bool = s != null and s.can_instantiate()
		printerr("RESULT ", path, " null=", s == null, " can_instantiate=", (s.can_instantiate() if s else false), " abstract=", (s.is_abstract() if s else false))
		if not ok:
			failed += 1
	printerr("failed=", failed)
	quit(1 if failed > 0 else 0)
