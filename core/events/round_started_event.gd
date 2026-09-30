class_name RoundStartedEvent
extends MatchEvent
## The round has started (ARCHITECTURE §4.2): its start tick. StartClock (2h, #64) emits it as the
## last action of the deal's row. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The host tick on which the round starts.
var start_tick: int


func _init(at_tick: int) -> void:
	start_tick = at_tick


func event_name() -> StringName:
	return &"RoundStarted"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"start_tick": start_tick}
