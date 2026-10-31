class_name EngineProblemFixedEvent
extends MatchEvent
## The ship's engine (ARCHITECTURE §4.2, §9.5.27; GDD §8): the problem `problem`
## (EngineProblemOpened's id) was fixed; its stations are calm again. It names no player: nobody
## is told who fixed it. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The problem's id.
var problem: int


func _init(problem_id: int) -> void:
	problem = problem_id


func event_name() -> StringName:
	return &"EngineProblemFixed"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"problem": problem}
