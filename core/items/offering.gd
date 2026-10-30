class_name Offering
extends Condition
## Passes when the actor has a live offer: it holds out its hand item to another player
## (Offers.live; ARCHITECTURE §9.4; #1434). The CancelOffer rule holds it; the HandOver rule holds
## it negated (`not_allowed`), so a giver has one offer at a time. Rejects with `no_offer`: the
## sender knows its own offer, and so does everyone (OfferMade).


func _test(ctx: MatchContext) -> bool:
	return Offers.live(ctx.state, ctx.actor) != null


func _reason() -> StringName:
	return Offers.NO_OFFER
