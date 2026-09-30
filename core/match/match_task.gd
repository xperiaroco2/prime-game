class_name MatchTask
extends RefCounted
## One dealt task in MatchState (ARCHITECTURE §9.1): its owner, its task type, and the state object
## that only its task type reads and writes. The owner and the detail are hidden: they reach
## only the owner (TasksAssigned, TaskUpdated).

var id: int
var owner: int
var type: TaskType
var state: TaskState


func _init(task_id: int, owner_peer: int, task_type: TaskType, task_state: TaskState) -> void:
	id = task_id
	owner = owner_peer
	type = task_type
	state = task_state
