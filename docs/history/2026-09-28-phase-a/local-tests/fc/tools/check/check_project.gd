extends SceneTree

const SKIP: PackedStringArray = ["res://addons", "res://tools/out", "res://tools/check", "res://.godot"]


class ErrorCounter:
	extends Logger
	var count: int = 0
	var _mutex: Mutex = Mutex.new()

	func _log_error(
		_function: String, _file: String, _line: int, _code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		count += 1
		_mutex.unlock()


func _initialize() -> void:
	var counter: ErrorCounter = ErrorCounter.new()
	OS.add_logger(counter)
	var files: PackedStringArray = []
	_collect("res://", files)
	var bad: PackedStringArray = []
	for path: String in files:
		var res: Resource = load(path)
		if res == null:
			bad.append(path)
		elif res is GDScript:
			var s: GDScript = res as GDScript
			if not s.can_instantiate() and not s.is_abstract():
				bad.append(path)
	OS.remove_logger(counter)
	for p: String in bad:
		printerr("CHECK FAIL ", p)
	print("check: files=%d failed=%d logged_errors=%d" % [files.size(), bad.size(), counter.count])
	quit(1 if (bad.size() > 0 or counter.count > 0) else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	if dir.trim_suffix("/") in SKIP:
		return
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir.path_join(d), out)
