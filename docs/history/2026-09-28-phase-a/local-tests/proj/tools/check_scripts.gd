extends SceneTree
## Proposal sketch: load every .gd under res:// (excluding addons/) and report parse failures.

func _init() -> void:
	var failures: int = 0
	var files: PackedStringArray = _collect("res://")
	for path: String in files:
		var s: Script = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if s == null or not s.can_instantiate():
			failures += 1
			printerr("CHECK FAIL: ", path)
	print("checked=%d failed=%d" % [files.size(), failures])
	quit(1 if failures > 0 else 0)

func _collect(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for d: String in DirAccess.get_directories_at(dir_path):
		if d.begins_with(".") or d == "addons" or d == "tools":
			continue
		out.append_array(_collect(dir_path.path_join(d)))
	for f: String in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out
