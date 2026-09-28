extends SceneTree


class ErrCounter:
	extends Logger
	var count: int = 0
	var mutex: Mutex = Mutex.new()

	func _log_error(
		_function: String, file: String, line: int, _code: String, rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtrace: Array[ScriptBacktrace]
	) -> void:
		mutex.lock()
		count += 1
		mutex.unlock()


func _initialize() -> void:
	var logger: ErrCounter = ErrCounter.new()
	OS.add_logger(logger)
	for f: String in DirAccess.get_files_at("res://src"):
		if f.get_extension() != "gd":
			continue
		var _s: Resource = load("res://src".path_join(f))
	OS.remove_logger(logger)
	printerr("logged_errors=", logger.count)
	quit(1 if logger.count > 0 else 0)
