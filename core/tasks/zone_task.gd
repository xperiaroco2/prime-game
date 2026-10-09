class_name ZoneTask
extends TaskType
## The zone task (#36; ARCHITECTURE §3.3, §9.5; the zone task ADR, 2026-10-09): one shared task of
## `subtasks_setting` zones, each done once living players have stood in it for `seconds` in all.
## Nobody owns it: any living player of any role works any zone (#79, ZD3).
##
## The deal (DealTasks calls deal() when the draw picks it): N zones, N the subtasks setting,
## whatever the player count, on distinct random `zone.spawn_tag` markers, each with its own random
## palette colour (colours never repeat), both from the one purpose `zones_rng`. Station ids follow
## spawn-point order, and zone i is subtask i. StationPlaced goes out in id order. With N = 0 the
## task has no subtasks, and so is done.
##
## The tick (TaskTicks, in each phase that lists it: Round in the base mode), for each undone zone
## in station-id order: the zone counts when at least one player, in peer-id order, is living
## (life ALIVE, any role), has its feet (its last accepted claim) inside the zone's cylinder
## (StationState.contains), and that claim is at most STALE_TICKS host ticks old
## (MovementRule.claim_age, ZE10): a client that stops claiming stops counting. A counting zone
## gains one tick, however many stand in it (ZD4); leaving pauses it, and it keeps its ticks (ZD2).
## A zone whose ticks reach needed_ticks() is done: ZoneProgress first, then Tasks.subtask_done
## (ZE5). Nothing else stops or resets a zone (ZD9): carrying, using, a hit that does not knock
## down.
##
## ZoneProgress (ZE4) goes out when a zone's counting changed since its last one, at most once per
## WINDOW_TICKS: a change inside the window goes out at its end with the state of that tick, even
## when counting is back where it was (the ticks gained or lost meanwhile differ from what a client
## extrapolated). Done goes out in its own tick.
##
## Emits: StationPlaced (everyone) in the deal; ZoneProgress (everyone) on a change; ZoneProgress,
## TaskState and TaskProgress (everyone) on a done zone. Raises subtask_done on a done zone.

## The fewest host ticks between two ZoneProgress events of one zone, but for its done (ZE4).
## A placeholder, not a decision.
const WINDOW_TICKS := 5
## The oldest a player's last accepted claim may be for it to count (ZE10): the lost-claim
## tolerance the push allowance already accepts (MovementRule.PUSH_TICKS).
const STALE_TICKS := MovementRule.PUSH_TICKS
## The bounds of `seconds`: ChannelEffect.seconds' (ZE1).
const MIN_SECONDS := 0.05
const MAX_SECONDS := 600.0


## The zone task's state (§9.1): per subtask, in order, its zone, the ticks it counted, whether it
## counts now, whether it is done, and its ZoneProgress bookkeeping. Only ZoneTask reads and writes
## it.
class State:
	extends TaskState

	## Station ids, one per subtask, ascending.
	var stations := PackedInt32Array()
	## Host ticks counted so far.
	var ticks := PackedInt32Array()
	## Whether the zone counted in the last tick it ran.
	var counting: Array[bool] = []
	var done: Array[bool] = []
	## The host tick of the zone's last ZoneProgress (-WINDOW_TICKS before any).
	var sent_at := PackedInt32Array()
	## Whether its counting changed since its last ZoneProgress.
	var changed: Array[bool] = []

	func done_count() -> int:
		return done.count(true)

	func total() -> int:
		return stations.size()


## The station kind of the zones: spawn tag, radius, height and colour palette.
@export var zone: StationKind
## The zone task's own subtasks setting: its zones.
@export var subtasks_setting: StringName
## How long living players must stand in a zone, in all (ZD1, ZD7: data, not a lobby setting).
## 0.05 to 600; converted once to host ticks (needed_ticks). The neutral default is out of bounds
## on purpose: the data sets it, so the mode check refuses a zone task that forgot it.
@export var seconds := 0.0
## The RNG purpose of the zones' markers and colours (§3.3).
@export var zones_rng: StringName = &"zones"


func new_state() -> TaskState:
	return State.new()


func has_tick() -> bool:
	return true


## The host ticks a zone needs: `seconds` by the one rounding rule (Ticks), at least 1.
func needed_ticks() -> int:
	return maxi(1, Ticks.from_seconds(seconds))


