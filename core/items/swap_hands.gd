class_name SwapHands
extends RuleEffect
## The actor's hand and belt items change places (ARCHITECTURE §7.1, §9.4; vision revision 1, Two
## hands): Items.swap. Either slot may be empty, so a lone item moves between the hand and the
## belt. Run it after CarriesItem and HandNotTwoHanded. As every applied action does, it stops the
## actor's running channel first (RuleRunner: a raiser who swaps stops its raise).
##
## Emits: Swapped (everyone).


func run(ctx: MatchContext) -> void:
	Items.swap(ctx, ctx.actor)


func emits() -> Array[Script]:
	return [SwappedEvent]
