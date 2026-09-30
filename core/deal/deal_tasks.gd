class_name DealTasks
extends RuleEffect
## Gives each present player `tasks_setting` tasks (ARCHITECTURE §3.3, §9.4), dealt by the mode's
## task types through TaskType.deal(), in the mode's order. With one task type it deals them all;
## with several, the tasks per player are split evenly in the mode's order, the first types
## taking one more each while the remainder lasts (share_of; not a decision, see §9.4). A type
## whose share is 0 deals nothing.
##
## Emits: the task types' events (Delivery: StationPlaced, ItemSpawned, TasksAssigned; §9.5).
## Demands: each task type's, for its share (TaskType.add_demands), forwarded to the task types
## of Demands.mode (LayoutCheck builds every Demands for its mode).

## The match setting that holds the tasks per player (`tasks_per_player`).
@export var tasks_setting: StringName


func run(ctx: MatchContext) -> void:
	var per_player := ctx.setting(tasks_setting)
	var types := ctx.mode.task_types
	for i in types.size():
		var share := share_of(per_player, types.size(), i)
		if share > 0:
			types[i].deal(ctx, share)


## The tasks per player that the `index`-th of `type_count` task types deals.
static func share_of(per_player: int, type_count: int, index: int) -> int:
	if type_count <= 0 or per_player <= 0:
		return 0
	var even := floori(float(per_player) / float(type_count))
	return even + (1 if index < per_player % type_count else 0)


func add_demands(settings: Dictionary[StringName, int], players: int, into: Demands) -> void:
	if into.mode == null:
		return
	var per_player: int = settings.get(tasks_setting, 0)
	var types := into.mode.task_types
	for i in types.size():
		var share := share_of(per_player, types.size(), i)
		if share > 0:
			types[i].add_demands(settings, players, share, into)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if tasks_setting.is_empty():
		found.append("DealTasks has no tasks_setting")
	return found
