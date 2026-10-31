class_name BreakersTrippedEvent
extends MatchEvent
## The ship's engine's tripped breakers (ARCHITECTURE §4.2, §9.5.27; GDD §8): the breakers problem
## `problem` (EngineProblemOpened's id) tripped `breakers`, the breaker stations in the order to
## switch them back on (1 to 8 of them). The console's hologram plays that order to whoever looks
## (GDD §8: "Remember it, or a friend at the console reads it out"), so it is public. It names no
## player. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The problem's id.
var problem: int
## The tripped breaker stations, in the order to switch them on.
var breakers: PackedInt32Array


func _init(problem_id: int, order: PackedInt32Array) -> void:
	problem = problem_id
	breakers = order


func event_name() -> StringName:
	return &"BreakersTripped"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"problem": problem, "breakers": breakers.duplicate()}
