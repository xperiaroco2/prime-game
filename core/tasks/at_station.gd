class_name AtStation
extends Condition
## Passes when the actor's feet, the position of its last accepted claim (never a position inside
## the intent; ARCHITECTURE §7.1), stand inside the cylinder of the station the intent names
## (StationState.contains: the kind's radius_m and height_m; the Generator ADR's GE3, #796). One
## cylinder means "at the station" for every station: a package rests in it, a zone counts a
## player in it, a switch is used from it. Rejects with `out_of_reach`: the sender knows its own
## position and the station's (StationPlaced is public).

const OUT_OF_REACH := &"out_of_reach"


## It needs a station (Stations.target_of), which no fact carries, and also reads the actor (the
## default).
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var station := Stations.target_of(ctx)
	if actor == null or station == null:
		return false
	return station.contains(actor.position)


func _reason() -> StringName:
	return OUT_OF_REACH
