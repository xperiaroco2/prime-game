class_name Generator
extends TaskType
## The Generator (#679; ARCHITECTURE §3.3, §9.5; the Generator ADR's part 2): one shared
## task whose subtasks are its N active switches, N the subtasks setting (0 to `switches`), all
## done at once when the generator's charge is full (GE13 (a)). Nobody owns it: any living player
## of any role uses a switch or the button (Interact, through the station kinds' rules; GE1, GE2).
##
## The deal (DealTasks calls deal() when the draw picks it): the generator's station on the map's
## one `generator` marker, then a switch station on N of its `switches` `switch` markers, the N
## drawn from the one purpose `switches_rng` (GD2), in level order. Station ids: the generator
## first, then the switches. Every placed switch starts off. The other markers get no station:
## their devices are the fixed switches, on for good, which nobody can aim at or use (GE14), so a
## forged Interact can only name an unknown station (`nothing_to_do`, Match). StationPlaced goes
## out in id order, then the charge's progress event at 0 (GE9). With N = 0 the task has no
## subtasks and is done at the deal (#79): the generator is still placed, and done, and its
## progress goes out at its full value, not counting.
##
## A use (use_station, after StationUsable passed: a done task refuses every use `unavailable`):
## a switch toggles, and one that goes off while the charge runs stops it (SwitchChanged, then the
## progress event); the button stops a running charge, starts one when every active switch is on,
## and otherwise changes nothing (ButtonPressed, then the progress event on a start or stop).
##
## The tick (TaskTicks, in each phase that lists it: Round in the base mode): first a held
## progress event whose window has passed goes out, whether or not the charge still runs (GE8);
## then a running charge gains one tick, and at needed_ticks() it is done: every station of the
## task done, the progress event at its full value, then Tasks.subtask_done per active switch in
## station order (GE9, GE13). Nothing else stops or resets the charge (the ADR's rule 2.6): it
## belongs to no player.
##
## The progress event is ZoneProgress (GE7) for the generator's station: `ticks` counted through
## host tick `tick`, and whether it counts in the ticks after it. A start or stop inside a
## WINDOW_TICKS window since the last one goes out at the window's end with that tick's state
## (ZE4's window, GE8); done goes out in its own tick. A start or stop in a command comes before
## that tick's gain, so its event's `tick` is the tick before (the charge counted through it).
## SwitchChanged and ButtonPressed go out once per accepted use, bounded by the reliable-intent
## bucket alone (§4.5.6). No event names a player (the ADR's row 18), and nothing reads a role.
##
## Emits: StationPlaced and ZoneProgress (everyone) in the deal; SwitchChanged, ButtonPressed and
## ZoneProgress (everyone) on a use (use_emits); ZoneProgress, TaskState and TaskProgress
## (everyone) on a held event and at full charge. Raises subtask_done per active switch at full
## charge.

## The fewest host ticks between two of the charge's progress events, but for its done: ZE4's
## window (GE8).
const WINDOW_TICKS := ZoneTask.WINDOW_TICKS
## The bounds of `seconds`: ZoneTask's (GE10).
const MIN_SECONDS := ZoneTask.MIN_SECONDS
const MAX_SECONDS := ZoneTask.MAX_SECONDS


## The Generator's state (§9.1, GE5): the generator's station id; per active switch, in station
## order, its station id and whether it is on; the charge's ticks; whether it runs; done; and the
## progress event's window bookkeeping. Only Generator reads and writes it.
class State:
	extends TaskState

	## The generator's station id (-1 before the deal placed it).
	var generator := -1
	## The active switches' station ids, ascending: subtask i is switch i.
	var switches := PackedInt32Array()
	## Whether each active switch is on.
	var on: Array[bool] = []
	## Host ticks charged so far.
	var ticks := 0
	var running := false
	## Charged (or dealt with no switch): every station of the task is done.
	var done := false
	## The host tick of the charge's last progress event sent for a start or stop
	## (-WINDOW_TICKS before any).
	var sent_at := -WINDOW_TICKS
	## Whether a start or stop waits for its window's end.
	var pending := false

	## Every subtask at once, at full charge (GE13 (a)).
	func done_count() -> int:
		return switches.size() if done else 0

	func total() -> int:
		return switches.size()


