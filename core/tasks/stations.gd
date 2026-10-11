class_name Stations
extends RefCounted
## What the station parts share (ARCHITECTURE §9.3, §9.4; the Generator ADR's GE2): the placed
## station an intent names, the task type that owns a station kind, and that type's task. A
## station kind belongs to exactly one task type of the mode (ZE3: ModeCheck refuses a kind held
## twice), and a type deals at most one task per match (#79), so a placed station finds its task
## through its kind.


## The placed station the rule's intent names (its `station` field, Intents.FIELDS), or null: no
## intent, an intent with no `station` field, or an id that names no placed station (Match refuses
## that one `nothing_to_do` before any owner is tried).
static func target_of(ctx: MatchContext) -> StationState:
	if ctx.command == null or not names_station(ctx.command.kind):
		return null
	return ctx.state.stations.get(ctx.command.get_int("station", -1))


## Whether `intent` carries a `station` (Interact).
static func names_station(intent: StringName) -> bool:
	var fields: Dictionary = Intents.FIELDS.get(intent, {})
	return fields.has("station")


## The station kinds `type` holds, one per StationKind property, in property order.
static func kinds_of(type: TaskType) -> Array[StationKind]:
	var found: Array[StationKind] = []
	for property: Dictionary in type.get_property_list():
		if ((property["usage"] as int) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = type.get(property["name"] as String)
		if value is StationKind:
			found.append(value as StationKind)
	return found


## Every station kind of `mode`'s task types, each once, in the mode's order.
static func kinds_in(mode: GameMode) -> Array[StationKind]:
	var found: Array[StationKind] = []
	for type: TaskType in mode.task_types:
		if type == null:
			continue
		for kind: StationKind in kinds_of(type):
			if not found.has(kind):
				found.append(kind)
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
