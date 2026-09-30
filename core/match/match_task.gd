class_name MatchTask
extends RefCounted
## One dealt task in MatchState (ARCHITECTURE §9.1): its task type and the state object that only
## its task type reads and writes. Tasks are shared (the engineer's decision of 2026-09-30, #79):
## nobody owns one, and any living player does any of its subtasks.

var id: int
var type: TaskType
var state: TaskState


func _init(task_id: int, task_type: TaskType, task_state: TaskState) -> void:
	id = task_id
	type = task_type
	state = task_state
