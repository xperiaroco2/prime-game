class_name ReadyChangedEvent
extends MatchEvent
## A player's ready flag (ARCHITECTURE §4.2): an accepted SetReady, and everyone un-ready on
## `End -> Lobby` (ResetMatch). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var ready: bool


func _init(of_peer: int, is_ready: bool) -> void:
	peer = of_peer
	ready = is_ready


func event_name() -> StringName:
	return &"ReadyChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "ready": ready}
