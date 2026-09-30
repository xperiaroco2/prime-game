class_name PlayerLoadedEvent
extends MatchEvent
## A valid LoadAck (ARCHITECTURE §4.2): that player has loaded the map. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int


func _init(loaded: int) -> void:
	peer = loaded


func event_name() -> StringName:
	return &"PlayerLoaded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer}
