class_name ShipEngine
extends TaskType
## The ship's engine (GDD §8; ARCHITECTURE §9.5.27; #1225, #1453): one shared task whose subtasks
## are its stages (`stage_problems`' first N, N the subtasks setting, 0 to their count), all done
## at once when the last stage passes (the Generator's GE13 (a)): TaskState never goes back on a
## blast and subtask_done is raised once per stage. Nobody owns it: any living player of any role
## presses the start and fixes problems (Interact, through the station kinds' rules).
##
## The deal: the start console's station on the map's one `start` marker, then per problem kind
## (`kinds`, ProblemKind) its `site_count` sites and its fixtures, each in level order; station ids
## in that order. The two `aboard_tag` markers are opposite corners of the box that is "aboard"
## (the ship's interior; a technical choice, #1453): no station. StationPlaced goes out in id order,
## then the bar's ZoneProgress at 0. With N = 0 the task is done at the deal (#79): every station
## placed and done, the bar full and not counting.
##
## The start: a use of the console (ButtonPressed) starts stage 1; a started or done engine
## refuses the console `unavailable`. A use of a kind's station goes to its kind
## (ProblemKind.use_problem, use_station) with the open problem holding it, or null.
##
## A stage s: its `stage_problems[s - 1]` problems open at moments drawn from `when_rng`, uniform
## over the stage's first `stage_seconds` of host ticks from its start (spread across the stage, not
## all at its start), in time order; each on a kind drawn from `what_rng` among the kinds with a
## free site, on the sites its kind claims (ProblemKind.claim), each problem with its own timer
## (its kind's `seconds`). No free site: it opens on the first tick one is free. The bar (one
## ZoneProgress on the console, `stages` thirds of `stage_seconds` each) charges while no problem is
## open; a stage passes when its part of the bar is full, every problem of it has opened and none
## is open. The last one passed: done.
##
## The tick (TaskTicks), per task, in this order: a held bar event whose window has passed; the
## spawns whose moment came; each open problem's kind tick (ProblemKind.tick_problem), in opening
## order; the blast, when an open problem's deadline is this tick (a command of that tick that
## fixed it saved it); the bar's start or stop (a held ZoneProgress, as the Generator's window)
## and its gain; the stage's pass.
##
## The blast: EngineBlast (the stage after the drop), then each living player inside the aboard box
## knocked down (LifeRules.knock_down, in peer order: KnockedDown, Correction, LaunchBody),
## invulnerable or not (GDD §8, "everyone aboard"; a knockdown is not damage); the open problems are
## gone (ProblemKind.cleared, in opening order); the engine drops one stage (s to s - 1, stage 1
## restarts stage 1), its bar back to that stage's start, ZoneProgress now; the stage's spawns are
## drawn again. Downed, dead and absent players and those outside the box are untouched.
##
## No event names a player or a kind, and nothing reads a role. Emits: StationPlaced and
## ZoneProgress in the deal; ButtonPressed, EngineProblemFixed and the kinds' use events on a use;
## EngineProblemOpened, EngineProblemFixed, EngineBlast, KnockedDown, Correction, LaunchBody,
## ZoneProgress, TaskState and TaskProgress in the tick. Raises subtask_done per stage at the end.

## The fewest host ticks between two of the bar's progress events, but for a blast's and the
## done's: the Generator's window.
const WINDOW_TICKS := ZoneTask.WINDOW_TICKS
## The bounds of `stage_seconds`: ZoneTask's.
const MIN_SECONDS := ZoneTask.MIN_SECONDS
const MAX_SECONDS := ZoneTask.MAX_SECONDS
## The most stages and the most problems one stage spawns.
const MAX_STAGES := 6
const MAX_STAGE_PROBLEMS := 16
## The most stations one problem holds (EngineProblemOpened's list; WireSchema pins its own equal).
const MAX_PROBLEM_STATIONS := 8
## The slack of the aboard box on every side, in metres.
const ABOARD_SLACK_M := 0.01


