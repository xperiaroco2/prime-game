class_name Stations
extends RefCounted
## What the station parts share (ARCHITECTURE §9.3, §9.4; the Generator ADR's GE2): the placed
## station an intent names, the task type that owns a station kind, and that type's task. A
## station kind belongs to exactly one task type of the mode (ZE3: ModeCheck refuses a kind held
## twice), and a type deals at most one task per match (#79), so a placed station finds its task
## through its kind.


## The placed station of the rule (Channels.station_of): its channel's while the channel's
## conditions are checked again or it ends (the car repair ADR's RE2: a hold passes its own
## re-check, where no intent is handled), else the one its intent names (its `station` field,
## Intents.FIELDS); null when there is none: no channel on a station and no intent, an intent with
## no `station` field, or an id that names no placed station (Match refuses that one
## `nothing_to_do` before any owner is tried).
static func target_of(ctx: MatchContext) -> StationState:
	return ctx.state.stations.get(Channels.station_of(ctx))


## Whether `intent` carries a `station` (Interact).
static func names_station(intent: StringName) -> bool:
	var fields: Dictionary = Intents.FIELDS.get(intent, {})
	return fields.has("station")


## The station kinds `type` holds, one per StationKind property, in property order.
static func kinds_of(type: TaskType) -> Array[StationKind]:
	return type.station_kinds()


## The names of the StationKind properties of `type`, in property order: what the default
## TaskType.station_kinds() reflects over (ModeCheck names a kind by its property).
static func property_names_of(type: TaskType) -> PackedStringArray:
	var names := PackedStringArray()
	for property: Dictionary in type.get_property_list():
		if ((property["usage"] as int) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = property["name"]
		if type.get(name) is StationKind:
			names.append(name)
	return names


## Every station kind of `mode`, each once: its task types' in the mode's order, then the kinds its
## phases place themselves (StationTicks, #1390: the lobby's tap, which no task type owns, so
## owner_of returns null for it) in phase and list order.
static func kinds_in(mode: GameMode) -> Array[StationKind]:
	var found: Array[StationKind] = []
	for type: TaskType in mode.task_types:
		if type == null:
			continue
		for kind: StationKind in kinds_of(type):
			if not found.has(kind):
				found.append(kind)
	for phase: PhaseSpec in mode.phases:
		if phase == null:
			continue
		for system: TickSystem in phase.tick_systems:
			var placed := system as StationTicks
			if placed != null and placed.kind != null and not found.has(placed.kind):
				found.append(placed.kind)
	return found


## The task type of `mode` that holds `kind`, or null.
static func owner_of(mode: GameMode, kind: StationKind) -> TaskType:
	for type: TaskType in mode.task_types:
		if type != null and kinds_of(type).has(kind):
			return type
	return null


## The match's task of `type`, or null when the deal dealt none.
static func task_of(state: MatchState, type: TaskType) -> MatchTask:
	for id: int in state.tasks:
		if state.tasks[id].type == type:
			return state.tasks[id]
	return null
