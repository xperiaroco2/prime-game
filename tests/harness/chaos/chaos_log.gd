class_name ChaosLog
extends Logger
## The warning and error lines logged while a chaos run is attached (OS.add_logger may call it from
## any thread): the host's one line per malformed disconnect (§4.5) is a warning, and any error line
## is a failure of the run (`run` fails on one too).

const DISCONNECTED := "host: disconnected peer %d sent"

var _warnings := PackedStringArray()
var _errors := PackedStringArray()
var _lock := Mutex.new()


func start() -> void:
	OS.add_logger(self)


func stop() -> void:
	OS.remove_logger(self)


func warnings() -> PackedStringArray:
	_lock.lock()
	var copy := _warnings.duplicate()
	_lock.unlock()
	return copy


func errors() -> PackedStringArray:
	_lock.lock()
	var copy := _errors.duplicate()
	_lock.unlock()
	return copy


## The warnings that are the host's malformed-disconnect line for `peer`.
func disconnect_lines(peer: int) -> PackedStringArray:
	var found := PackedStringArray()
	var head := DISCONNECTED % peer
	for line: String in warnings():
		if line.contains(head + " "):
			found.append(line)
	return found


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
	var text := "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
	_lock.lock()
	if error_type == ERROR_TYPE_WARNING:
		_warnings.append(text)
	else:
		_errors.append(text)
	_lock.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
