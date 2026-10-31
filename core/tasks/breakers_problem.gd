class_name BreakersProblem
extends ProblemKind
## The ship engine's tripped breakers (ARCHITECTURE §9.3, §9.5.27; GDD §8 "Tripped breakers", PR
## #1269): its sites are the two breaker boards, one in each corridor, and its one fixture the
## breakers, four on each board (red, yellow, green, blue), eight in all. Each breaker belongs to
## the board nearest it. A problem holds one board or both (EngineProblemOpened's stations: what
## the console's hologram blinks) and trips `trips` breakers of them in an order drawn from
## `order_rng`: in `side_changes + 1` runs as near equal as can be, alternating boards from a
## drawn one, each run's breakers drawn without repeat (GDD's placeholders: 2 on one board, then 4
## with one change of side, then 6 alternating sides). BreakerChain names the order to every
## peer: the hologram plays it to whoever looks (GDD §8).
##
## The chain: the next breaker of the order is switched on (a use of its station; BreakerChain
## counts it on) when it is the first, or while the one before it is green: from `ramp_seconds` to
## `ramp_seconds + green_seconds` after that one went on (its lamp yellow, then green). Too late:
## the one before trips again (BreakerChain, one less on) and the chain goes on from the breaker
## before that one, whose green starts again then (so a chain left alone unwinds one breaker per
## green window). A short circuit, a tripped breaker out of order or one switched while the one
## before is still yellow, knocks the presser down (LifeRules.knock_down) and changes nothing else
## (GDD: the tripped breakers stay tripped). The last of the order on: fixed. A board, a breaker
## that is not tripped and one already on take no use (`unavailable`).

## The breakers on each board (GDD §8: red, yellow, green, blue).
const BREAKERS_PER_BOARD := 4
## The bounds of `ramp_seconds` and `green_seconds`.
const MIN_RAMP_SECONDS := 0.0
const MIN_GREEN_SECONDS := 0.05
const MAX_CHAIN_SECONDS := 60.0

## Per stage (1 up; past the end the last), how many breakers a problem trips (GDD §8's
## placeholders 2, 4, 6).
@export var trips := PackedInt32Array()
## Per stage, how many times its order changes board (GDD §8's placeholders 0, 1, and alternating
## sides: 5). With 0 a problem takes one board, else both when both are free.
@export var side_changes := PackedInt32Array()
## The yellow ramp of a breaker switched on, before its lamp is green (the GDD gives no number).
@export var ramp_seconds := 0.0
## How long a breaker's lamp stays green (the GDD gives no number: long enough for one player to
## run across the hall to the other board).
@export var green_seconds := 0.0
## The RNG purpose of the orders.
@export var order_rng: StringName = &"engine_breakers"


## A breakers problem's own state (EngineProblem.data).
class Data:
	extends RefCounted
	## The tripped breaker stations, in the order to switch them on.
	var order := PackedInt32Array()
	## Per breaker of `order`, the host tick it went on (its green measured from it), or -1.
	var on_since := PackedInt32Array()
	## The index in `order` of the next breaker to switch on.
	var next := 0


func ramp_ticks() -> int:
	return maxi(0, Ticks.from_seconds(ramp_seconds))


func green_ticks() -> int:
	return maxi(1, Ticks.from_seconds(green_seconds))


## Stage `stage`'s index in `trips` and `side_changes` (the last past their end).
func stage_index(stage: int) -> int:
	return clampi(stage - 1, 0, trips.size() - 1)


## One board at a stage without a change of side, or with one board free (GDD: easy first); both
## boards otherwise.
func claim(
	_ctx: MatchContext,
	_task: MatchTask,
	free: PackedInt32Array,
	stage: int,
	rng: RandomNumberGenerator
) -> PackedInt32Array:
	if free.size() < 2 or side_changes.is_empty() or side_changes[stage_index(stage)] == 0:
		return PackedInt32Array([free[rng.randi_range(0, free.size() - 1)]])
	return free.slice(0, 2)


