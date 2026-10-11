class_name StationUsable
extends Condition
## Passes when the task type that owns the named station's kind takes a use of it now
## (TaskType.use_problem empty; the Generator ADR's GE2, #796). Rejects with the type's reason,
## which is one of REASONS: today only `unavailable` (the Generator: any station of its task once
## the task is done). Each reason says only public state of a station the actor has in reach and in
## sight (ModeCheck requires AtStation and StationInSight before this condition), and never a
## role, so a task whose stations hold state the rules hide (cooking, #682) inherits the limit. A
## reason outside REASONS is a match error and refused `unavailable`.
##
## Condition.rejection_reason() has no MatchContext, so the reason is the one of REASONS: a second
## reason needs the condition to carry its run's reason first (the seam is _test here).

const UNAVAILABLE := &"unavailable"
## Every reason use_problem may return. A new one updates ARCHITECTURE §9.4.1's row (what it
## reveals) and station_usable_test.gd.
const REASONS: Array[StringName] = [UNAVAILABLE]


## It needs a station (Stations.target_of), which no fact carries, and also reads the actor (the
## default): a task type's use_problem may read what the actor holds.
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var station := Stations.target_of(ctx)
	if station == null:
		return false
	var type := Stations.owner_of(ctx.mode, station.kind)
	if type == null:
		return false
	var reason := type.use_problem(ctx, Stations.task_of(ctx.state, type), station)
	if reason.is_empty():
		return true
	if not REASONS.has(reason):
		ctx.error(
			(
				"task type %s refused a use of station %d with %s, which is not one of %s"
				% [type.id, station.id, reason, REASONS]
			)
		)
	return false


func _reason() -> StringName:
	return UNAVAILABLE
