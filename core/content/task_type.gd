class_name TaskType
extends ContentPart
## How tasks are dealt and done (ARCHITECTURE §9.3): a class with settings, not composed rules,
## because a task type's deal and its check depend on each other. A new task type is one script:
## this class with its TaskState as an inner class. The MVP's is Delivery (2f); ZoneTask
## (#647) is the second, and the first that ticks.
##
## Tasks are shared (the engineer's decision of 2026-09-30, #79): nobody owns a task, and any
## living player does any subtask. A match deals at most one task of each type: DealTasks draws
## the types and calls deal() once per drawn type, in the mode's order; Match calls on_fact() for
## every fact, after the mode's reactions and in the mode's order; TaskTicks (2f) calls tick()
## when has_tick(). Each type reads its own subtasks setting, `subtasks_setting` (Delivery:
## `packages`), which every type has (#256's shared part, the Generator ADR's G0, #795).

@export var id: StringName
@export var display_name: String
## What a player does for a task of this type, in a sentence or two: the task screen shows it
## (vision revision 1, the Tab task screen) with the task's shared progress (TaskState). Every
## client reads it from its own copy of the mode, so it never travels. Empty fails the mode check.
@export_multiline var description: String
## The paths of the mode's maps this type plays on (the Generator ADR's GE15, #803); empty, the
## default, means every map. DealTasks draws only the types that play on the match's map, and the
## demands (the fit check, LayoutCheck) ask a map only for the markers of its own types. The mode
## check refuses a path that is not one of the mode's maps.
@export var maps: PackedStringArray = PackedStringArray()
## The type's own subtasks setting (#256's shared part, the Generator ADR's §6.1, #795): the id of
## a whole-number SettingSpec of the mode, one lobby control, that deal() reads for the number of
## subtasks of its one task (Delivery's packages, the zone task's zones, the Generator's active
## switches, ...). Every type has one: check() refuses it empty and refuses a setting that goes
## below 0 (ModeCheck checks it names a declared whole-number setting, as every `*_setting`); a
## type adds only its own bound (the Generator's `switches`).
@export var subtasks_setting: StringName


## A fresh state for one task of this type.
func new_state() -> TaskState:
	return TaskState.new()


## Deals one shared task of this type into ctx.state.tasks (MatchState.add_task), with a state
## from new_state(), and places what it needs. Draws only from the RNG purposes this type names.
func deal(_ctx: MatchContext) -> void:
	pass


## This type's check of a fact (Delivery on `item_rested`), for its own tasks.
func on_fact(_ctx: MatchContext) -> void:
	pass


func has_tick() -> bool:
	return false


func tick(_ctx: MatchContext) -> void:
	pass


## What dealing one task of this type with these settings and `players` players needs of the map
## (§9.4); DealTasks sums these over the types a draw could pick.
func add_demands(_settings: Dictionary[StringName, int], _players: int, _into: Demands) -> void:
	pass


## What is wrong with `layout`, a map this type may be dealt on, beyond its marker counts (the car
## repair ADR's RE14, #807: CarRepair's short axis), as HostTexts: at most
## most_layout_problems(). FitCheck.shortfalls appends them, so `all_ready` holds back on such a
## map before Match starts. Read only from `layout`; none by default.
func layout_problems(_layout: LevelLayout) -> Array[HostText]:
	return []


## The most HostTexts layout_problems() returns: WireBudget sizes SettingsChanged's shortfalls
## with it. 0 by default.
func most_layout_problems() -> int:
	return 0


## Whether `ctx` has the layout of the level being entered; else reports "`task`: no layout for
## the level being entered". The first step of every type's fit at deal() (#1254); the lobby's fit
## check (§9.4) keeps a match from getting there without one.
static func has_layout(ctx: MatchContext, task: String) -> bool:
	if ctx.layout != null:
		return true
	ctx.error("%s: no layout for the level being entered" % task)
	return false


