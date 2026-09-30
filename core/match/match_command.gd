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
## The intent's fields, plain data (§4.1), named and typed by Intents.FIELDS; rules read them
## through field() and the typed getters.
var args: Dictionary
## The fields a rule read that Intents.FIELDS does not declare for this kind, in order, each once.
## Match records each as a match error after the command ran, so it reaches `diagnostics` (and
## the bots runner) rather than only the log. Not part of the command log.
var undeclared_reads := PackedStringArray()


func _init(
	command_kind: StringName, sender: int, host_tick: int, fields: Dictionary = {}, number := 0
) -> void:
	kind = command_kind
	peer = sender
	tick = host_tick
	args = fields.duplicate(true)
	seq = number


## The value of field `key`, as the client sent it (any type), or null when it is absent. The
## field must be one that Intents.FIELDS declares for this command's kind: reading another is a
## bug in the rule (a name the wire does not carry would always read as absent), so it is kept in
## `undeclared_reads`, which Match records as a match error, and read as absent (§4.4).
func field(key: String) -> Variant:
	if not declares(key):
		if not undeclared_reads.has(key):
			undeclared_reads.append(key)
		return null
	return args.get(key)


## Whether the command carries field `key` (declared, as field() requires).
func has_field(key: String) -> bool:
	return field(key) != null


## Whether Intents.FIELDS declares `key` for this command's kind.
func declares(key: String) -> bool:
	var declared: Dictionary = Intents.FIELDS.get(kind, {})
	return declared.has(key)


func get_bool(key: String, default := false) -> bool:
	var value: Variant = field(key)
	return value if value is bool else default


func get_int(key: String, default := 0) -> int:
	var value: Variant = field(key)
	return value if value is int else default


func get_vector3(key: String, default := Vector3.ZERO) -> Vector3:
	var value: Variant = field(key)
	return value if value is Vector3 else default


func get_string(key: String, default := "") -> String:
	var value: Variant = field(key)
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