## The generator's station kind: its button.
@export var generator: StationKind
## The switches' station kind.
@export var switch: StationKind
## The switch devices every map it plays on holds, exactly (GE10): the demands ask for that many
## `switch` markers, and the panel draws one bar per switch. At least 1. The neutral default is out
## of bounds on purpose: the data sets it.
@export var switches := 0
## How long the charge runs in all (GD9): 0.05 to 600, converted once to host ticks
## (needed_ticks). The neutral default is out of bounds on purpose: the data sets it.
@export var seconds := 0.0
## The RNG purpose of the active switches' markers (§3.3, GD2).
@export var switches_rng: StringName = &"switches"


func new_state() -> TaskState:
	return State.new()


func has_tick() -> bool:
	return true


## The host ticks the charge needs: `seconds` by the one rounding rule (Ticks), at least 1.
func needed_ticks() -> int:
	return maxi(1, Ticks.from_seconds(seconds))


func deal(ctx: MatchContext) -> void:
	var count := maxi(ctx.setting(subtasks_setting), 0)
	if not _fits(ctx, count):
		return
	var spots := ctx.layout.positions(switch.spawn_tag)
	var placed: Array[StationState] = [
		ctx.state.add_station(generator, ctx.layout.positions(generator.spawn_tag)[0], Color.WHITE)
	]
	if count > 0:
		for index: int in Tasks.pick(spots.size(), count, ctx.rng(switches_rng)):
			placed.append(ctx.state.add_station(switch, spots[index], Color.WHITE))
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	task_state.generator = placed[0].id
	for i in range(1, placed.size()):
		task_state.switches.append(placed[i].id)
		task_state.on.append(false)
	var needed := needed_ticks()
	if count == 0:
		task_state.done = true
		task_state.ticks = needed
		placed[0].done = true
	for station: StationState in placed:
		ctx.emit(
			StationPlacedEvent.new(station.id, station.kind.id, station.colour, station.position)
		)
	ctx.emit(ZoneProgressEvent.new(task_state.generator, task_state.ticks, needed, false, ctx.tick))


## Every use is taken until the task is done; then every station of it refuses `unavailable`
## (the ADR's row 11). Reads no role.
func use_problem(_ctx: MatchContext, task: MatchTask, _station: StationState) -> StringName:
	if task == null or (task.state as State).done:
		return StationUsable.UNAVAILABLE
	return &""


