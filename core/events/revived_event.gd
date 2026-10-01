class_name RevivedEvent
extends MatchEvent
## A raise completed (ARCHITECTURE §4.2, §5; vision revision 1, Revive): the downed `peer` stands
## up, living, where it lay, with the raise's revive health, invulnerable for
## PlayerRules.invulnerable_s. It also ends the raise: no RaiseStopped follows. Public, like the
## avatar that stands up; it names no raiser (RaiseStarted did). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int


func _init(revived: int) -> void:
	peer = revived


func event_name() -> StringName:
	return &"Revived"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer}
