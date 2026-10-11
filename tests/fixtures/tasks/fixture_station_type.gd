class_name FixtureStationType
extends TaskType
## A task type with one station kind, `panel`, for the unit tests of Interact and the station parts
## (core/tasks/station_*.gd, use_station.gd; the Generator ADR's GE1 to GE4, #796). Its deal
## places one panel on each marker of the panel's spawn tag, in marker order, and adds its task.
## use_problem() returns `problem` (empty by default: every use is taken), so a test sets
## `unavailable`, or a reason outside StationUsable.REASONS to see it held to the list.
## The hold hooks (HoldStation; the car repair ADR's RE1 to RE4, #805) note "hold started",
## "hold stopped" (" phase_ended" when its phase ended) and "hold completed" with the station, the
## actor and the ticks run, to everyone (hold_emits(); nothing when `quiet`).
## use_station() emits a FixtureNoteEvent "used <station id> task <task id>" to everyone (its
## use_emits()), so a test sees which station a use reached and that the type got its task.

@export var panel: StationKind

## Why use_problem() refuses every use, or empty.
var problem: StringName = &""
## Whether use_emits() lists nothing (a use that reaches nobody), for ModeCheck's warning.
var quiet := false
## What kills() answers (the car repair ADR's RE6, #806), for ModeCheck's LifeTicks rule.
var killing := false


func _init() -> void:
	id = &"fixture_station"
	description = "Press the panels."


func deal(ctx: MatchContext) -> void:
	var placed: Array[StationState] = []
	for spot: Vector3 in ctx.layout.positions(panel.spawn_tag):
		placed.append(ctx.state.add_station(panel, spot, Color.ORANGE))
	ctx.state.add_task(self)
	for station: StationState in placed:
		ctx.emit(StationPlacedEvent.new(station.id, panel.id, station.colour, station.position))


func use_problem(_ctx: MatchContext, _task: MatchTask, _station: StationState) -> StringName:
	return problem


func use_station(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	var task_id := task.id if task != null else -1
	ctx.emit(FixtureNoteEvent.new("used %d task %d" % [station.id, task_id]))


func use_emits() -> Array[Script]:
	if quiet:
		return []
	return [FixtureNoteEvent]


## "hold started <station> by <actor> task <task id>" to everyone.
func hold_started(
	ctx: MatchContext, task: MatchTask, station: StationState, channel: Channel
) -> void:
	var task_id := task.id if task != null else -1
	ctx.emit(
		FixtureNoteEvent.new("hold started %d by %d task %d" % [station.id, channel.actor, task_id])
	)


## "hold stopped <station> by <actor> after <ticks>", with " phase_ended" when stop_all stopped it.
func hold_stopped(
	ctx: MatchContext, _task: MatchTask, station: StationState, channel: Channel
) -> void:
	var text := "hold stopped %d by %d after %d" % [station.id, channel.actor, channel.done_ticks]
	if channel.phase_ended:
		text += " phase_ended"
	ctx.emit(FixtureNoteEvent.new(text))


## "hold completed <station> by <actor> after <ticks>".
func hold_completed(
	ctx: MatchContext, _task: MatchTask, station: StationState, channel: Channel
) -> void:
	ctx.emit(
		FixtureNoteEvent.new(
			"hold completed %d by %d after %d" % [station.id, channel.actor, channel.done_ticks]
		)
	)


func kills() -> bool:
	return killing


func hold_emits() -> Array[Script]:
	if quiet:
		return []
	return [FixtureNoteEvent]


func emits() -> Array[Script]:
	return [StationPlacedEvent]
