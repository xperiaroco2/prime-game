class_name TaskTicks
extends TickSystem
## The tick system of the task types (ARCHITECTURE §3.3, §9.4): every tick of the phase that lists
## it, runs the tick of each of the mode's task types that has one (TaskType.has_tick), in the
## mode's order: the zone task's (ZoneTask, #647); Delivery has none, it is checked when an item
## comes to rest. ModeCheck refuses a ticking task type that no phase lists this in. Emits: the
## task types' events.


func run(ctx: MatchContext) -> void:
	for type: TaskType in ctx.mode.task_types:
		if type == null or not type.has_tick():
			continue
		var own := ctx.copy()
		own.source = "tick of task type %s" % type.id
		type.tick(own)
