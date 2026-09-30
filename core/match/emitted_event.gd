class_name EmittedEvent
extends RefCounted
## One event as Match emitted it (ARCHITECTURE §5): the tick, the event, and its recipients as
## its audience named them at emission. server/ builds one message per recipient and adds none;
## a server directive has no recipients.

var tick: int
var event: MatchEvent
var recipients: PackedInt32Array
var is_directive: bool


func _init(at_tick: int, what: MatchEvent, to_peers: PackedInt32Array, directive: bool) -> void:
	tick = at_tick
	event = what
	recipients = to_peers
	is_directive = directive


func describe() -> Dictionary:
	var described := event.describe()
	described["tick"] = tick
	described["recipients"] = recipients
	return described