func use_station(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	if task == null:
		return  # StationUsable refused it.
	var task_state := task.state as State
	if station.id == task_state.generator:
		ctx.emit(ButtonPressedEvent.new(station.id))
		if task_state.running:
			task_state.running = false
			_changed(ctx, task_state)
		elif not task_state.on.has(false):
			task_state.running = true
			_changed(ctx, task_state)
		return
	var index := task_state.switches.find(station.id)
	if index < 0:
		ctx.error("Generator: station %d is neither its generator nor a switch" % station.id)
		return
	task_state.on[index] = not task_state.on[index]
	ctx.emit(SwitchChangedEvent.new(station.id, task_state.on[index]))
	if not task_state.on[index] and task_state.running:
		task_state.running = false
		_changed(ctx, task_state)


func use_emits() -> Array[Script]:
	return [SwitchChangedEvent, ButtonPressedEvent, ZoneProgressEvent]


func tick(ctx: MatchContext) -> void:
	for task_id: int in ctx.state.tasks:
		var task := ctx.state.tasks[task_id]
		if task.type != self:
			continue
		var task_state := task.state as State
		if task_state.done:
			continue
		# A held start or stop goes out before the charge is checked, so a stop always does.
		if task_state.pending and ctx.tick - task_state.sent_at >= WINDOW_TICKS:
			_send(ctx, task_state, ctx.tick - 1)
		if not task_state.running:
			continue
		task_state.ticks += 1
		if task_state.ticks >= needed_ticks():
			_complete(ctx, task, task_state)


## The charge started or stopped in a command: its progress event now, or at its window's end.
func _changed(ctx: MatchContext, task_state: State) -> void:
	if ctx.tick - task_state.sent_at >= WINDOW_TICKS:
		_send(ctx, task_state, ctx.tick - 1)
	else:
		task_state.pending = true


## The charge's progress event with the state now, counted through `through` (this tick's gain is
## still to come).
func _send(ctx: MatchContext, task_state: State, through: int) -> void:
	task_state.pending = false
	task_state.sent_at = ctx.tick
	ctx.emit(
		ZoneProgressEvent.new(
			task_state.generator, task_state.ticks, needed_ticks(), task_state.running, through
		)
	)


## Full charge: every station done, the progress event at its full value, then each active
## switch's subtask in station order (GE9, GE13).
func _complete(ctx: MatchContext, task: MatchTask, task_state: State) -> void:
	var needed := needed_ticks()
	task_state.ticks = needed
	task_state.running = false
	task_state.pending = false
	task_state.done = true
	var ids := PackedInt32Array([task_state.generator])
	ids.append_array(task_state.switches)
	for station_id: int in ids:
		var station: StationState = ctx.state.stations.get(station_id)
		if station != null:
			station.done = true
	ctx.emit(ZoneProgressEvent.new(task_state.generator, needed, needed, false, ctx.tick))
	for i in task_state.switches.size():
		Tasks.subtask_done(ctx, task, {"subtask": i, "station": task_state.switches[i]})


## Exactly one `generator` marker and exactly `switches` `switch` markers, whatever the setting and
## the players (GE10): every switch device is an active switch's station or a fixed switch. No
## colours.
func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	if generator == null or switch == null:
		return  # The check refuses such a mode.
	into.add_markers(generator.spawn_tag, 1, true)
	into.add_markers(switch.spawn_tag, switches, true)


func emits() -> Array[Script]:
	return [
		StationPlacedEvent,
		ZoneProgressEvent,
		SwitchChangedEvent,
		ButtonPressedEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


## GE10: both station kinds, with different spawn tags, each with an Interact rule whose effect is
## UseStation; `switches` at least 1; the subtasks setting at most `switches` (TaskType.check
## requires it, from at least 0; ModeCheck checks it names a declared whole-number setting);
## `seconds` within bounds; a non-empty RNG purpose.
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if generator == null:
		found.append("Generator %s has no generator station kind" % id)
	if switch == null:
		found.append("Generator %s has no switch station kind" % id)
	if generator != null and switch != null and generator.spawn_tag == switch.spawn_tag:
		found.append(
			"Generator %s: its two station kinds share the spawn tag %s" % [id, switch.spawn_tag]
		)
	for kind: StationKind in [generator, switch]:
		if kind != null and not _has_use_rule(kind):
			found.append(
				"Generator %s: station kind %s has no Interact rule with UseStation" % [id, kind.id]
			)
	if switches < 1:
		found.append("Generator %s has %d switches, fewer than 1" % [id, switches])
	# TaskType.check refuses an empty subtasks setting and one below 0 (G0); the top is the type's.
	var spec := (
		mode.find_setting(subtasks_setting)
		if mode != null and not subtasks_setting.is_empty()
		else null
	)
	if spec != null and spec.is_number() and spec.max_value > switches:
		found.append(
			(
				"Generator %s: setting %s goes up to %d, above its %d switches"
				% [id, subtasks_setting, spec.max_value, switches]
			)
		)
	if switches_rng.is_empty():
		found.append("Generator %s has an empty RNG purpose" % id)
	append_found(
		found, [out_of_bounds("Generator %s seconds" % id, seconds, MIN_SECONDS, MAX_SECONDS)]
	)
	return found


static func _has_use_rule(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT:
			continue
		for effect: RuleEffect in rule.effects:
			if effect is UseStation:
				return true
	return false


## Whether the level being entered has the generator's marker and a marker for each of `count`
## switches; the lobby's fit check (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext, count: int) -> bool:
	if not has_layout(ctx, "Generator"):
		return false
	var generators := ctx.layout.count(generator.spawn_tag)
	var markers := ctx.layout.count(switch.spawn_tag)
	if generators >= 1 and markers >= count:
		return true
	ctx.error(
		(
			"Generator: %d switches need a %s marker and as many %s markers; the map has %d and %d"
			% [count, generator.spawn_tag, switch.spawn_tag, generators, markers]
		)
	)
	return false
