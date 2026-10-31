class_name ProblemKind
extends ContentPart
## One kind of the ship engine's problems (ARCHITECTURE §9.3, §9.5.27; GDD §8: the overheat at the
## throat's gill sets, the tripped breakers, the spent cartridge): the content part ShipEngine's
## `kinds` list. The engine owns the stages, the spawns, each problem's timer, the blast and the
## bar; a kind owns which of its sites a new problem takes, what a use of its stations does, its
## own per-problem data (EngineProblem.data) and its own events. Every hook has a default, so a
## kind overrides only what it needs; this base is the whole interface part 2 fills (#1225).
##
## Its stations: one `site` station on every marker of `site.spawn_tag` (exactly `site_count` of
## them: the map's demands ask for that many), where its problems open, and one station of each of
## `fixtures` on every marker of its tag, never a problem's site (the crystal's chargers). Each is a
## StationKind with the Interact rule whose effect is UseStation, so a use reaches use_problem()
## and use_station() through ShipEngine. Station ids: after the engine's console, per kind in
## ShipEngine.kinds order, its sites then each fixture's, each in level order.
##
## Stateless, as every part (ContentPart): what changes lives in the problem (EngineProblem) or in
## ShipEngine.State. A hook draws randomness only from `rng` it is handed (the engine's
## `what_rng` purpose) or from ctx.rng with a purpose of its own data.

## The fewest and the most seconds of a problem's timer.
const MIN_SECONDS := 0.05
const MAX_SECONDS := 600.0

@export var id: StringName
## The problem's timer: from its opening to the blast unless it is fixed (GDD §8's placeholders:
## an overheat 10 s, the breakers 30 s, a cartridge 30 s), converted once to host ticks, at least
## 1. The neutral default is out of bounds on purpose: the data sets it.
@export var seconds := 0.0
## The station kind of its sites, where its problems open.
@export var site: StationKind
## How many `site` markers every map it plays on holds, exactly (GDD §8: the gill sets 2, the
## boards 2, the sockets 4). At least 1.
@export var site_count := 0
## Station kinds placed on every marker of their tags that are never a problem's site (the
## crystal's chargers). None by default.
@export var fixtures: Array[StationKind] = []


## The station ids a new problem of this kind takes, from `free`: the ids of its sites without an
## open problem, ascending, never empty when the engine asks. At least 1 and at most
## ShipEngine.MAX_PROBLEM_STATIONS of them, each from `free`. Any other answer is a match error,
## and the engine then opens the problem on the first free site anyway: a problem always opens, so
## claim should keep no state of its own. `stage` is the engine's stage, 1 up (the breakers trip
## more later). By default one site, drawn from `rng`.
func claim(
	_ctx: MatchContext,
	_task: MatchTask,
	free: PackedInt32Array,
	_stage: int,
	rng: RandomNumberGenerator
) -> PackedInt32Array:
	return PackedInt32Array([free[rng.randi_range(0, free.size() - 1)]])


## `problem` just opened (the engine emitted EngineProblemOpened first): the kind sets
## `problem.data` and emits its own events. Nothing by default.
func opened(_ctx: MatchContext, _task: MatchTask, _problem: EngineProblem) -> void:
	pass


## Each host tick while `problem` is open, before its timer is checked (the gills' white bar, the
## breakers' chain, the charger). It may fix it (ShipEngine.fix). Nothing by default.
func tick_problem(_ctx: MatchContext, _task: MatchTask, _problem: EngineProblem) -> void:
	pass


## The blast took `problem` (it is no longer open; no EngineProblemFixed goes out): the kind
## clears its own state of it (the tripped breakers reset, a crystal in a hand). Nothing by default.
func cleared(_ctx: MatchContext, _task: MatchTask, _problem: EngineProblem) -> void:
	pass


## Why a use of `station`, one of this kind's stations, is refused now, or empty when it is taken
## (TaskType.use_problem's rules: only a reason use_reasons() lists, public state only, never a
## role, a query that changes nothing). `problem` is the open problem holding `station`, or null
## (an idle site, a fixture). By default only a site with an open problem takes a use.
func use_problem(
	_ctx: MatchContext, _task: MatchTask, _station: StationState, problem: EngineProblem
) -> StringName:
	return StationUsable.UNAVAILABLE if problem == null else &""


## Every reason use_problem() may return. By default `unavailable` alone.
func use_reasons() -> Array[StringName]:
	return [StationUsable.UNAVAILABLE]


## Uses `station` (after use_problem() took it); `problem` as in use_problem(). A fix calls
## ShipEngine.fix(ctx, task, problem). Nothing by default.
func use_station(
	_ctx: MatchContext, _task: MatchTask, _station: StationState, _problem: EngineProblem
) -> void:
	pass


## The event classes use_station() can emit, but EngineProblemFixed (ShipEngine.fix's, which the
## engine lists). None by default.
func use_emits() -> Array[Script]:
	return []


## The event classes opened() and tick_problem() can emit. None by default.
func emits() -> Array[Script]:
	return []


## The station kinds this kind places: `site`, then `fixtures`, in data order (nulls left out).
func station_kinds() -> Array[StationKind]:
	var found: Array[StationKind] = []
	if site != null:
		found.append(site)
	for fixture: StationKind in fixtures:
		if fixture != null:
			found.append(fixture)
	return found


## What a map needs for this kind (§9.4): exactly `site_count` site markers and at least one
## marker of each fixture's tag.
func add_demands(into: Demands) -> void:
	if site != null:
		into.add_markers(site.spawn_tag, site_count, true)
	for fixture: StationKind in fixtures:
		if fixture != null:
			into.add_markers(fixture.spawn_tag, 1)


## An id; `seconds` within bounds; a site kind; `site_count` at least 1; no null fixture.
## ShipEngine checks the station kinds' rules and spawn tags across every kind.
func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a ship engine problem kind has no id")
	if site == null:
		found.append("problem kind %s has no site station kind" % id)
	if site_count < 1:
		found.append("problem kind %s has %d sites, fewer than 1" % [id, site_count])
	if fixtures.has(null):
		found.append("problem kind %s has an empty fixture" % id)
	append_found(
		found, [out_of_bounds("problem kind %s seconds" % id, seconds, MIN_SECONDS, MAX_SECONDS)]
	)
	return found
