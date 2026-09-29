extends SceneTree
## Re-saves .tscn and .tres files the way the Godot editor does. Used by `run normalize`.
##
## Run in headless editor context:
##   godot --headless -e -s res://tools/normalize/normalize.gd -- <res:// paths>
## Only the editor's file system hands out uids, so the script waits for its first scan, then
## loads each file and saves it through ResourceSaver. A scene is instantiated in edit state and
## packed again, as the editor does. Prints one line per file, then NORMALIZE done:
##   NORMALIZE saved <path>
##   NORMALIZE error <path>: <why>

const TIMEOUT_MS: int = 180000

var _started_ms: int = 0
var _done: bool = false
var _logger: ErrorLogger = ErrorLogger.new()


## Collects engine errors, so a file that loads with errors is reported, never saved.
class ErrorLogger:
	extends Logger

	var errors: PackedStringArray = []
	var _mutex: Mutex = Mutex.new()

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d)" % [rationale if not rationale.is_empty() else code, file, line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		_mutex.lock()
		var taken: PackedStringArray = errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return taken


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if _done:
		return true
	if Time.get_ticks_msec() - _started_ms > TIMEOUT_MS:
		print("NORMALIZE error editor: the file system scan did not finish in time")
		return _finish(1)
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		print("NORMALIZE error editor: not in editor context; run with --headless -e -s")
		return _finish(1)
	var editor: Object = Engine.get_singleton("EditorInterface")
	var file_system: EditorFileSystem = editor.call("get_resource_filesystem") as EditorFileSystem
	if file_system == null or file_system.is_scanning():
		return false
	var failures: int = 0
	OS.add_logger(_logger)
	for path: String in OS.get_cmdline_user_args():
		_logger.take()
		var problem: String = _normalize(path)
		if problem.is_empty():
			print("NORMALIZE saved ", path)
		else:
			failures += 1
			print("NORMALIZE error %s: %s" % [path, problem])
	OS.remove_logger(_logger)
	return _finish(1 if failures > 0 else 0)


## Returns "" when the file was saved, else the reason it was not.
func _normalize(path: String) -> String:
	var extension: String = path.get_extension()
	var is_text_resource: bool = extension == "tscn" or extension == "tres"
	if not path.begins_with("res://") or not is_text_resource or not ResourceLoader.exists(path):
		return "not an existing res:// .tscn or .tres file"
	# CACHE_MODE_IGNORE: a copy the editor scan already cached would load without its errors.
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		return "failed to load"
	var to_save: Resource = loaded
	if extension == "tscn":
		to_save = _repack(loaded as PackedScene)
		if to_save == null:
			return "not a scene, or it failed to instantiate or pack"
	var errors: PackedStringArray = _logger.take()
	if not errors.is_empty():
		return "loaded with errors, not saved: " + "; ".join(errors)
	var save_error: Error = ResourceSaver.save(to_save, path)
	if save_error != OK:
		return "save failed: %s" % error_string(save_error)
	return ""


## The scene instantiated in edit state and packed again, or null.
func _repack(scene: PackedScene) -> PackedScene:
	if scene == null:
		return null
	var root_node: Node = scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if root_node == null:
		return null
	var packed: PackedScene = PackedScene.new()
	var pack_error: Error = packed.pack(root_node)
	root_node.free()
	return packed if pack_error == OK else null


func _finish(code: int) -> bool:
	_done = true
	print("NORMALIZE done")
	quit(code)
	return true
