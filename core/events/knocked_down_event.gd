class_name KnockedDownEvent
extends MatchEvent
## A living player reached 0 health and is downed where it stood (ARCHITECTURE §4.2, §5): it
## crawls at `position` for the knockdown time, then dies. Public, like the downed avatar itself;
## no field names an attacker or a cause. It confirms a hit to the attacker, an accepted exception
## to "no hit confirmation" (vision revision 1). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
## Where it lies: the floor below its last accepted position.
var position: Vector3


func _init(downed: int, lies_at: Vector3) -> void:
	peer = downed
	position = lies_at


func event_name() -> StringName:
	return &"KnockedDown"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "position": position}
