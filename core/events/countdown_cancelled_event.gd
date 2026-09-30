class_name CountdownCancelledEvent
extends MatchEvent
## The countdown was cancelled (ARCHITECTURE §3.2, §4.2): a SetReady(false), a join or a leave.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

const UN_READY := &"un_ready"
const JOIN := &"join"
const LEAVE := &"leave"

## UN_READY, JOIN or LEAVE.
var reason: StringName


func _init(why: StringName) -> void:
	reason = why


func event_name() -> StringName:
	return &"CountdownCancelled"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"reason": reason}
