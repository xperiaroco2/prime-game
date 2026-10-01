class_name ReplayFiles
extends RefCounted
## The command logs a debug-build host keeps on its own disk (ARCHITECTURE §4.5 "The command log
## and replays", E13): HostSession writes the session's log when the session ends, never after
## each match, because the log holds the session seed from which every later match's seed is
## derived; only the newest KEEP files are kept. read() gives a CommandLog back for Match.replay,
## with the game mode loaded from its `mode_path` by the caller. A log never leaves the host (§5).
##
## The file is FileAccess.store_var of CommandLog.to_dict(): a local file, lossless, read back
## without objects; never the wire.

const DIR := "user://replays"
## The newest logs kept.
const KEEP := 10
const EXTENSION := "cmdlog"


## Writes `recorded` to a new file in `dir` and keeps only the newest `keep` there; the file's
## path, or "" after logging why it could not be written.
static func write(recorded: CommandLog, dir: String = DIR, keep: int = KEEP) -> String:
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		push_error("replays: cannot create %s: %s" % [dir, error_string(made)])
		return ""
	var path := dir.path_join(_file_name())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(
			"replays: cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())]
		)
		return ""
	file.store_var(recorded.to_dict())
	file.close()
	var kept := list(dir)
	for i in maxi(0, kept.size() - keep):
		DirAccess.remove_absolute(kept[i])
	return path


## The log in the file at `path`, or null when it cannot be read as one.
static func read(path: String) -> CommandLog:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Variant = file.get_var(false)
	file.close()
	if not data is Dictionary:
		return null
	return CommandLog.from_dict(data as Dictionary)


## The logs in `dir`, oldest first (their names sort by the time they were written).
static func list(dir: String = DIR) -> PackedStringArray:
	var found := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.get_extension() == EXTENSION:
			found.append(dir.path_join(file_name))
	found.sort()
	return found


## session-<UTC date>-<UTC time>-<microseconds since start>.cmdlog: sorts by when it was written,
## also across a daylight saving change.
static func _file_name() -> String:
	var now := Time.get_datetime_dict_from_system(true)
	return (
		"session-%04d%02d%02d-%02d%02d%02d-%013d.%s"
		% [
			now["year"],
			now["month"],
			now["day"],
			now["hour"],
			now["minute"],
			now["second"],
			Time.get_ticks_usec(),
			EXTENSION
		]
	)
