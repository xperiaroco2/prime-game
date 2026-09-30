class_name CommandLog
extends RefCounted
## Everything core/ is given, so a match can be replayed (ARCHITECTURE §3.3): the session seed, the
## game mode's path and content hash, the host's content hash that joiners must match, the levels'
## layouts, the start tick, every command in
## order with its tick (server/'s own included), the last tick run, and every WorldQuery answer.
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
