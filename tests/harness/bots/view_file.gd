class_name ViewFile
extends RefCounted
## A bot's view file (ARCHITECTURE §4.6): what one bot decoded, its peer id and its failures,
## written as FileAccess.store_var of plain data (a local file, lossless, not the wire) to
## tools/out/bots/<scenario>/bot-<i>.bin. Over ENet the host reads every bot's file back and
## compares it with view_of; in one process the files are a record of the run. Over WebRTC it also
## holds the bot's OrderLog lists (`order`), which the host checks against its own. A bot that left
## and joined again (ScenarioBot.lives) also holds each earlier connection's view (`earlier`).


## The folder of a scenario's files under the project: tools/out/bots/<scenario>.
static func dir_of(scenario_name: String) -> String:
	return ProjectSettings.globalize_path("res://tools/out/bots").path_join(scenario_name)


## Writes bot `bot`'s file in `dir`; false after logging why it could not. `earlier`: its earlier
## connections, oldest first, each {peer, view: DecodedView, order}.
static func write(
	dir: String,
	bot: int,
	peer: int,
	view: DecodedView,
	failures: PackedStringArray,
	order: Dictionary = {},
	earlier: Array[Dictionary] = [],
) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("bots: cannot create %s" % dir)
		return false
	var data := _data_of(peer, view, order)
	data["bot"] = bot
	data["failures"] = failures
	var lives: Array = []
	for life: Dictionary in earlier:
		var life_order: Dictionary = life.get("order", {})
		lives.append(_data_of(life["peer"] as int, life["view"] as DecodedView, life_order))
	data["earlier"] = lives
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


## {bot, peer, view: DecodedView, failures, order, earlier} from bot `bot`'s file in `dir`
## (`earlier`: each earlier connection's {peer, view, order}, oldest first); empty when there is
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
	var earlier: Array[Dictionary] = []
	for life: Dictionary in fields.get("earlier", []) as Array:
		earlier.append({"peer": life["peer"], "view": _view_of(life), "order": life["order"]})
	return {
		"bot": fields["bot"],
		"peer": fields["peer"],
		"view": _view_of(fields),
		"failures": fields["failures"],
		"order": fields.get("order", {}),
		"earlier": earlier,
	}


static func _data_of(peer: int, view: DecodedView, order: Dictionary) -> Dictionary:
	var events: Array = []
	for event: WireMessage in view.events:
		events.append([event.name, event.fields])
	return {
		"peer": peer,
		"events": events,
		"snapshots": view.snapshots,
		"repeated_snapshots": view.repeated_snapshots,
		"voice": view.voice,
		"voice_seqs": view.voice_seqs,
		"order": order,
	}


static func _view_of(fields: Dictionary) -> DecodedView:
	var view := DecodedView.new()
	view.peer = fields["peer"] as int
	for pair: Array in fields["events"] as Array:
		view.events.append(WireMessage.new(pair[0] as StringName, pair[1] as Dictionary))
	view.snapshots.assign(fields["snapshots"] as Dictionary)
	view.repeated_snapshots.assign(fields["repeated_snapshots"] as Array)
	view.voice.assign(fields["voice"] as Dictionary)
	view.voice_seqs.assign(fields["voice_seqs"] as Dictionary)
	return view
