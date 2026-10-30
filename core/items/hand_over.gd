class_name HandOver
extends RuleEffect
## The actor offers its hand item to the rule's target player (the intent's `target`; #1434,
## ARCHITECTURE §7.1, §9.4; GDD §6 "Handing over"): Offers.open. The item stays in the giver's
## hand, held out, until the receiver takes it (TakeOffer) or the offer ends (CancelOffer,
## OfferTicks, EndOffers). Any item kind may be offered; a two-handed one follows the pick-up's
## hand rules at the take. Run it after the conditions required_conditions() lists (the base mode
## adds a negated Offering: one offer per giver). As every applied action does, it stops the
## actor's running channel first (RuleRunner).
##
## Emits: OfferMade (everyone); before it OfferEnded for an offer of the giver's that no longer
## holds and OfferTicks has not ended yet.


func run(ctx: MatchContext) -> void:
	Offers.open(ctx, ctx.actor, Channels.target_of(ctx), Items.held_by(ctx.state, ctx.actor))


## The condition classes a rule holding this effect must hold, not negated (ModeCheck): the item
## (HoldsItem), the receiver (TargetLiving) and the geometry (TargetInReach, TargetInSight), so no
## mode offers a belt item, or offers to a player far away or behind a wall.
static func required_conditions() -> Array[Script]:
	return [HoldsItem, TargetLiving, TargetInReach, TargetInSight]


func emits() -> Array[Script]:
	return [OfferMadeEvent, OfferEndedEvent]


## Where the mode offers, it ends offers too (OfferTicks.problems).
func check(mode: GameMode) -> PackedStringArray:
	return OfferTicks.problems(mode)
