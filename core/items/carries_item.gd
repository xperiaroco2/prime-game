class_name CarriesItem
extends Condition
## Passes when the actor carries an item in the hand or on the belt (ARCHITECTURE §9.4; vision
## revision 1, Two hands): the base mode's Swap. Rejects with `nothing_to_swap`: the sender knows
## its own slots.

const NOTHING_TO_SWAP := &"nothing_to_swap"


func _test(ctx: MatchContext) -> bool:
	return (
		Items.held_by(ctx.state, ctx.actor) != null or Items.belted_by(ctx.state, ctx.actor) != null
	)


func _reason() -> StringName:
	return NOTHING_TO_SWAP
