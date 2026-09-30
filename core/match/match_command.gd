class_name MatchCommand
extends RefCounted
## One input to Match (ARCHITECTURE §3.3, §4.1): an intent from a peer, or a command server/
## originates (PeerConnected, PeerLeft), stamped with the host tick on which it applies. The
## sender is the peer id the transport reports, never a field of the message.

## An intent name (Intents.ALL) or a server command (Intents.PEER_CONNECTED, PEER_LEFT).
var kind: StringName
var peer: int
var tick: int
## The intent's sequence number, which a Rejected names.
var seq: int
## The intent's fields, plain data (§4.1).
var args: Dictionary


func _init(
	command_kind: StringName, sender: int, host_tick: int, fields: Dictionary = {}, number := 0
) -> void:
	kind = command_kind
	peer = sender
	tick = host_tick
	args = fields.duplicate(true)
	seq = number


func get_bool(key: String, default := false) -> bool:
	var value: Variant = args.get(key, default)
	return value if value is bool else default


func get_int(key: String, default := 0) -> int:
	var value: Variant = args.get(key, default)
	return value if value is int else default


func get_vector3(key: String, default := Vector3.ZERO) -> Vector3:
	var value: Variant = args.get(key, default)
	return value if value is Vector3 else default


func get_string(key: String, default := "") -> String:
	var value: Variant = args.get(key, default)
	return value if value is String else default


## Plain data for the command log.
func to_dict() -> Dictionary:
	return {"kind": kind, "peer": peer, "tick": tick, "seq": seq, "args": args.duplicate(true)}


static func from_dict(data: Dictionary) -> MatchCommand:
	var command_kind: StringName = data["kind"]
	var sender: int = data["peer"]
	var host_tick: int = data["tick"]
	var fields: Dictionary = data.get("args", {})
	var number: int = data.get("seq", 0)
	return MatchCommand.new(command_kind, sender, host_tick, fields, number)
