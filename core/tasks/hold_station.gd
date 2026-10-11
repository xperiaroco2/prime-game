class_name HoldStation
extends ChannelEffect
## A channel on the station the intent names (Interact; the car repair ADR's RE1 to RE5 and RE9,
## #805): the actor holds E there, for `seconds` (a fit at the car) or with no end (`endless`: the
## lift's hold). Started, stopped and completed, it hands the channel to the task type that owns
## the station's kind (TaskType.hold_started, hold_stopped, hold_completed), which alone writes its
## task state (§9.1) and emits only the events its hold_emits() lists; this effect emits nothing
## itself. Every tick its rule's conditions run again with the channel's station (Stations.target_of
## through Channels.station_of), so walking out of the cylinder or out of sight, or a use_problem
## the type now returns, stops it; AtStation also fails a timed hold whose actor stopped claiming
## (ZE10). StopRaise stops it (RE5), as does every other stop of Channels.
##
## Requires AtStation and ChannelFree in its rule (ModeCheck, RE9: one holder per station), and only
## on an intent that names a station (ModeCheck, as a UseStation). A phase that accepts its intent
## lists ChannelTicks (§9.1).

## Whether it never completes (RE3): only its stops end it. Then `seconds` stays 0 (the check).
@export var endless := false
## Whether a hit of its actor stops it (LifeRules.damage): a fit stops, the lift's hold goes on
## (RD10 (c)). A knockdown stops it either way.
@export var hit_stops := true


func is_endless() -> bool:
	return endless


func stops_on_hit() -> bool:
	return hit_stops


func required_conditions() -> Array[Script]:
	return [AtStation, ChannelFree]


func started(ctx: MatchContext, channel: Channel) -> void:
	var found := _owner(ctx, "started")
	if found.is_empty():
		return
	var type := found[0] as TaskType
	type.hold_started(ctx, Stations.task_of(ctx.state, type), found[1] as StationState, channel)


func stopped(ctx: MatchContext, channel: Channel) -> void:
	var found := _owner(ctx, "stopped")
	if found.is_empty():
		return
	var type := found[0] as TaskType
	type.hold_stopped(ctx, Stations.task_of(ctx.state, type), found[1] as StationState, channel)


func completed(ctx: MatchContext, channel: Channel) -> void:
	var found := _owner(ctx, "completed")
	if found.is_empty():
		return
	var type := found[0] as TaskType
	type.hold_completed(ctx, Stations.task_of(ctx.state, type), found[1] as StationState, channel)


func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if endless and seconds != 0.0:
		found.append(
			"HoldStation is endless and has seconds %s: an endless hold has none" % number(seconds)
		)
	return found


## The task type that owns the channel's station and the station, or empty with a rule error: a
## channel on no placed station of a type of the mode (ModeCheck keeps a HoldStation to intents
## that name a station, and Match refuses an id that names no placed one).
func _owner(ctx: MatchContext, what: String) -> Array:
	var station := Stations.target_of(ctx)
	var type: TaskType = null
	if station != null:
		type = Stations.owner_of(ctx.mode, station.kind)
	if type == null:
		ctx.error(
			"HoldStation %s: the channel runs on no station of a task type of the mode" % what
		)
		return []
	return [type, station]
