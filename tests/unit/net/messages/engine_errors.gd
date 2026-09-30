extends Logger
## Collects every engine error line (ERROR:, SCRIPT ERROR:, a push_error) logged while it is
## attached, so a suite can assert that a decoder printed none. Attach with start(), detach with
## stop(); OS.add_logger may call it from any thread.

var _lines := PackedStringArray()
var _lock := Mutex.new()


func start() -> void:
	OS.add_logger(self)


func stop() -> void:
	OS.remove_logger(self)


func count() -> int:
	_lock.lock()
	var found := _lines.size()
	_lock.unlock()
	return found


## A copy of the lines logged so far, taken under the lock.
func snapshot() -> PackedStringArray:
	_lock.lock()
	var copy := _lines.duplicate()
	_lock.unlock()
	return copy


func clear() -> void:
	_lock.lock()
	_lines.clear()
	_lock.unlock()


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_lock.lock()
	_lines.append("%s:%d %s: %s %s" % [file, line, function, code, rationale])
	_lock.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
