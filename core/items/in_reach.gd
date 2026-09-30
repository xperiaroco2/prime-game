class_name InReach
extends Condition
## Passes when the rule's item (Items.target_of) is within `reach_m` of the actor's last accepted
## position, the feet of its last accepted MoveClaim, never a position inside the intent
## (ARCHITECTURE §7.1, §9.4). Rejects with `out_of_reach`: the sender knows both positions.

const OUT_OF_REACH := &"out_of_reach"

## Metres, 0.1 to 10. The neutral default is out of bounds on purpose: the data sets it (the base
## mode's PickUp: 2), so the mode check refuses a rule that forgot it.
@export var reach_m := 0.0


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var item := Items.target_of(ctx)
	if actor == null or item == null:
		return false
	return actor.position.distance_to(item.position) <= reach_m


func _reason() -> StringName:
	return OUT_OF_REACH


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [out_of_bounds("InReach reach_m", reach_m, 0.1, 10)])
	return found
