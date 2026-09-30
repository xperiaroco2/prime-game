class_name MatchEndedEvent
extends MatchEvent
## The match has ended (ARCHITECTURE §4.2, §5): the winning side (a SideSpec id: crew or
## dissidents), nothing else. No names and no roles: End widens nothing, and each player knows
## from its own role whether it won. EndMatch (2h, #64) emits it on `Round, won -> End`.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The winning side's id.
var side: StringName


func _init(winning_side: StringName) -> void:
	side = winning_side


func event_name() -> StringName:
	return &"MatchEnded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"side": side}
