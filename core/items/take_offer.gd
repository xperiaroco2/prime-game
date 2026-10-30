class_name TakeOffer
extends RuleEffect
## The actor takes the offer the rule's target player (the TakeOffer's `target`, the giver) holds
## out to it (#1434; ARCHITECTURE §7.1, §9.4; GDD §6 "Handing over"): Offers.take. The item leaves
## the giver's hand and arrives exactly as a pick-up from the floor (Items.take_offered: the same
## hand, belt and swap moves and events), then the offer ends. Run it after the conditions
## required_conditions() lists. As every applied action does, it stops the actor's running channel
## first (RuleRunner).
##
## Emits: ItemPickedUp (everyone, its `peer` the receiver); for a full receiver first ItemPlaced
## (put_down) and item_rested for the item it puts down, for a two-handed swap ItemPlaced (swap)
## after; then OfferEnded (everyone).


func run(ctx: MatchContext) -> void:
	Offers.take(ctx, Channels.target_of(ctx), ctx.actor)


## The condition classes a rule holding this effect must hold, not negated (ModeCheck): the offer
## (OfferedTo), the giver (TargetLiving) and the geometry (TargetInReach, TargetInSight), so no
## mode takes an item nobody offers, or from a player far away or behind a wall.
static func required_conditions() -> Array[Script]:
	return [OfferedTo, TargetLiving, TargetInReach, TargetInSight]


func emits() -> Array[Script]:
	return [ItemPickedUpEvent, ItemPlacedEvent, OfferEndedEvent]
