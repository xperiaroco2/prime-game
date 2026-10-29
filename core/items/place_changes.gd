class_name PlaceChanges
extends Condition
## Passes when the intent's `place` is not the actor's selected place (ARCHITECTURE §9.4; GDD §6
## "Drawing from the belt"): the base mode's Draw, after PlaceInRange, so a Draw of the place
## already in the hand changes nothing and says so. Rejects with `same_place`: the sender knows
## its own places.

const SAME_PLACE := &"same_place"


func _test(ctx: MatchContext) -> bool:
	var player := ctx.actor_state()
	if player == null or ctx.command == null:
		return false
	return ctx.command.get_int("place", -1) != player.selected_place


func _reason() -> StringName:
	return SAME_PLACE