## The engine's state (§9.1): its stations, its stage and bar, its spawn schedule and its open
## problems. Only ShipEngine and its kinds (through the problems) read and write it.
class State:
	extends TaskState

	## The console's station id (-1 before the deal).
	var console := -1
	## The kind index (into ShipEngine.kinds) of each of the kinds' station ids.
	var kind_of: Dictionary[int, int] = {}
	## Per kind, its sites' station ids, ascending.
	var sites: Array[PackedInt32Array] = []
	## Every station id of the task, ascending.
	var stations := PackedInt32Array()
	## The stages dealt (the subtasks).
	var stages := 0
	## The stage the engine stands on, 1 up.
	var stage := 1
	var started := false
	## The last stage passed (or no stage dealt): every station done.
	var done := false
	## The bar's host ticks charged, over every stage.
	var charge := 0
	## Whether the bar charges.
	var running := false
	## The host tick the stage's spawn moments count from.
	var stage_start := 0
	## The stage's spawn moments, host ticks after stage_start, ascending.
	var schedule := PackedInt32Array()
	## How many of `schedule` have opened.
	var spawned := 0
	## The open problems, in opening order.
	var problems: Array[EngineProblem] = []
	## The next problem's id.
	var next_problem := 1
	## The aboard box's corners.
	var aboard_low := Vector3.ZERO
	var aboard_high := Vector3.ZERO
	## The host tick of the bar's last progress event sent for a start or stop.
	var sent_at := -WINDOW_TICKS
	## Whether a start or stop waits for its window's end.
	var pending := false

	## Every stage at once, at the end (GE13 (a)): a blast never takes one back.
	func done_count() -> int:
		return stages if done else 0

	func total() -> int:
		return stages


## The start console's station kind.
@export var start: StationKind
## The problem kinds, in data order (their stations' id order, the draw's order).
@export var kinds: Array[ProblemKind] = []
## The problems each stage spawns, stage 1 first (GDD §8: 2, 4, 6). 1 to MAX_STAGES entries, each
## 1 to MAX_STAGE_PROBLEMS.
@export var stage_problems := PackedInt32Array()
## Each stage's part of the bar, and the span its spawn moments are drawn over (GDD §8: "about
## 30 s each", a placeholder). The neutral default is out of bounds on purpose: the data sets it.
@export var stage_seconds := 0.0
## The tag of the two markers at opposite corners of the box that is aboard.
@export var aboard_tag: StringName = &"engine_aboard"
## The RNG purposes of the spawn moments and of each problem's kind and sites (§3.3).
@export var when_rng: StringName = &"engine_when"
@export var what_rng: StringName = &"engine_what"


func new_state() -> TaskState:
	return State.new()


func has_tick() -> bool:
	return true


## The blast knocks players down: ModeCheck's KillCheck then requires LifeTicks with a Respawn in
## each phase that lists TaskTicks.
func knocks_down() -> bool:
	return true


## The last stage's pass is the finish (GDD §8): the round lingers for it (§3.4, #1502).
func has_finale() -> bool:
	return true


## One stage's host ticks: `stage_seconds` by the one rounding rule, at least 1.
func stage_ticks() -> int:
	return maxi(1, Ticks.from_seconds(stage_seconds))


## The bar's host ticks for `stages` stages, at least 1.
func bar_ticks(stages: int) -> int:
	return maxi(1, stages * stage_ticks())


