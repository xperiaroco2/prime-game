class_name CarriesItem
extends Condition
## Passes when the actor carries an item in any of its three places, the hand or the belt
## (ARCHITECTURE §9.4; vision revision 1, Two hands; GDD §6): the base mode's Swap (X). Rejects
## with `nothing_to_swap`: the sender knows its own places.

const NOTHING_TO_SWAP := &"nothing_to_swap"


func _test(ctx: MatchContext) -> bool:
	return not Items.carried_by(ctx.state, ctx.actor).is_empty()


func _reason() -> StringName:
	return NOTHING_TO_SWAP
