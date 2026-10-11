class_name FixtureSkipItemIds
extends RuleEffect
## Moves the match's item id counter on to `next` (MatchState.skip_item_ids_to), as if a long
## match had handed out the ids before it: the replay test of reused ids (the cooking ADR §7, C10)
## starts near the wire's limit with it, as a transition action, so the replay repeats it.

@export var next := 1


func run(ctx: MatchContext) -> void:
	ctx.state.skip_item_ids_to(next)
