class_name HoldsItem
extends Condition
## Passes when the actor has an item in hand (ARCHITECTURE §9.4). Rejects with `empty_hand`: the
## sender knows its own hand.

const EMPTY_HAND := &"empty_hand"


func _test(ctx: MatchContext) -> bool:
	return Items.held_by(ctx.state, ctx.actor) != null


func _reason() -> StringName:
	return EMPTY_HAND
