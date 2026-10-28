class_name SwapHands
extends RuleEffect
## X: the actor's last place comes back into the hand (ARCHITECTURE §7.1, §9.4; GDD §6 "Drawing
## from the belt"): Items.back. The hand item stays in its place, on the belt, so with a single
## item X moves it between the hand and the belt, as the swap of one belt slot did. Either place
## may be empty. Run it after CarriesItem and HandNotTwoHanded (X keeps V13: a two-handed hand
## item is refused, never put down). As every applied action does, it stops the actor's running
## channel first (RuleRunner: a raiser who swaps stops its raise).
##
## Emits: Swapped (everyone).


func run(ctx: MatchContext) -> void:
	Items.back(ctx, ctx.actor)


func emits() -> Array[Script]:
	return [SwappedEvent]
