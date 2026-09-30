class_name Tasks
extends RefCounted
## What every task type does when one of its subtasks is done (ARCHITECTURE §4.2, §9.2): the
## public progress, the owner's private update, and the fact `subtask_done`. Delivery calls it;
## so will #36's zone task. The task type marks the subtask done in its own task state first.


## The subtasks done and the subtasks in total over every task of the match, as (done, total).
static func progress(state: MatchState) -> Vector2i:
	var counted := Vector2i.ZERO
	for id: int in state.tasks:
		var task_state := state.tasks[id].state
		counted.x += task_state.done_count()
		counted.y += task_state.total()
	return counted


## A subtask of `task` is done: emits TaskProgress (everyone), then TaskUpdated (the task's owner
## only), then raises subtask_done with the task, its owner and `detail`, the task type's detail
## of the subtask. The owner and the detail are hidden fields of the fact (§9.2): a reaction must
## not copy them into an event with a wider audience.
static func subtask_done(ctx: MatchContext, task: MatchTask, detail: Variant) -> void:
	var counted := progress(ctx.state)
	ctx.emit(TaskProgressEvent.new(counted.x, counted.y))
	ctx.emit(TaskUpdatedEvent.new(task.owner, task.id, task.state.done_count()))
	var fact := Fact.new(Facts.SUBTASK_DONE)
	fact.task = task.id
	fact.player = task.owner
	fact.detail = detail
	ctx.raise_fact(fact)
