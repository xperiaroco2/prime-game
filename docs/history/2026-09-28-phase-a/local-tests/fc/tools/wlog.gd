extends SceneTree

class L:
	extends Logger
	var items: Array[String] = []
	var m: Mutex = Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _en: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		m.lock()
		items.append("type=%d file=%s:%d code=%s rationale=%s fn=%s" % [error_type, file, line, code.left(90), rationale.left(60), function])
		m.unlock()

func _initialize() -> void:
	var l: L = L.new()
	OS.add_logger(l)
	var s: Resource = load("res://src/warn_only.gd")
	var t: Resource = load("res://src/syntax_err.gd")
	OS.remove_logger(l)
	for i: String in l.items:
		print("LOG ", i)
	print("n=", l.items.size(), " debugger_active=", EngineDebugger.is_active())
	quit(0)
