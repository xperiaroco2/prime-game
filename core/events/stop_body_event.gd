class_name StopBodyEvent
extends MatchEvent
## A directive (ARCHITECTURE §4.2; the knockdown rework's KE3, KE15): the motion of `peer`'s body
## ended (its rest, the longest motion, a report that is not finite, a death, a leave, a revive or
## ResetMatch), and server/ frees its host body (HostBodies). A replay ignores it. Audience:
## server, no peer.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.SERVER

var peer: int


func _init(stopped: int) -> void:
	peer = stopped


func event_name() -> StringName:
	return &"StopBody"


func audience() -> Audience:
	return Audience.server()


func to_dict() -> Dictionary:
	return {"peer": peer}