func opened(ctx: MatchContext, task: MatchTask, problem: EngineProblem) -> void:
	var data := Data.new()
	problem.data = data
	var groups := breakers_of(ctx.state, task)
	var left: Array[PackedInt32Array] = []
	for board: int in problem.stations:
		var group: PackedInt32Array = groups.get(board, PackedInt32Array())
		left.append(group.duplicate())
	var at := stage_index(problem.stage)
	var changes := side_changes[at] if problem.stations.size() > 1 else 0
	var available := 0
	for breakers: PackedInt32Array in left:
		available += breakers.size()
	# One board free on a later stage: that stage's breakers on it, as many as it has.
	var count := mini(trips[at], available)
	var rng := ctx.rng(order_rng)
	var side := rng.randi_range(0, left.size() - 1)
	for run: int in runs_of(count, changes):
		for _i in run:
			if left[side].is_empty():
				side = (side + 1) % left.size()
			if left[side].is_empty():
				ctx.error("BreakersProblem: problem %d has no breaker left to trip" % problem.id)
				break
			var pick := rng.randi_range(0, left[side].size() - 1)
			data.order.append(left[side][pick])
			left[side].remove_at(pick)
		side = (side + 1) % left.size()
	data.on_since.resize(data.order.size())
	data.on_since.fill(-1)
	ctx.emit(BreakerChainEvent.new(problem.id, data.order.duplicate(), 0, -1))


## `count` breakers in `changes + 1` runs as near equal as can be, the longer ones first.
static func runs_of(count: int, changes: int) -> PackedInt32Array:
	var runs := PackedInt32Array()
	var parts := clampi(changes + 1, 1, maxi(1, count))
	for j in parts:
		runs.append(count / parts + (1 if j < count % parts else 0))
	return runs


## The breaker stations of each board (board station id -> the ids of its breakers, ascending):
## each breaker belongs to the board nearest it, a tie to the lower id.
func breakers_of(state: MatchState, task: MatchTask) -> Dictionary[int, PackedInt32Array]:
	var found: Dictionary[int, PackedInt32Array] = {}
	var task_state := task.state as ShipEngine.State
	var k := (task.type as ShipEngine).kinds.find(self)
	if k < 0:
		return found
	var boards := task_state.sites[k]
	for board: int in boards:
		found[board] = PackedInt32Array()
	for station_id: int in task_state.stations:
		if task_state.kind_of.get(station_id, -1) != k or boards.has(station_id):
			continue
		var spot := state.stations[station_id].position
		var nearest := -1
		var nearest_far := INF
		for board: int in boards:
			var far := spot.distance_squared_to(state.stations[board].position)
			if far < nearest_far:
				nearest = board
				nearest_far = far
		if nearest >= 0:
			found[nearest].append(station_id)
	return found


## The open problem of this kind whose order holds the breaker `station_id`, or null.
func tripped_by(task: MatchTask, station_id: int) -> EngineProblem:
	for problem: EngineProblem in (task.state as ShipEngine.State).problems:
		if problem.kind == self and (problem.data as Data).order.has(station_id):
			return problem
	return null


func use_problem(
	_ctx: MatchContext, task: MatchTask, station: StationState, _problem: EngineProblem
) -> StringName:
	var found := tripped_by(task, station.id)
	if found == null:
		return StationUsable.UNAVAILABLE
	var data := found.data as Data
	if data.on_since[data.order.find(station.id)] >= 0:
		return StationUsable.UNAVAILABLE
	return &""


func use_station(
	ctx: MatchContext, task: MatchTask, station: StationState, _problem: EngineProblem
) -> void:
	var found := tripped_by(task, station.id)
	if found == null:
		return  # use_problem refused it.
	var data := found.data as Data
	var index := data.order.find(station.id)
	if index != data.next or not _in_green(data, ctx.tick):
		var presser := ctx.state.player(ctx.actor)
		if presser != null and presser.is_alive():
			LifeRules.knock_down(ctx, ctx.actor)
		return
	data.on_since[index] = ctx.tick
	data.next += 1
	ctx.emit(chain_of(found))
	if data.next == data.order.size():
		ShipEngine.fix(ctx, task, found)


