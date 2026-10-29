class_name PlaceInRange
extends Condition
## Passes when the intent's `place` names one of the actor's three places, 0..2 (ARCHITECTURE
## §9.4; GDD §6 "Drawing from the belt"): the base mode's Draw, which carries the place as a wire
## byte. Rejects with `no_such_place`: the sender sent the number itself. It reads the intent, which
## a reaction or a win condition has none of, so it keeps reads_actor_state() true.

const NO_SUCH_PLACE := &"no_such_place"


func _test(ctx: MatchContext) -> bool:
	if ctx.command == null:
		return false
	var place := ctx.command.get_int("place", -1)
	return place >= 0 and place < PlayerState.PLACES


func _reason() -> StringName:
	return NO_SUCH_PLACE
