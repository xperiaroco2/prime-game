class_name VanishTicks
extends TickSystem
## The tick system of items left lying (ARCHITECTURE §9.4.5; the cooking ADR, CD6 (c), CE3): every
## tick of the phase that lists it, each item of a kind with `vanish_seconds` that lies on the
## ground and has lain that long since it last came to rest (ItemState.rest_tick, which Items.lay
## sets) vanishes through Items.vanish, with ItemVanished, in ascending item id (§3.3's stable
## order, never the item table's, which a reused id breaks). An item lying since tick r of a kind
## of s seconds vanishes in the first tick t of such a phase with t - r >= Ticks.from_seconds(s):
## exactly then when the phase runs through it. A pick-up and a put-down start it over; an item in
## a hand, on a belt, in flight or locked does not lie, so it never vanishes.
##
## A phase that does not list it removes nothing; a later phase that does removes at once what
## lay long enough meanwhile. An item of a vanishing kind on the ground without a rest tick (put
## into MatchState without Items.spawn or Items.lay) is a rule error, logged, and stays.
##
## Emits: ItemVanished. No demands.


func run(ctx: MatchContext) -> void:
	for id: int in due(ctx):
		var item: ItemState = ctx.state.items.get(id)
		if item != null:
			Items.vanish(ctx, item)


func emits() -> Array[Script]:
	return [ItemVanishedEvent]


## The ids of the items that vanish in this tick, ascending.
static func due(ctx: MatchContext) -> Array[int]:
	var ids: Array[int] = []
	for id: int in ctx.state.items:
		var item: ItemState = ctx.state.items[id]
		if item.kind == null or not item.kind.vanishes() or item.where != ItemState.Where.GROUND:
			continue
		if item.rest_tick < 0:
			ctx.error("VanishTicks: item %d lies with no rest tick" % id)
			continue
		if ctx.tick - item.rest_tick >= Ticks.from_seconds(item.kind.vanish_seconds):
			ids.append(id)
	ids.sort()
	return ids
