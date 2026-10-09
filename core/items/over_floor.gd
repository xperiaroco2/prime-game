class_name OverFloor
extends Condition
## Passes when there is a floor below the actor's last accepted position: WorldQuery.floor_below
## of it lifted (Items.lifted), the point Items.fallback_rest asks (ARCHITECTURE §7.1.16, §9.4;
## the throwing ADR, TD11 (a)). The base mode's Throw rule holds it before ThrowItem, and ModeCheck
## requires it in every rule that throws: a throw over no floor (a jump over a pit, a client that
## walked out through the level's wall) would have no fallback rest, and its item could hang in
## the air where nobody reaches it. A condition, not a check inside the effect, so a refused throw
## stops no raise (an applied action does, before its effects run).
## Rejects with `no_floor`: it names only the sender's own position, which the sender knows.

const NO_FLOOR := &"no_floor"


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	if actor == null:
		return false
	return ctx.world.floor_below(Items.lifted(actor.position)) != WorldQuery.NO_FLOOR


func _reason() -> StringName:
	return NO_FLOOR
