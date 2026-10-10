class_name MatchEndedEvent
extends MatchEvent
## The match has ended (ARCHITECTURE §4.2, §5): the winning side (a SideSpec id: crew or
## dissidents) and, when a win condition ended it, why (#548): the condition's id and whole-number
## arguments (`time`: the round's play time in whole seconds, when the clock ran), so the post-game
## screen words the reason in each player's language. All public: the condition's id names what
## every player saw end the round (the tasks, the clock, who is left), the time follows from the
## public RoundStarted and this event. No names and no roles: each player knows from its own role
## whether it won. EndMatch (2h, #64) emits it on `Round, won -> End`. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The winning side's id.
var side: StringName
## The id of the win condition that ended the match (WinCondition.id), or empty when none did (a
## `won` reported by a rule): then to_dict() has neither `reason` nor `numbers`.
var reason: StringName
## The reason's arguments by name: `time` (seconds), when the clock ran.
var numbers: Dictionary[StringName, int] = {}


func _init(
	winning_side: StringName, why: StringName = &"", arguments: Dictionary[StringName, int] = {}
) -> void:
	side = winning_side
	reason = why
	numbers = arguments.duplicate()


func event_name() -> StringName:
	return &"MatchEnded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	if reason.is_empty():
		return {"side": side}
	return {"side": side, "reason": reason, "numbers": numbers.duplicate()}
