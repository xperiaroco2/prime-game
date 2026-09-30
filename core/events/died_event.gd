class_name DiedEvent
extends MatchEvent
## A player died (ARCHITECTURE §4.2, §5): its health reached 0, and its body rests at `position`.
## Bodies and whose they are are public; no field names a killer or a cause. Emitted after the
## player became a ghost, so it reaches the dead player too. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
## The body's rest position: the floor below the player's last accepted position.
var position: Vector3


func _init(dead: int, body_at: Vector3) -> void:
	peer = dead
	position = body_at


func event_name() -> StringName:
	return &"Died"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "position": position}
