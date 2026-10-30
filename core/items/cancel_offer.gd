class_name CancelOffer
extends RuleEffect
## The actor's open offer ends (#1434; ARCHITECTURE §7.1, §9.4): the giver presses E again. The
## item stays in its hand. Run it after an Offering condition (required_conditions()).
##
## Emits: OfferEnded (everyone).


func run(ctx: MatchContext) -> void:
	var offer := Offers.of_giver(ctx.state, ctx.actor)
	if offer == null:
		ctx.error("cancel offer: player %d has no offer" % ctx.actor)
		if ctx.command != null:
			ctx.reject(ctx.command, Offers.NO_OFFER)
		return
	Offers.close(ctx, offer)


## The condition classes a rule holding this effect must hold, not negated (ModeCheck).
static func required_conditions() -> Array[Script]:
	return [Offering]


func emits() -> Array[Script]:
	return [OfferEndedEvent]
