class_name DealTasks
extends RuleEffect
## Deals the match's shared tasks (ARCHITECTURE §3.3, §9.4; the engineer's decision of 2026-09-30,
## #79): draws `tasks_setting` different task types at random (`rng_purpose`) from the pool, the
## mode's task types minus the ones in `banned_setting` (the host's bans in the lobby), and runs
## each drawn type's TaskType.deal() once, in the mode's order. Nobody owns a task. Then each
## task's TaskState in id order (Tasks.announce: the task screen's data, E30) and TaskProgress
## (everyone) with the subtasks done and in total, so every client knows each task and the shared
## progress from the start (the HUD shows only the sum); with no task drawn it is 0 of 0.
##
## Emits: the task types' events (Delivery: StationPlaced, ItemSpawned; §9.5), then TaskState per
## task, then TaskProgress.
## Demands: for any draw, per spawn tag the sum of the `tasks` largest demands among the types
## not banned, and per station kind the same over colours (see add_demands).
## Refuses in ChangeSettings (settings_problem): `tasks` above the types not banned, or every
## type banned (`out_of_bounds`).

## The match setting that holds how many tasks a match has (`tasks`), a whole number.
@export var tasks_setting: StringName
## The match setting that holds the task types the host banned (`banned_task_types`), a set of
## task type ids (SettingSpec.Kind.TASK_TYPES); empty: nothing can be banned.
@export var banned_setting: StringName
## The RNG purpose of the draw (§3.3). The neutral default is empty: the data names it.
@export var rng_purpose: StringName


func run(ctx: MatchContext) -> void:
	var pool := pool_of(ctx.mode, ctx.id_set(banned_setting))
	var wanted := ctx.setting(tasks_setting)
	if wanted > pool.size():
		# settings_problem keeps the lobby from getting here.
		ctx.error("DealTasks: %d tasks, %d task types left after the bans" % [wanted, pool.size()])
		wanted = pool.size()
	var drawn := RngStreams.shuffled_indices(pool.size(), ctx.rng(rng_purpose)).slice(0, wanted)
	drawn.sort()
	for index: int in drawn:
		var own := ctx.copy()
		own.source = "%s, deal of task type %s" % [ctx.source, pool[index].id]
		pool[index].deal(own)
	Tasks.announce(ctx)
	var counted := Tasks.progress(ctx.state)
	ctx.emit(TaskProgressEvent.new(counted.x, counted.y))


## The mode's task types minus `banned` (ids), in the mode's order.
static func pool_of(mode: GameMode, banned: PackedStringArray) -> Array[TaskType]:
	var found: Array[TaskType] = []
	for type: TaskType in mode.task_types:
		if type != null and not banned.has(String(type.id)):
			found.append(type)
	return found


## Whatever `tasks` of the pool's types are drawn, the map must fit them: so per spawn tag the
## demand is the sum of the `tasks` largest demands of that tag among the pool's types, and per
## station kind the same over colours. For any draw of `tasks` types, the sum over the drawn
## types is at most that, per tag and per kind, so a map that passes the fit check fits every
## draw. With one type in the pool it is exactly that type's demand.
func add_demands(settings: Dictionary[StringName, int], players: int, into: Demands) -> void:
	if into.mode == null:
		return
	var pool := pool_of(into.mode, into.id_set(banned_setting))
	var wanted := mini(settings.get(tasks_setting, 0) as int, pool.size())
	if wanted <= 0:
		return
	var markers: Dictionary[StringName, Array] = {}
	var colours: Dictionary[StringName, Array] = {}
	for type: TaskType in pool:
		var own := Demands.new(into.mode)
		own.id_sets = into.id_sets
		type.add_demands(settings, players, own)
		for tag: StringName in own.markers:
			if not markers.has(tag):
				markers[tag] = []
			markers[tag].append(own.markers[tag])
		for station: StringName in own.colours:
			if not colours.has(station):
				colours[station] = []
			colours[station].append(own.colours[station])
			into.palettes[station] = own.palettes[station]
	for tag: StringName in markers:
		into.add_markers(tag, _largest_sum(markers[tag], wanted))
	for station: StringName in colours:
		into.colours[station] = (
			into.colours.get(station, 0) + _largest_sum(colours[station], wanted)
		)


func settings_problem(
	settings: Dictionary[StringName, int],
	id_sets: Dictionary[StringName, PackedStringArray],
	mode: GameMode
) -> StringName:
	var banned: PackedStringArray = id_sets.get(banned_setting, PackedStringArray())
	var left := pool_of(mode, banned).size()
	if not banned.is_empty() and left == 0:
		return RejectReasons.OUT_OF_BOUNDS
	if settings.get(tasks_setting, 0) > left:
		return RejectReasons.OUT_OF_BOUNDS
	return &""


func emits() -> Array[Script]:
	return [TaskStateEvent, TaskProgressEvent]


func set_settings() -> PackedStringArray:
	return PackedStringArray(["banned_setting"])


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if tasks_setting.is_empty():
		found.append("DealTasks has no tasks_setting")
	if rng_purpose.is_empty():
		found.append("DealTasks has an empty rng_purpose")
	var tasks := mode.find_setting(tasks_setting) if mode != null else null
	if tasks != null:
		if not tasks.is_number():
			found.append("DealTasks: setting %s is not a whole number" % tasks_setting)
		elif tasks.max_value > mode.task_types.size():
			found.append(
				(
					"DealTasks: setting %s goes up to %d, the mode has %d task types"
					% [tasks_setting, tasks.max_value, mode.task_types.size()]
				)
			)
	var banned := mode.find_setting(banned_setting) if mode != null else null
	if banned != null and banned.is_number():
		found.append("DealTasks: setting %s is not a set of task types" % banned_setting)
	return found


## The sum of the `count` largest of `values` (ints).
static func _largest_sum(values: Array, count: int) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	sorted.reverse()
	var total := 0
	for i in mini(count, sorted.size()):
		total += sorted[i] as int
	return total
