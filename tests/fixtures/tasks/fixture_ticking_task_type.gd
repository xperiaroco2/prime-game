class_name FixtureTickingTaskType
extends TaskType
## A task type that ticks (the kind #36's zone task will be), for TaskTicks' tests: each tick
## emits a note "tick <id> <host tick> <source>". Its check of facts does nothing.


static func of(type_id: StringName) -> FixtureTickingTaskType:
	var made := FixtureTickingTaskType.new()
	made.id = type_id
	return made


func has_tick() -> bool:
	return true


func tick(ctx: MatchContext) -> void:
	ctx.emit(FixtureNoteEvent.new("tick %s %d %s" % [id, ctx.tick, ctx.source]))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]
