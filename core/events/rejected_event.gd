class_name RejectedEvent
extends MatchEvent
## A rejected intent, or an applied intent whose outcome was dropped (`outcome_dropped`;
## ARCHITECTURE §3.1, §4.2). The reason depends only on facts the sender is entitled to (§4.1).
## Audience: the sender (SENDER), which may be a connected peer that is not a player yet.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.SENDER

var peer: int
## The intent's sequence number.
var seq: int
var reason: StringName


func _init(to_peer: int, intent_seq: int, why: StringName) -> void:
	peer = to_peer
	seq = intent_seq
	reason = why


func event_name() -> StringName:
	return &"Rejected"


func audience() -> Audience:
	return Audience.sender(peer)


func to_dict() -> Dictionary:
	return {"seq": seq, "reason": reason}
