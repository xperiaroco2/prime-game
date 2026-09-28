extends SceneTree

class ErrCounter extends Logger:
	var count: int = 0
	var lines: PackedStringArray = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		count += 1
		lines.append("%s:%d %s %s" % [file, line, code, rationale])
	func _log_message(message: String, error: bool) -> void:
		pass

var _failed: PackedStringArray = []


func _initialize() -> void:
	var logger := ErrCounter.new()
	OS.add_logger(logger)
	var files: PackedStringArray = []
	_collect("res://", files)
	for path: String in files:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			_failed.append(path)
		elif res is GDScript and not (res as GDScript).can_instantiate() and not (res as GDScript).is_abstract():
			_failed.append(path + " (cannot instantiate)")
	print("checked=%d failed=%d logged_errors=%d" % [files.size(), _failed.size(), logger.count])
	for f: String in _failed:
		print("FAIL ", f)
	quit(1 if (_failed.size() > 0 or logger.count > 0) else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "addons":
			continue
		_collect(dir.path_join(d), out)
