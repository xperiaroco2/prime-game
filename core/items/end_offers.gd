class_name EndOffers
extends RuleEffect
## Every open hand-over offer ends (#1434; ARCHITECTURE §7.1, §9.4): a transition action on a row
## from a phase that lists OfferTicks into one that does not (the base mode's Countdown -> Loading
## and Round -> End), so no offer outlasts the phase that ends offers (OfferTicks.problems). In
## giver order, OfferEnded for each; none open: nothing happens.
##
## Emits: OfferEnded (everyone). No demands.


func run(ctx: MatchContext) -> void:
	Offers.end_all(ctx)


func emits() -> Array[Script]:
	return [OfferEndedEvent]
