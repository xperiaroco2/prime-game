class_name UseStation
extends RuleEffect
## Uses the station the intent names: hands it to the task type that owns its kind
## (TaskType.use_station), which alone writes its task state (§9.1; the Generator ADR's GE2,
## #796). Emits what that type's use_emits() lists, which emits() cannot name: ModeCheck counts
## the owning type's use_emits() for a UseStation in a station kind's rule (§9.2's role-reveal
## warning), and every task type's for one in a role's or the mode's rule, which any station may
## reach. Requires AtStation, StationInSight and StationUsable in its rule (ModeCheck), so a use
## is only ever of a station in reach, in sight and that its type takes now.


func run(ctx: MatchContext) -> void:
	var station := Stations.target_of(ctx)
	var type: TaskType = null
	if station != null:
		type = Stations.owner_of(ctx.mode, station.kind)
	if type == null:
		ctx.error("UseStation: the intent names no station of a task type of the mode")
		return
	type.use_station(ctx, Stations.task_of(ctx.state, type), station)


## The condition classes its rule must hold, not negated (ModeCheck), StationUsable after the
## other two.
func required_conditions() -> Array[Script]:
	return [AtStation, StationInSight, StationUsable]