## The tags of `needs` (a marker count per spawn tag) `layout` has fewer markers of than needed,
## each with the count it has, in `needs` order: what a type's fit at deal() reports in its own
## words (#1254). Empty when the layout has them all.
static func short_markers(
	layout: LevelLayout, needs: Dictionary[StringName, int]
) -> Dictionary[StringName, int]:
	var short: Dictionary[StringName, int] = {}
	for tag: StringName in needs:
		var have := layout.count(tag)
		if have < needs[tag]:
			short[tag] = have
	return short


## The spawn tags of the level markers where this type's items may lie (Delivery: its package
## kind's), for the map screen's zones (#253): the client lights each room that holds a marker of
## such a tag. Level data every client has, never a place a deal chose. None by default.
func item_spawn_tags() -> Array[StringName]:
	return []


## The station kinds this type places, one per StationKind property, in property order (the
## delivery-by-meaning ADR's DE4, #827): the one finder every reader of a type's kinds asks
## (Stations, MarkerReader.floor_tags_of, ModeCheck's station check, CircleViews, WireBudget). By
## default the reflection over the type's stored properties; a type that holds its kinds some
## other way (a list, a built kind) overrides it, and its kinds are then snapped, checked and
## drawn like any other.
func station_kinds() -> Array[StationKind]:
	var found: Array[StationKind] = []
	for property: Dictionary in get_property_list():
		if ((property["usage"] as int) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = get(property["name"] as String)
		if value is StationKind:
			found.append(value as StationKind)
	return found


## The event classes this type can emit (§9.2).
func emits() -> Array[Script]:
	return []


## The outcomes on_fact() or tick() can report through MatchContext.report_outcome: ModeCheck
## requires a row for each from every phase (on_fact runs in all of them, §9.1).
func reported_outcomes() -> Array[StringName]:
	return []


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a task type has no id")
	if description.strip_edges().is_empty():
		found.append("task type %s has no description" % id)
	_check_subtasks_setting(mode, found)
	for map: String in maps:
		if mode != null and not mode.maps.has(map):
			found.append(
				"task type %s lists the map %s, which is not one of the mode's maps" % [id, map]
			)
	for reason: StringName in use_reasons():
		var text := ""
		if not ModeCheck.is_wire_id(reason):
			text = 'task type %s lists the use reason "%s", which is not an id: 1 to %d characters'
			text += " of a-z, 0-9 and _ (the wire's alphabet)"
			found.append(text % [id, reason, ModeCheck.MAX_ID_LENGTH])
		elif not StationUsable.REASONS.has(reason):
			text = "task type %s lists the use reason %s, which is not one of StationUsable.REASONS"
			found.append(text % [id, reason])
	return found


## Whether this type plays on `map` (`maps` empty: every map). An empty `map` is no map at all:
## every type (DealTasks.pool_of without a map, for the lobby's bounds, #79).
func plays_on(map: String) -> bool:
	return map.is_empty() or maps.is_empty() or maps.has(map)


## Why this type refuses a use of `station`, a placed station of its kind, by the actor of `ctx`
## now (StationUsable, the Generator ADR's GE2, #796), or empty when it takes it. Only a reason
## use_reasons() lists: each says only public state of a station the actor has in reach and in
## sight (AtStation and StationInSight run before StationUsable) and what the actor holds, and
## never reads a role. A query that changes nothing: StationUsable may ask it twice in one step.
## `task` is the type's task (null when the deal dealt none). By default every use is refused
## `unavailable`: a type whose stations nobody uses takes no use.
func use_problem(_ctx: MatchContext, _task: MatchTask, _station: StationState) -> StringName:
	return StationUsable.UNAVAILABLE


## Every reason use_problem() may return (the cooking ADR's CE11, #780): StationUsable refuses a
## use with one of them, and with `unavailable` (a match error) for any other. ModeCheck refuses
## one outside the wire's alphabet or StationUsable.REASONS. By default `unavailable` alone.
func use_reasons() -> Array[StringName]:
	return [StationUsable.UNAVAILABLE]


## Uses `station` (UseStation, after StationUsable passed): the type writes its own task state
## (§9.1) and emits only the events use_emits() lists. Nothing by default.
func use_station(_ctx: MatchContext, _task: MatchTask, _station: StationState) -> void:
	pass


## The event classes use_station() can emit (the Generator's SwitchChanged, ButtonPressed and its
## progress event): ModeCheck counts them for a UseStation in a rule of this type's station kinds,
## so a role-gated station rule whose use reaches everyone warns (§9.2). None by default.
func use_emits() -> Array[Script]:
	return []


## The tier of `item` under its kind's cap (C1's GiveItem; the photo ADR's PE10, #782): at the cap
## the loose item of the lowest tier vanishes first, an item's tier the highest answer of every
## dealt task type, then CE3's order (the earliest rest tick, then the lowest id). A type ranks
## only what everyone already knows (which item lies in its station, which one has shots), never a
## hidden fact: ItemVanished tells everyone which one went. A query that changes nothing. 0 by
## default.
func cap_tier(_state: MatchState, _item: ItemState) -> int:
	return 0


## A HoldStation `channel` on `station`, a placed station of this type's kind, started (it is
## running: Channels.of_actor finds it; the car repair ADR's RE1 to RE3, #805). The type writes its
## own task state and emits only the events hold_emits() lists. `task` as in use_problem(). Nothing
## by default.
func hold_started(
	_ctx: MatchContext, _task: MatchTask, _station: StationState, _channel: Channel
) -> void:
	pass


## `channel` on `station` stopped before completing, for any reason: one of its conditions failed on
## a re-check, StopRaise or another applied action of its actor, its actor hit (when
## HoldStation.hit_stops), downed, dying or leaving, or its phase ending (Channel.phase_ended set:
## the car comes down without a kill, RE4). It is no longer running. Nothing by default.
func hold_stopped(
	_ctx: MatchContext, _task: MatchTask, _station: StationState, _channel: Channel
) -> void:
	pass


## `channel` on `station` ran its seconds and completed (an endless hold never does, RE3). It is no
## longer running. Nothing by default.
func hold_completed(
	_ctx: MatchContext, _task: MatchTask, _station: StationState, _channel: Channel
) -> void:
	pass


## Whether this type's tick() can knock a player down (LifeRules.knock_down: the ship engine's
## blast, #1453). A downed player bleeds out into death, so ModeCheck (KillCheck) requires
## LifeTicks with a Respawn in every phase that lists TaskTicks. False by default.
func knocks_down() -> bool:
	return false


## Whether this type can kill a player (LifeRules.kill through kill_later: the car's drop; the car
## repair ADR's RE6, #806). ModeCheck then requires LifeTicks with a Respawn in every phase that
## accepts Interact, so a dead player always comes back. False by default.
func kills() -> bool:
	return false


## The event classes hold_started(), hold_stopped() and hold_completed() can emit: ModeCheck counts
## them for a HoldStation as it counts use_emits() for a UseStation (§9.2's role-reveal warning).
## None by default.
func hold_emits() -> Array[Script]:
	return []


## The shared check of `subtasks_setting` (G0, #795): present, and from at least 0 when the mode
## declares it as a number (ModeCheck reports a setting it does not declare, or a set of ids). The
## errors name the type's class (Delivery, ZoneTask, ...), as each type's own checks do.
func _check_subtasks_setting(mode: GameMode, found: PackedStringArray) -> void:
	var script := get_script() as Script
	var label := script.get_global_name() if script != null else &""
	var kind := String(label) if not label.is_empty() else "task type"
	if subtasks_setting.is_empty():
		found.append("%s %s has no subtasks_setting" % [kind, id])
		return
	var spec := mode.find_setting(subtasks_setting) if mode != null else null
	if spec != null and spec.is_number() and spec.min_value < 0:
		found.append("%s %s: setting %s goes below 0" % [kind, id, subtasks_setting])
