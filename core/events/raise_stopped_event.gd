class_name RaiseStoppedEvent
extends MatchEvent
## A raise stopped before it completed (ARCHITECTURE §4.2, §5; vision revision 1, Revive): the
## downed `target`'s knockdown runs on from where it paused. It names the raiser and the target
## only, never a cause (the engineer's answer 7 on PR #133): a raise stopped by a hit on the raiser
## still confirms that hit to the attacker, an accepted exception to "no hit confirmation".
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var raiser: int
var target: int


func _init(raising: int, downed: int) -> void:
	raiser = raising
	target = downed


func event_name() -> StringName:
	return &"RaiseStopped"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"raiser": raiser, "target": target}