## Whether the next breaker may go on at `tick`: the first always, else while the one before is
## green.
func _in_green(data: Data, tick: int) -> bool:
	if data.next == 0:
		return true
	var since := tick - data.on_since[data.next - 1]
	return since >= ramp_ticks() and since <= ramp_ticks() + green_ticks()


func tick_problem(ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	var data := problem.data as Data
	if data.next == 0 or ctx.tick - data.on_since[data.next - 1] <= ramp_ticks() + green_ticks():
		return
	data.next -= 1
	data.on_since[data.next] = -1
	if data.next > 0:
		# The one before is green from now: the chain goes on from it.
		data.on_since[data.next - 1] = ctx.tick - ramp_ticks()
	ctx.emit(chain_of(problem))


## The chain of the breakers problem `problem` as it is now (BreakerChain).
static func chain_of(problem: EngineProblem) -> BreakerChainEvent:
	var data := problem.data as Data
	var since := data.on_since[data.next - 1] if data.next > 0 else -1
	return BreakerChainEvent.new(problem.id, data.order.duplicate(), data.next, since)


func use_emits() -> Array[Script]:
	return [BreakerChainEvent, KnockedDownEvent, CorrectionEvent, LaunchBodyEvent]


func emits() -> Array[Script]:
	return [BreakerChainEvent]


## Exactly `site_count` boards and BREAKERS_PER_BOARD breakers on each.
func add_demands(into: Demands) -> void:
	if site != null:
		into.add_markers(site.spawn_tag, site_count, true)
	if fixtures.size() == 1 and fixtures[0] != null:
		into.add_markers(fixtures[0].spawn_tag, site_count * BREAKERS_PER_BOARD, true)


## ProblemKind's check; one fixture, the breakers; `trips` and `side_changes` of one size, at least
## 1, each stage's breakers fitting its boards; the chain's seconds within bounds; an RNG purpose.
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if fixtures.size() != 1:
		found.append("problem kind %s needs one fixture, the breakers" % id)
	if trips.is_empty() or trips.size() != side_changes.size():
		found.append("problem kind %s needs trips and side_changes of one size" % id)
	else:
		for i in trips.size():
			_check_stage(found, i)
	if order_rng.is_empty():
		found.append("problem kind %s has no order_rng" % id)
	append_found(
		found,
		[
			out_of_bounds(
				"problem kind %s ramp_seconds" % id,
				ramp_seconds,
				MIN_RAMP_SECONDS,
				MAX_CHAIN_SECONDS
			),
			out_of_bounds(
				"problem kind %s green_seconds" % id,
				green_seconds,
				MIN_GREEN_SECONDS,
				MAX_CHAIN_SECONDS
			),
		]
	)
	return found


## Stage i's trips: at least 1; its changes 0 up to trips - 1, none with one board; each board's
## share at most BREAKERS_PER_BOARD.
func _check_stage(found: PackedStringArray, i: int) -> void:
	var count := trips[i]
	var changes := side_changes[i]
	if count < 1 or changes < 0 or changes > count - 1 or (changes > 0 and site_count < 2):
		found.append(
			"problem kind %s stage %d trips %d with %d side changes" % [id, i + 1, count, changes]
		)
		return
	var runs := runs_of(count, changes)
	var first := 0
	for j in runs.size():
		if j % 2 == 0:
			first += runs[j]
	if first > BREAKERS_PER_BOARD or count - first > BREAKERS_PER_BOARD:
		found.append(
			(
				"problem kind %s stage %d trips more than %d breakers on a board"
				% [id, i + 1, BREAKERS_PER_BOARD]
			)
		)