func deal(ctx: MatchContext) -> void:
	var count := clampi(ctx.setting(subtasks_setting), 0, stage_problems.size())
	if not _fits(ctx):
		return
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	task_state.stages = count
	var placed: Array[StationState] = [
		ctx.state.add_station(start, ctx.layout.positions(start.spawn_tag)[0], Color.WHITE)
	]
	task_state.console = placed[0].id
	for k in kinds.size():
		var kind := kinds[k]
		var ids := PackedInt32Array()
		var spots := ctx.layout.positions(kind.site.spawn_tag).slice(0, kind.site_count)
		for spot: Vector3 in spots:
			placed.append(ctx.state.add_station(kind.site, spot, Color.WHITE))
			ids.append(placed[-1].id)
			task_state.kind_of[placed[-1].id] = k
		task_state.sites.append(ids)
		for fixture: StationKind in kind.fixtures:
			for spot: Vector3 in ctx.layout.positions(fixture.spawn_tag):
				placed.append(ctx.state.add_station(fixture, spot, Color.WHITE))
				task_state.kind_of[placed[-1].id] = k
	for station: StationState in placed:
		task_state.stations.append(station.id)
	var corners := ctx.layout.positions(aboard_tag)
	task_state.aboard_low = corners[0].min(corners[1])
	task_state.aboard_high = corners[0].max(corners[1])
	if count == 0:
		task_state.done = true
		task_state.charge = bar_ticks(0)
		for station: StationState in placed:
			station.done = true
	for station: StationState in placed:
		ctx.emit(
			StationPlacedEvent.new(station.id, station.kind.id, station.colour, station.position)
		)
	ctx.emit(
		ZoneProgressEvent.new(
			task_state.console, task_state.charge, bar_ticks(count), false, ctx.tick
		)
	)


## The console takes one use, the start; a kind's station is its kind's to refuse; a done engine
## refuses every use `unavailable`. Reads no role.
func use_problem(ctx: MatchContext, task: MatchTask, station: StationState) -> StringName:
	if task == null or (task.state as State).done:
		return StationUsable.UNAVAILABLE
	var task_state := task.state as State
	if station.id == task_state.console:
		return StationUsable.UNAVAILABLE if task_state.started else &""
	var k: int = task_state.kind_of.get(station.id, -1)
	if k < 0:
		return StationUsable.UNAVAILABLE
	return kinds[k].use_problem(ctx, task, station, problem_at(task_state, station.id))


func use_reasons() -> Array[StringName]:
	var found: Array[StringName] = [StationUsable.UNAVAILABLE]
	for kind: ProblemKind in kinds:
		if kind == null:
			continue
		for reason: StringName in kind.use_reasons():
			if not found.has(reason):
				found.append(reason)
	return found


