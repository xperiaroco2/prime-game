class_name MirrorFree
extends Condition
## Passes when the mirror place the actor targets is free or the actor's own (Mirror.holder;
## ARCHITECTURE §9.4; #1394): the place's Interact rule holds it after AtStation and StationInSight,
## so a second player cannot take a place another one holds. Rejects with `unavailable`: who stands
## where is public (MirrorPlaces).

const UNAVAILABLE := &"unavailable"


## It reads the place the intent names (Stations.target_of), and the actor.
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var station := Stations.target_of(ctx)
	if station == null:
		return false
	var held := Mirror.holder(ctx.state, station.id)
	return held < 0 or held == ctx.actor


func _reason() -> StringName:
	return UNAVAILABLE
