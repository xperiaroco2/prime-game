class_name ViewFile
extends RefCounted
## A bot's view file (ARCHITECTURE §4.6): what one bot decoded, its peer id and its failures,
## written as FileAccess.store_var of plain data (a local file, lossless, not the wire) to
## tools/out/bots/<scenario>/bot-<i>.bin. Over ENet the host reads every bot's file back and
## compares it with view_of; in one process the files are a record of the run.


## The folder of a scenario's files under the project: tools/out/bots/<scenario>.
static func dir_of(scenario_name: String) -> String:
	return ProjectSettings.globalize_path("res://tools/out/bots").path_join(scenario_name)


## Writes bot `bot`'s file in `dir`; false after logging why it could not.
static func write(
	dir: String, bot: int, peer: int, view: DecodedView, failures: PackedStringArray
) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("bots: cannot create %s" % dir)
		return false
	var events: Array = []
	for event: WireMessage in view.events:
		events.append([event.name, event.fields])
	var data := {
		"bot": bot,
		"peer": peer,
		"events": events,
		"snapshots": view.snapshots,
		"voice": view.voice,
		"failures": failures,
	}
	var path := path_of(dir, bot)
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	if file == null:
		push_error("bots: cannot write %s" % path)
		return false
	file.store_var(data)
	file.close()
	# Renamed when complete, so a reader never sees half a file.
	return DirAccess.rename_absolute(path + ".part", path) == OK


static func path_of(dir: String, bot: int) -> String:
	return dir.path_join("bot-%d.bin" % bot)


## {bot, peer, view: DecodedView, failures} from bot `bot`'s file in `dir`; empty when there is
## none (yet) or it cannot be read.
static func read(dir: String, bot: int) -> Dictionary:
	var path := path_of(dir, bot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var(false)
	file.close()
	if not data is Dictionary:
		return {}
	var fields: Dictionary = data
	var view := DecodedView.new()
	view.peer = fields["peer"] as int
	for pair: Array in fields["events"] as Array:
		view.events.append(WireMessage.new(pair[0] as StringName, pair[1] as Dictionary))
	view.snapshots.assign(fields["snapshots"] as Dictionary)
	view.voice.assign(fields["voice"] as Dictionary)
	return {
		"bot": fields["bot"],
		"peer": fields["peer"],
		"view": view,
		"failures": fields["failures"],
	}
