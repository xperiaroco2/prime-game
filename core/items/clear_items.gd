class_name ClearItems
extends RuleEffect
## Removes every item of the match (ARCHITECTURE §3.2, §9.4, #1388): a transition action of
## `Countdown, countdown_done -> Loading`, so nothing held, stashed or put down in the lobby's hall
## reaches Pregame or Round. Each item, in ascending id, vanishes as VanishTicks' do
## (Items.vanish): out of any hand or belt (a two-handed one too), out of MatchState, its id queued
## for reuse. Items only: a station that holds an item keeps its own reference, so a lobby thing
## that locks an item on a station clears its own state at the same row.
##
## Emits: ItemVanished (everyone), per item in ascending id. No demands.


func run(ctx: MatchContext) -> void:
	var ids: Array[int] = []
	ids.assign(ctx.state.items.keys())
	ids.sort()
	for id: int in ids:
		var item: ItemState = ctx.state.items.get(id)
		if item != null:
			Items.vanish(ctx, item)


func emits() -> Array[Script]:
	return [ItemVanishedEvent]
