class_name FixtureDealTasks
extends RuleEffect
## Stands in for DealTasks (2c) in tests: a transition action that calls deal() of each of the
## mode's task types, in the mode's order, with the match setting `tasks_per_player`.

const TASKS_PER_PLAYER := &"tasks_per_player"


func run(ctx: MatchContext) -> void:
	for type: TaskType in ctx.mode.task_types:
		type.deal(ctx, ctx.setting(TASKS_PER_PLAYER))
