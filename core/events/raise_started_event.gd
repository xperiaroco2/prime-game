class_name RaiseStartedEvent
extends MatchEvent
## A living player started raising a downed one (ARCHITECTURE §4.2, §5; vision revision 1, Revive):
## `raiser` holds E over `target`, whose knockdown is paused and who is held in place until the
## raise stops or completes. Public, like both avatars. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var raiser: int
var target: int


func _init(raising: int, downed: int) -> void:
	raiser = raising
	target = downed


func event_name() -> StringName:
	return &"RaiseStarted"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"raiser": raiser, "target": target}