func use_station(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	if task == null:
		return  # StationUsable refused it.
	var task_state := task.state as State
	if station.id == task_state.console:
		task_state.started = true
		ctx.emit(ButtonPressedEvent.new(station.id))
		_begin_stage(ctx, task_state, ctx.tick)
		return
	var k: int = task_state.kind_of.get(station.id, -1)
	if k < 0:
		ctx.error("ShipEngine: station %d is none of its stations" % station.id)
		return
	kinds[k].use_station(ctx, task, station, problem_at(task_state, station.id))


func use_emits() -> Array[Script]:
	var found: Array[Script] = [ButtonPressedEvent, EngineProblemFixedEvent]
	for kind: ProblemKind in kinds:
		if kind != null:
			_add_scripts(found, kind.use_emits())
	return found


## The open problem holding `station_id`, or null.
static func problem_at(task_state: State, station_id: int) -> EngineProblem:
	for problem: EngineProblem in task_state.problems:
		if problem.stations.has(station_id):
			return problem
	return null


## `problem` is fixed (its kind's use or tick): it closes, EngineProblemFixed goes out. The bar
## starts again on the next tick when no other is open.
static func fix(ctx: MatchContext, task: MatchTask, problem: EngineProblem) -> void:
	var task_state := task.state as State
	var index := task_state.problems.find(problem)
	if index < 0:
		ctx.error("ShipEngine.fix: problem %d is not open" % problem.id)
		return
	task_state.problems.remove_at(index)
	ctx.emit(EngineProblemFixedEvent.new(problem.id))


func tick(ctx: MatchContext) -> void:
	for task_id: int in ctx.state.tasks:
		var task := ctx.state.tasks[task_id]
		if task.type != self:
			continue
		var task_state := task.state as State
		if task_state.done:
			continue
		if task_state.pending and ctx.tick - task_state.sent_at >= WINDOW_TICKS:
			_send(ctx, task_state, ctx.tick - 1)
		if not task_state.started:
			continue
		_spawn(ctx, task, task_state)
		for problem: EngineProblem in task_state.problems.duplicate():
			if task_state.problems.has(problem):
				problem.kind.tick_problem(ctx, task, problem)
		if _blown(ctx, task_state):
			_blast(ctx, task, task_state)
			continue
		var goal := task_state.stage * stage_ticks()
		var runs := task_state.problems.is_empty() and task_state.charge < goal
		if runs != task_state.running:
			task_state.running = runs
			_changed(ctx, task_state)
		if runs:
			task_state.charge += 1
		if (
			task_state.charge >= goal
			and task_state.spawned == task_state.schedule.size()
			and task_state.problems.is_empty()
		):
			_pass(ctx, task, task_state)


## Whether `at` is inside the box between `low` and `high`, ABOARD_SLACK_M on every side.
static func in_box(at: Vector3, low: Vector3, high: Vector3) -> bool:
	var slack := Vector3.ONE * ABOARD_SLACK_M
	var from := low - slack
	var to := high + slack
	return (
		at.x >= from.x
		and at.x <= to.x
		and at.y >= from.y
		and at.y <= to.y
		and at.z >= from.z
		and at.z <= to.z
	)


## The living players aboard (their last accepted position in the box), in peer order.
func aboard(ctx: MatchContext, task_state: State) -> Array[int]:
	var peers: Array[int] = []
	for peer: int in ctx.state.players:
		peers.append(peer)
	peers.sort()
	var found: Array[int] = []
	for peer: int in peers:
		var player := ctx.state.players[peer]
		if (
			player.is_alive()
			and in_box(player.position, task_state.aboard_low, task_state.aboard_high)
		):
			found.append(peer)
	return found


## Stage `task_state.stage` begins at `from_tick`: its spawn moments drawn, none opened yet.
func _begin_stage(ctx: MatchContext, task_state: State, from_tick: int) -> void:
	task_state.stage_start = from_tick
	task_state.spawned = 0
	var rng := ctx.rng(when_rng)
	var moments := PackedInt32Array()
	for i in stage_problems[task_state.stage - 1]:
		moments.append(rng.randi_range(0, stage_ticks() - 1))
	moments.sort()
	task_state.schedule = moments


## Opens every problem whose moment came, while a kind has a free site.
func _spawn(ctx: MatchContext, task: MatchTask, task_state: State) -> void:
	while (
		task_state.spawned < task_state.schedule.size()
		and ctx.tick - task_state.stage_start >= task_state.schedule[task_state.spawned]
	):
		if not _open(ctx, task, task_state):
			return
		task_state.spawned += 1


## Opens one problem: a kind drawn among those with a free site, the sites it claims. False when
## no kind has a free site.
func _open(ctx: MatchContext, task: MatchTask, task_state: State) -> bool:
	var candidates: Array[int] = []
	for k in kinds.size():
		if not _free_sites(task_state, k).is_empty():
			candidates.append(k)
	if candidates.is_empty():
		return false
	var rng := ctx.rng(what_rng)
	var k := candidates[rng.randi_range(0, candidates.size() - 1)]
	var kind := kinds[k]
	var free := _free_sites(task_state, k)
	var claimed := kind.claim(ctx, task, free, task_state.stage, rng)
	if not _claim_fits(claimed, free):
		ctx.error(
			(
				"ShipEngine: problem kind %s claimed %s of its free sites %s; it takes %d"
				% [kind.id, claimed, free, free[0]]
			)
		)
		claimed = PackedInt32Array([free[0]])
	claimed.sort()
	var deadline := ctx.tick + maxi(1, Ticks.from_seconds(kind.seconds))
	var problem := EngineProblem.new(
		task_state.next_problem, kind, claimed, ctx.tick, deadline, task_state.stage
	)
	# A u16 on the wire: an endless match wraps around long after any open problem closed.
	task_state.next_problem = task_state.next_problem % 0xFFFF + 1
	task_state.problems.append(problem)
	ctx.emit(EngineProblemOpenedEvent.new(problem.id, claimed.duplicate(), deadline))
	kind.opened(ctx, task, problem)
	return true


## The sites of kind `k` without an open problem, ascending.
static func _free_sites(task_state: State, k: int) -> PackedInt32Array:
	var free := PackedInt32Array()
	for station_id: int in task_state.sites[k]:
		if problem_at(task_state, station_id) == null:
			free.append(station_id)
	return free


## Whether `claimed` holds 1 to MAX_PROBLEM_STATIONS distinct ids of `free`.
static func _claim_fits(claimed: PackedInt32Array, free: PackedInt32Array) -> bool:
	if claimed.is_empty() or claimed.size() > MAX_PROBLEM_STATIONS:
		return false
	for i in claimed.size():
		if not free.has(claimed[i]) or claimed.find(claimed[i]) != i:
			return false
	return true


## Whether an open problem's deadline came.
static func _blown(ctx: MatchContext, task_state: State) -> bool:
	for problem: EngineProblem in task_state.problems:
		if problem.deadline <= ctx.tick:
			return true
	return false


## The blast (GDD §8): the order the class doc gives.
func _blast(ctx: MatchContext, task: MatchTask, task_state: State) -> void:
	var stage := maxi(1, task_state.stage - 1)
	ctx.emit(EngineBlastEvent.new(stage))
	for peer: int in aboard(ctx, task_state):
		LifeRules.knock_down(ctx, peer)
	var gone := task_state.problems.duplicate()
	task_state.problems.clear()
	for problem: EngineProblem in gone:
		problem.kind.cleared(ctx, task, problem)
	task_state.stage = stage
	task_state.charge = (stage - 1) * stage_ticks()
	task_state.running = false
	_send(ctx, task_state, ctx.tick)
	_begin_stage(ctx, task_state, ctx.tick + 1)


## The stage passed: the next begins on the next tick, or the engine is done.
func _pass(ctx: MatchContext, task: MatchTask, task_state: State) -> void:
	if task_state.stage < task_state.stages:
		task_state.stage += 1
		_begin_stage(ctx, task_state, ctx.tick + 1)
		return
	var needed := bar_ticks(task_state.stages)
	task_state.done = true
	task_state.charge = needed
	task_state.running = false
	task_state.pending = false
	for station_id: int in task_state.stations:
		var station: StationState = ctx.state.stations.get(station_id)
		if station != null:
			station.done = true
	ctx.emit(ZoneProgressEvent.new(task_state.console, needed, needed, false, ctx.tick))
	for i in task_state.stages:
		Tasks.subtask_done(ctx, task, {"subtask": i, "stage": i + 1})


## The bar started or stopped: its progress event now, or at its window's end.
func _changed(ctx: MatchContext, task_state: State) -> void:
	if ctx.tick - task_state.sent_at >= WINDOW_TICKS:
		_send(ctx, task_state, ctx.tick - 1)
	else:
		task_state.pending = true


## The bar's progress event with the state now, counted through `through`.
func _send(ctx: MatchContext, task_state: State, through: int) -> void:
	task_state.pending = false
	task_state.sent_at = ctx.tick
	ctx.emit(
		ZoneProgressEvent.new(
			task_state.console,
			task_state.charge,
			bar_ticks(task_state.stages),
			task_state.running,
			through
		)
	)


## The console, then each kind's site and fixtures, in data order.
func station_kinds() -> Array[StationKind]:
	var found: Array[StationKind] = []
	if start != null:
		found.append(start)
	for kind: ProblemKind in kinds:
		if kind != null:
			found.append_array(kind.station_kinds())
	return found


## Exactly one start marker and two aboard corners, and each kind's (ProblemKind.add_demands),
## whatever the setting and the players: no difficulty scaling (GDD §8).
func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	if start != null:
		into.add_markers(start.spawn_tag, 1, true)
	into.add_markers(aboard_tag, 2, true)
	for kind: ProblemKind in kinds:
		if kind != null:
			kind.add_demands(into)


func emits() -> Array[Script]:
	var found: Array[Script] = [
		StationPlacedEvent,
		ZoneProgressEvent,
		ButtonPressedEvent,
		EngineProblemOpenedEvent,
		EngineProblemFixedEvent,
		EngineBlastEvent,
		KnockedDownEvent,
		CorrectionEvent,
		LaunchBodyEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]
	for kind: ProblemKind in kinds:
		if kind != null:
			_add_scripts(found, kind.emits())
			_add_scripts(found, kind.use_emits())
	return found


## The start kind and at least one problem kind, each fine (ProblemKind.check) with its own id;
## every station kind with an Interact rule whose effect is UseStation (ModeCheck refuses two kinds
## on one tag); the aboard tag set and none of theirs; 1 to MAX_STAGES stages of 1 to
## MAX_STAGE_PROBLEMS problems; `stage_seconds` within bounds; the subtasks setting at most the
## stages; two different non-empty RNG purposes.
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if start == null:
		found.append("ShipEngine %s has no start station kind" % id)
	if kinds.is_empty():
		found.append("ShipEngine %s has no problem kinds" % id)
	var ids: Array[StringName] = []
	for kind: ProblemKind in kinds:
		if kind == null:
			found.append("ShipEngine %s has an empty problem kind" % id)
			continue
		if ids.has(kind.id):
			found.append("ShipEngine %s has two problem kinds with the id %s" % [id, kind.id])
		ids.append(kind.id)
		found.append_array(kind.check(mode))
	for kind: StationKind in station_kinds():
		if not _has_use_rule(kind):
			found.append(
				(
					"ShipEngine %s: station kind %s has no Interact rule with UseStation"
					% [id, kind.id]
				)
			)
		if kind.spawn_tag == aboard_tag:
			found.append(
				(
					"ShipEngine %s: station kind %s spawns on the aboard tag %s"
					% [id, kind.id, aboard_tag]
				)
			)
	if aboard_tag.is_empty():
		found.append("ShipEngine %s has no aboard tag" % id)
	_check_stages(mode, found)
	if when_rng.is_empty() or what_rng.is_empty() or when_rng == what_rng:
		found.append("ShipEngine %s needs two different RNG purposes" % id)
	append_found(
		found,
		[out_of_bounds("ShipEngine %s stage_seconds" % id, stage_seconds, MIN_SECONDS, MAX_SECONDS)]
	)
	return found


func _check_stages(mode: GameMode, found: PackedStringArray) -> void:
	if stage_problems.is_empty() or stage_problems.size() > MAX_STAGES:
		found.append(
			"ShipEngine %s has %d stages, outside 1 to %d" % [id, stage_problems.size(), MAX_STAGES]
		)
	for count: int in stage_problems:
		append_found(
			found,
			[out_of_bounds("ShipEngine %s stage problems" % id, count, 1, MAX_STAGE_PROBLEMS)]
		)
	var spec := (
		mode.find_setting(subtasks_setting)
		if mode != null and not subtasks_setting.is_empty()
		else null
	)
	if spec != null and spec.is_number() and spec.max_value > stage_problems.size():
		found.append(
			(
				"ShipEngine %s: setting %s goes up to %d, above its %d stages"
				% [id, subtasks_setting, spec.max_value, stage_problems.size()]
			)
		)


## Whether the level being entered has the start marker, two aboard corners and every kind's
## sites; the lobby's fit check (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext) -> bool:
	if not has_layout(ctx, "ShipEngine"):
		return false
	var needs: Dictionary[StringName, int] = {start.spawn_tag: 1, aboard_tag: 2}
	for kind: ProblemKind in kinds:
		needs[kind.site.spawn_tag] = kind.site_count
	var short := short_markers(ctx.layout, needs)
	if short.is_empty():
		return true
	var words := PackedStringArray()
	for tag: StringName in short:
		words.append("%d %s markers of %d" % [short[tag], tag, needs[tag]])
	ctx.error("ShipEngine: the map is short of markers: %s" % ", ".join(words))
	return false


static func _has_use_rule(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT:
			continue
		for effect: RuleEffect in rule.effects:
			if effect is UseStation:
				return true
	return false


static func _add_scripts(into: Array[Script], more: Array[Script]) -> void:
	for script: Script in more:
		if not into.has(script):
			into.append(script)
