extends SceneTree

var _failed: PackedStringArray = []


func _initialize() -> void:
	var files: PackedStringArray = []
	_collect("res://src", files)
	for path: String in files:
		printerr("loading ", path)
		var res: Resource = ResourceLoader.load(path)
		if res == null:
			_failed.append(path)
	print("checked=%d failed=%d" % [files.size(), _failed.size()])
	for f: String in _failed:
		print("FAIL ", f)
	quit(1 if _failed.size() > 0 else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir.path_join(f))
