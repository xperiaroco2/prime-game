class_name PlayerLeftEvent
extends MatchEvent
## A player left in any phase, or missed the loading deadline (ARCHITECTURE §3.5, §4.2). Emitted
## after the player left the roster or its life state became `left`, so it does not reach them.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int


func _init(leaver: int) -> void:
	peer = leaver


func event_name() -> StringName:
	return &"PlayerLeft"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer}
