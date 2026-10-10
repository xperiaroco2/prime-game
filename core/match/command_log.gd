class_name CommandLog
extends RefCounted
## Everything core/ is given, so a match can be replayed (ARCHITECTURE §3.3): the session seed, the
## game mode's path and content hash, the host's content hash that joiners must match, the levels'
## layouts, the start tick, every command in order with its tick (server/'s own included), the last
## tick run, and every WorldQuery answer.
## A replay refuses to run when the mode's hash differs. It never leaves the host (§5).

var session_seed := 0
var mode_path := ""
var mode_hash := 0
## The host's content hash (§4.3, E1), which JoinRules compares with each Hello's `content`.
var content_hash := 0
## Level path -> layout.
var layouts: Dictionary[String, LevelLayout] = {}
var start_tick := -1
var ticked_through := -1
var commands: Array[MatchCommand] = []
## Booleans and Vector3s, in the order they were answered.
var world_answers: Array = []


## Plain data, for comparing two logs and for saving one.
func to_dict() -> Dictionary:
	var layout_data := {}
	var paths: Array[String] = []
	paths.assign(layouts.keys())
	paths.sort()
	for path: String in paths:
		layout_data[path] = layouts[path].to_dict()
	var command_data: Array[Dictionary] = []
	for command: MatchCommand in commands:
		command_data.append(command.to_dict())
	return {
		"session_seed": session_seed,
		"mode_path": mode_path,
		"mode_hash": mode_hash,
		"content_hash": content_hash,
		"layouts": layout_data,
		"start_tick": start_tick,
		"ticked_through": ticked_through,
		"commands": command_data,
		"world_answers": world_answers.duplicate(),
	}


## The log that to_dict() gave `data` (E13: a saved log read back for Match.replay). A missing
## entry reads as its default.
static func from_dict(data: Dictionary) -> CommandLog:
	var loaded := CommandLog.new()
	loaded.session_seed = data.get("session_seed", 0)
	loaded.mode_path = data.get("mode_path", "")
	loaded.mode_hash = data.get("mode_hash", 0)
	loaded.content_hash = data.get("content_hash", 0)
	loaded.start_tick = data.get("start_tick", -1)
	loaded.ticked_through = data.get("ticked_through", -1)
	var layout_data: Dictionary = data.get("layouts", {})
	for path: String in layout_data:
		var entry: Dictionary = layout_data[path]
		var layout_path: String = entry.get("path", path)
		var layout := LevelLayout.new(layout_path)
		var markers: Dictionary = entry.get("markers", {})
		for tag: String in markers:
			for position: Vector3 in markers[tag] as PackedVector3Array:
				layout.add_marker(StringName(tag), position)
		var volumes: Array = entry.get("no_rest", [])
		for volume: AABB in volumes:
			layout.add_no_rest(volume)
		loaded.layouts[path] = layout
	var command_data: Array = data.get("commands", [])
	for command: Dictionary in command_data:
		loaded.commands.append(MatchCommand.from_dict(command))
	var answers: Array = data.get("world_answers", [])
	loaded.world_answers = answers.duplicate()
	return loaded
