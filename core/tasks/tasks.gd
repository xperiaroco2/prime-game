class_name Tasks
extends RefCounted
## What every task type does when one of its subtasks is done (ARCHITECTURE §4.2, §9.2): the
## public progress and the fact `subtask_done`. Delivery calls it; so will #36's zone task. The
## task type marks the subtask done in its own task state first. Tasks are shared (#79): no
## task has an owner, so nothing here is private.


## The subtasks done and the subtasks in total over every task of the match, as (done, total).
static func progress(state: MatchState) -> Vector2i:
	var counted := Vector2i.ZERO
	for id: int in state.tasks:
		var task_state := state.tasks[id].state
		counted.x += task_state.done_count()
		counted.y += task_state.total()
	return counted


## Whether every task of the match is done (the engineer's rule of 2026-09-30, #79): a task with
## no subtasks is done, and with no tasks at all this holds. AllSubtasksDone (2h, #64) reads it.
static func all_done(state: MatchState) -> bool:
	for id: int in state.tasks:
		if not state.tasks[id].state.is_done():
			return false
	return true


## A subtask of `task` is done: emits TaskProgress (everyone), then raises subtask_done with the
## task and `detail`, the task type's detail of the subtask. The detail is a hidden field of the
## fact (§9.2): no event carries it, and a reaction must not copy it into one.
static func subtask_done(ctx: MatchContext, task: MatchTask, detail: Variant) -> void:
	var counted := progress(ctx.state)
	ctx.emit(TaskProgressEvent.new(counted.x, counted.y))
	var fact := Fact.new(Facts.SUBTASK_DONE)
	fact.task = task.id
	fact.detail = detail
	ctx.raise_fact(fact)