func deal(ctx: MatchContext) -> void:
	var count := ctx.setting(subtasks_setting)
	if count <= 0:
		ctx.state.add_task(self)
		return
	if not _fits(ctx, count):
		return
	var spots := ctx.layout.positions(zone.spawn_tag)
	var markers := Tasks.pick(spots.size(), count, ctx.rng(zones_rng))
	var colours := RngStreams.shuffled_indices(zone.palette.size(), ctx.rng(zones_rng))
	var placed: Array[StationState] = []
	for i in count:
		placed.append(ctx.state.add_station(zone, spots[markers[i]], zone.palette[colours[i]]))
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	for station: StationState in placed:
		task_state.stations.append(station.id)
		task_state.ticks.append(0)
		task_state.counting.append(false)
		task_state.done.append(false)
		task_state.sent_at.append(-WINDOW_TICKS)
		task_state.changed.append(false)
	for station: StationState in placed:
		ctx.emit(StationPlacedEvent.new(station.id, zone.id, station.colour, station.position))


func tick(ctx: MatchContext) -> void:
	var needed := needed_ticks()
	for task_id: int in ctx.state.tasks:
		var task := ctx.state.tasks[task_id]
		if task.type != self:
			continue
		var task_state := task.state as State
		for i in task_state.stations.size():
			if not task_state.done[i]:
				_tick_zone(ctx, task, task_state, i, needed)


## One undone zone's tick: count, then done or its ZoneProgress.
func _tick_zone(
	ctx: MatchContext, task: MatchTask, task_state: State, index: int, needed: int
) -> void:
	var station: StationState = ctx.state.stations.get(task_state.stations[index])
	if station == null:
		ctx.error("ZoneTask: subtask %d has no station %d" % [index, task_state.stations[index]])
		return
	var counts := _anyone_inside(ctx, station)
	if counts != task_state.counting[index]:
		task_state.changed[index] = true
	task_state.counting[index] = counts
	if counts:
		task_state.ticks[index] += 1
	if task_state.ticks[index] >= needed:
		task_state.ticks[index] = needed
		task_state.counting[index] = false
		task_state.done[index] = true
		station.done = true
		ctx.emit(ZoneProgressEvent.new(station.id, needed, needed, false, ctx.tick))
		Tasks.subtask_done(ctx, task, {"subtask": index, "station": station.id})
		return
	if task_state.changed[index] and ctx.tick - task_state.sent_at[index] >= WINDOW_TICKS:
		task_state.changed[index] = false
		task_state.sent_at[index] = ctx.tick
		ctx.emit(
			ZoneProgressEvent.new(station.id, task_state.ticks[index], needed, counts, ctx.tick)
		)


## Whether a living player whose last accepted claim is at most STALE_TICKS old stands in
## `station`. Reads no role (ZD3): a public ZoneProgress must not tell who counts.
static func _anyone_inside(ctx: MatchContext, station: StationState) -> bool:
	for peer: int in ctx.state.peers():
		var player := ctx.state.player(peer)
		if player == null or not player.is_alive():
			continue
		var age := MovementRule.claim_age(ctx.state, peer, ctx.tick)
		if age < 0 or age > STALE_TICKS:
			continue
		if station.contains(player.position):
			return true
	return false


## As many `zone` markers and palette colours as zones (§9.4). The player count does not matter:
## the task is shared.
func add_demands(settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	if zone == null:
		return  # ModeCheck refuses such a mode.
	var count: int = maxi(settings.get(subtasks_setting, 0) as int, 0)
	into.add_markers(zone.spawn_tag, count)
	into.add_colours(zone, count)


func emits() -> Array[Script]:
	return [StationPlacedEvent, ZoneProgressEvent, TaskStateEvent, TaskProgressEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if zone == null:
		found.append("ZoneTask %s has no zone station kind" % id)
	if subtasks_setting.is_empty():
		found.append("ZoneTask %s has no subtasks_setting" % id)
	if zones_rng.is_empty():
		found.append("ZoneTask %s has an empty RNG purpose" % id)
	append_found(
		found, [out_of_bounds("ZoneTask %s seconds" % id, seconds, MIN_SECONDS, MAX_SECONDS)]
	)
	return found


## Whether the level being entered has the markers and the palette the colours for `count` zones;
## the lobby's fit check (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext, count: int) -> bool:
	if ctx.layout == null:
		ctx.error("ZoneTask: no layout for the level being entered")
		return false
	var markers := ctx.layout.count(zone.spawn_tag)
	var colours := zone.palette.size()
	if markers >= count and colours >= count:
		return true
	ctx.error(
		(
			"ZoneTask: %d zones need as many %s markers and colours; the map has %d, the palette %d"
			% [count, zone.spawn_tag, markers, colours]
		)
	)
	return false
