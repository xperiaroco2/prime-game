class_name OfferedTo
extends Condition
## Passes when the rule's target player (Channels.target_of: the TakeOffer's `target`, the giver)
## has a live offer to the actor: it holds the offered item in its hand still (Offers.live;
## ARCHITECTURE §9.4; #1434). Rejects with `no_offer`, the same for no offer and for an offer to
## another player, so the refusal tells nothing the public OfferMade did not; with `bad_args` when
## the target is the actor itself (the sender knows its own id).


## It needs a target player, which only an intent gives: no fact carries one. It also reads the
## actor (the default), whom the offer must name.
func needs_target() -> bool:
	return true


func rejection_reason_in(ctx: MatchContext) -> StringName:
	if not negate and Channels.target_of(ctx) == ctx.actor:
		return RejectReasons.BAD_ARGS
	return rejection_reason()


func _test(ctx: MatchContext) -> bool:
	var giver := Channels.target_of(ctx)
	if giver == ctx.actor:
		return false
	var offer := Offers.live(ctx.state, giver)
	return offer != null and offer.target == ctx.actor


func _reason() -> StringName:
	return Offers.NO_OFFER
