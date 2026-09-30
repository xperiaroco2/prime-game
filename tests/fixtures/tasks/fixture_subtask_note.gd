class_name FixtureSubtaskNote
extends RuleEffect
## A reaction effect on subtask_done: emits a FixtureNoteEvent "subtask_done <task> <detail>" to
## the server audience, so tests see the fact with its hidden detail while no peer's view gets
## it.


func run(ctx: MatchContext) -> void:
	ctx.emit(FixtureNoteEvent.new(text(ctx.fact.task, ctx.fact.detail), Audience.server()))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]


static func text(task: int, detail: Variant) -> String:
	return "subtask_done %d %s" % [task, detail]
