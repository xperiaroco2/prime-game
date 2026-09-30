class_name SwungEvent
extends MatchEvent
## A player swung a weapon (ARCHITECTURE §4.2, §7.1): a valid Use whose rule strikes (Strike),
## whether or not it touched anyone. Swings are public; who was hit is not, so nothing here says
## whether the swing touched anyone. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
## The facing the strike used: the Use's, or the last accepted claim's when the Use had none.
var facing: Vector3


func _init(attacker: int, toward: Vector3) -> void:
	peer = attacker
	facing = toward


func event_name() -> StringName:
	return &"Swung"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "facing": facing}
