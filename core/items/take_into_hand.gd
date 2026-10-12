class_name TakeIntoHand
extends RuleEffect
## The rule's item (the intent's `item`) goes to the actor (ARCHITECTURE §7.1, §9.4; vision
## revision 1, Two hands, as the cooking ADR's CE21 amends it): Items.take. Beside a two-handed hand
## item a one-handed picked item goes onto the belt (Items.give's belt move: a full belt's item
## down at the actor's feet first, ItemPickedUp's `belted` the item itself), the two-handed item
## staying in the hand. Otherwise into the hand: a one-handed hand item moves to an empty belt
## (ItemPickedUp's `belted`); any other hand item is swapped: it comes to rest where the picked-up
## one lay, a spot already known to be valid. Run it after ItemOnGround, InReach and InSight.
##
## Emits: ItemPickedUp (everyone); for a swap, ItemPlaced (swap, everyone), then the fact
## item_rested for the swapped item; for a full belt beside a two-handed hand item, first
## ItemPlaced (put_down, everyone) and item_rested for the belt's item.


func run(ctx: MatchContext) -> void:
	Items.take(ctx, ctx.actor, Items.target_of(ctx))


func emits() -> Array[Script]:
	return [ItemPickedUpEvent, ItemPlacedEvent]
