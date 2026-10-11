class_name StationUsable
extends Condition
## Passes when the task type that owns the kind of the rule's station (Stations.target_of: the one
## the intent names, or on a re-check the channel's, the car repair ADR's RE2) takes a use of it
## now (TaskType.use_problem empty; the Generator ADR's GE2, #796). On a re-check
## (MatchContext.channel set) use_problem says whether a running hold may go on. Rejects with the
## type's own reason (the cooking ADR's CE11, #780): one the type lists in TaskType.use_reasons(),
## each of which is one of REASONS (ModeCheck). Each reason says only public state of a station the
## actor has in reach and in sight (ModeCheck requires AtStation and StationInSight before this
## condition), and what the actor holds, never a role, so a task whose stations hold state the
## rules hide inherits the limit. A reason outside either list is a match error and refused
## `unavailable`.
##
## The reason depends on the run, so it comes from rejection_reason_in(), which asks use_problem
## again (a query that changes nothing); rejection_reason(), which has no MatchContext, is
## `unavailable` (ModeCheck's alphabet check of every condition's reason).

## The station takes no use now: the task is done (the Generator), or the station has nothing to
## give.
const UNAVAILABLE := &"unavailable"
## The station does not take what the actor holds (the cooking ADR's CE11: a cooked patty at an
## empty grill, a knife at a place).
const WRONG_ITEM := &"wrong_item"
## The use needs an item in the actor's hand, and it holds none (HoldsItem's reason).
const EMPTY_HAND := HoldsItem.EMPTY_HAND
## The use would put an item beside a two-handed one (HandNotTwoHanded's reason).
const TWO_HANDED := HandNotTwoHanded.TWO_HANDED
## Every reason use_problem may return, and a type may list in use_reasons(). A new one updates
## ARCHITECTURE §9.4.1's row (what it reveals) and station_usable_test.gd, and the protocol
## version (a client of the old one never gets it).
const REASONS: Array[StringName] = [UNAVAILABLE, WRONG_ITEM, EMPTY_HAND, TWO_HANDED]


## It needs a station (Stations.target_of), which no fact carries, and also reads the actor (the
## default): a task type's use_problem may read what the actor holds.
func needs_target() -> bool:
	return true


func rejection_reason_in(ctx: MatchContext) -> StringName:
	if negate:
		return RejectReasons.NOT_ALLOWED
	return _problem(ctx, false)


func _test(ctx: MatchContext) -> bool:
	return _problem(ctx, true).is_empty()


func _reason() -> StringName:
	return UNAVAILABLE


## Why the type refuses the use `ctx` names, or empty when it takes it: the type's reason when it
## lists it and REASONS has it, else `unavailable`, which `report` also logs as a match error.
func _problem(ctx: MatchContext, report: bool) -> StringName:
	var station := Stations.target_of(ctx)
	if station == null:
		return UNAVAILABLE
	var type := Stations.owner_of(ctx.mode, station.kind)
	if type == null:
		return UNAVAILABLE
	var reason := type.use_problem(ctx, Stations.task_of(ctx.state, type), station)
	if reason.is_empty() or (REASONS.has(reason) and type.use_reasons().has(reason)):
		return reason
	if report:
		ctx.error(
			(
				"task type %s refused a use of station %d with %s, which is not one of its %s"
				% [type.id, station.id, reason, type.use_reasons()]
			)
		)
	return UNAVAILABLE
