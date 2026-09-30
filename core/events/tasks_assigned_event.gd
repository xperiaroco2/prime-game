class_name TasksAssignedEvent
extends MatchEvent
## A player's own tasks, from the deal (ARCHITECTURE §3.3, §4.2): per task its id and task type,
## and per subtask its target, an item id or a station id (Delivery: the package; its circle is
## in ItemSpawned). Another player's tasks never leave the host (§5). Audience: only that player.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
## Per task, in task-id order: {"task": id, "type": the task type's id, "subtasks": [target]},
## where a target is {"item": id} or {"station": id}.
var tasks: Array[Dictionary] = []


func _init(to_peer: int, dealt: Array[Dictionary]) -> void:
	peer = to_peer
	tasks = dealt.duplicate(true)


## One task of the payload.
static func task_entry(task_id: int, type_id: StringName, targets: Array[Dictionary]) -> Dictionary:
	return {"task": task_id, "type": type_id, "subtasks": targets.duplicate(true)}


func event_name() -> StringName:
	return &"TasksAssigned"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"tasks": tasks.duplicate(true)}
