class_name Drink
extends RuleEffect
## The actor drinks the item in its hand (#1390; GDD §3 Base mode, "The bar"; ARCHITECTURE §9.4.2):
## a full mug's UseSecondary (the right mouse button, #1438). The held item becomes `empty_kind`
## where it is (Items.change_kind: ItemChanged to everyone; it keeps its id, place and holder), and
## the actor's PlayerState.drunk rises by `amount`, at most to PlayerRules.drunk_max. A drink
## that lifts the value from below PlayerRules.drunk_too_much_at to that or above raises the fact
## `drunk_too_much` (Fact.player: the drinker), each upward crossing once; below it nothing is
## raised. A sober drinker's first point falls one PlayerRules.drunk_point_s later (DrunkTicks);
## drinking while drunk adds to the value and keeps the stamp. The value is public (the avatar)
## and the drinker's own SelfStatus carries it (SelfStatusFeed).
##
## The empty kind's cap: before the change, the loose empty that has lain longest makes room
## (GiveItem.make_room: ItemVanished), so spamming the tap and drinking never floods the hall with
## empties; with every empty held (a hand bounds them) the drink still goes ahead.
##
## The rule's owner is the full kind's `actions` (a held item's UseSecondary, §9.3): the empty kind
## lists no rule, so either intent with an empty mug in the hand finds none and is refused
## `nothing_to_do`; so does a Use with a full one (the left button is the hit's, #1437).
##
## Emits: ItemVanished (the empty's cap), ItemChanged; both to everyone. No demands. Only on an
## intent (an actor); a reaction or a row has none (a rule error, logged).

## What the drunk item becomes: one-handed and capped (`max_items` set), an item kind of the mode.
@export var empty_kind: ItemKind
## How much one drink raises PlayerState.drunk: 1..PlayerRules.drunk_max.
@export var amount := 0


func run(ctx: MatchContext) -> void:
	var player := ctx.state.player(ctx.actor)
	var item := Items.held_by(ctx.state, ctx.actor)
	var rules := ctx.state.player_rules
	if player == null or item == null or rules == null or empty_kind == null:
		ctx.error("Drink: player %d holds nothing to drink, or no rules or empty kind" % ctx.actor)
		return
	GiveItem.make_room(ctx, empty_kind)
	Items.change_kind(ctx, item, empty_kind)
	var before := player.drunk
	player.drunk = mini(before + amount, rules.drunk_max)
	if before == 0 and player.drunk > 0:
		player.drunk_stamp = ctx.tick + DrunkTicks.step_of(rules)
	SelfStatusFeed.touch(ctx.state, player.peer)
	if before < rules.drunk_too_much_at and player.drunk >= rules.drunk_too_much_at:
		var fact := Fact.new(Facts.DRUNK_TOO_MUCH)
		fact.player = player.peer
		ctx.raise_fact(fact)


func emits() -> Array[Script]:
	return [ItemVanishedEvent, ItemChangedEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if empty_kind == null:
		found.append("Drink has no empty_kind")
	else:
		if mode.find_item_kind(empty_kind.id) == null:
			found.append("Drink: item kind %s is not an item kind of the mode" % empty_kind.id)
		if empty_kind.is_two_handed() or not empty_kind.is_capped():
			found.append(
				(
					"Drink: empty_kind %s must be one-handed and set max_items (its cap)"
					% empty_kind.id
				)
			)
	var rules := mode.player_rules
	if rules == null or rules.drunk_max <= 0:
		found.append("Drink: the mode's PlayerRules set no drunk_max (no bar)")
		return found
	append_found(found, [out_of_bounds("amount", amount, 1, rules.drunk_max)])
	return found
