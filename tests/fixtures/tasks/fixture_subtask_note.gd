class_name FixtureSubtaskNote
extends RuleEffect
## A reaction effect on subtask_done: emits a FixtureNoteEvent "subtask_done <task> <owner>
## <detail>" to the server audience, so tests see the fact with its hidden fields while no peer's
## view gets them.


func run(ctx: MatchContext) -> void:
	ctx.emit(
		FixtureNoteEvent.new(
			text(ctx.fact.task, ctx.fact.player, ctx.fact.detail), Audience.server()
		)
	)


func emits() -> Array[Script]:
	return [FixtureNoteEvent]


static func text(task: int, owner: int, detail: Variant) -> String:
	return "subtask_done %d %d %s" % [task, owner, detail]
