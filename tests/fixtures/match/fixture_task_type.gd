class_name FixtureTaskType
extends TaskType
## A task type whose check of a fact only emits a note "task <fact>", so tests see when task
## types run relative to the mode's reactions.


func _init() -> void:
	id = &"fixture_task"


func on_fact(ctx: MatchContext) -> void:
	ctx.emit(FixtureNoteEvent.new("task %s" % ctx.fact.name))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]
