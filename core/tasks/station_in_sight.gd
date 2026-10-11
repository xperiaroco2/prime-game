class_name StationInSight
extends Condition
## Passes when the line from the actor's eye (Items.eye_of: the floor it stands on at its last
## accepted position, raised by PlayerRules.eye_height_m) to just above the marker of the station
## the intent names (Items.lifted) is clear of walls (WorldQuery.line_of_sight; the Generator ADR's
## GE4, #796), as InSight for an item. The marker is the use spot, on the floor in front of the
## device and clear of its collision (GE11), so the device does not block it, and a press through
## a thin wall from the next room is refused even where the cylinder reaches through it. Rejects
## with `blocked`: the sender sees the wall too.

const BLOCKED := &"blocked"


## It needs a station (Stations.target_of), which no fact carries, and also reads the actor (the
## default).
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var station := Stations.target_of(ctx)
	if actor == null or station == null or ctx.state.player_rules == null:
		return false
	var eye := Items.eye_of(ctx, actor)
	return ctx.world.line_of_sight(eye, Items.lifted(station.position))


func _reason() -> StringName:
	return BLOCKED
