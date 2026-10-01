class_name TaskStateEvent
extends MatchEvent
## One task's public progress (ARCHITECTURE §4.2; E30, the task screen): the task's id, its task
## type's id, and its subtasks done and in total. Emitted for each task after the deal and after
## each of its subtasks is done. Tasks are shared (#79) and the task screen is every player's,
## living, downed or dead (vision revision 1): it names no owner, no item and no position.
## TaskProgress, the sum over every task, stays for the HUD. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var task: int
var type: StringName
var done: int
var total: int


func _init(task_id: int, type_id: StringName, done_count: int, total_count: int) -> void:
	task = task_id
	type = type_id
	done = done_count
	total = total_count


func event_name() -> StringName:
	return &"TaskState"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"task": task, "type": type, "done": done, "total": total}
