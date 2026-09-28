extends SceneTree
## Project checker used by `tools/run.py check` and the .gd post-edit hook.
##
## Loads every script, scene and resource under res:// (or only the res:// paths given after `--`)
## and prints one line per problem:
##   CHECK error <message>
##   CHECK warning <message>
## Exits 1 when any error was found, 0 otherwise. Run it with `-d --ignore-error-breaks` so that
## Warn-level GDScript warnings reach the logger; never with a bare `-d` (it hangs on errors).

const SKIP_DIRS: PackedStringArray = [
	"res://addons",
	"res://tools/out",
	"res://tools/check",
	"res://.godot",
]
const EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres"]


class ProblemLogger:
	extends Logger

	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	var _mutex: Mutex = Mutex.new()

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
		var text: String = rationale if not rationale.is_empty() else code
		var where: String = "%s:%d" % [file, line]
		if error_type == Logger.ERROR_TYPE_WARNING:
			var line_text: String = "%s: %s (%s)" % [where, text, code]
			_mutex.lock()
			warnings.append(line_text)
			_mutex.unlock()
		else:
			var line_text: String = "%s: %s [%s]" % [where, text, function]
			_mutex.lock()
			errors.append(line_text)
			_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var logger: ProblemLogger = ProblemLogger.new()
	OS.add_logger(logger)

	var files: PackedStringArray = []
	var requested: PackedStringArray = OS.get_cmdline_user_args()
	if requested.is_empty():
		_collect("res://", files)
	else:
		files = requested

	var broken: PackedStringArray = []
	for path: String in files:
		if not ResourceLoader.exists(path):
			broken.append("%s: file not found" % path)
			continue
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			broken.append("%s: failed to load" % path)
		elif res is Script and not (res as Script).can_instantiate():
			broken.append("%s: script does not compile" % path)

	OS.remove_logger(logger)

	for text: String in logger.warnings:
		print("CHECK warning ", text)
	for text: String in logger.errors:
		print("CHECK error ", text)
	var logged: String = "\n".join(logger.errors)
	for text: String in broken:
		# A script that failed to compile has already been reported by the engine with its line.
		if not logged.contains(text.substr(0, text.find(": "))):
			print("CHECK error ", text)
	var failed: bool = not broken.is_empty() or not logger.errors.is_empty()
	print(
		(
			"CHECK summary files=%d errors=%d warnings=%d"
			% [files.size(), logger.errors.size() + broken.size(), logger.warnings.size()]
		)
	)
	quit(1 if failed else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	if dir.trim_suffix("/") in SKIP_DIRS or FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() in EXTENSIONS:
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), out)
