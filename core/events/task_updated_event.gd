class_name TaskUpdatedEvent
extends MatchEvent
## One of a player's own tasks moved on (ARCHITECTURE §4.2): the task and its subtasks done. Who
## owns a task is hidden (§5), so only the owner learns it, even when another player delivered
## the package. Audience: only the task's owner.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
var task: int
## The task's subtasks done.
var done: int


func _init(owner_peer: int, task_id: int, done_count: int) -> void:
	peer = owner_peer
	task = task_id
	done = done_count


func event_name() -> StringName:
	return &"TaskUpdated"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"task": task, "done": done}
