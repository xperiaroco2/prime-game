class_name TakeIntoHand
extends RuleEffect
## The rule's item (the intent's `item`) goes into the actor's hand; a held item is swapped: it
## comes to rest where the picked-up one lay, a spot already known to be valid (ARCHITECTURE
## §7.1, §9.4). Run it after ItemOnGround, InReach and InSight.
##
## Emits: ItemPickedUp (everyone); for a swap, ItemPlaced (swap, everyone), then the fact
## item_rested for the swapped item.


func run(ctx: MatchContext) -> void:
	Items.take(ctx, ctx.actor, Items.target_of(ctx))


func emits() -> Array[Script]:
	return [ItemPickedUpEvent, ItemPlacedEvent]
