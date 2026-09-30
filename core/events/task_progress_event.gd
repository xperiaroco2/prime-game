class_name TaskProgressEvent
extends MatchEvent
## The shared task progress (ARCHITECTURE §4.2): the subtasks done and the subtasks in total, over
## every task of the match. Public: it names no task and no owner. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var done: int
var total: int


func _init(done_count: int, total_count: int) -> void:
	done = done_count
	total = total_count


func event_name() -> StringName:
	return &"TaskProgress"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"done": done, "total": total}
