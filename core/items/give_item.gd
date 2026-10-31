class_name GiveItem
extends RuleEffect
## A new item of `kind` comes to the actor from the rule's target (the cooking ADR's CE2, CE3,
## #770: a box's take; ARCHITECTURE §9.4.2): spawned at the target's position (the item the intent
## names, a box at rest; else the station it names), announced by ItemSpawned (no station), then
## given to the actor (Items.give, which makes room). The new item never rests, so no item_rested
## is raised for it. Its body is give_new(), which a task type calls for a source that is a station
## (Cooking.use_station for a herb bed, C4) and the photo booth's print calls from a tick for each
## strip's receiver as the actor, with no command (BoothSessions, #1396).
##
## The cap (CE3): `kind.max_items` set, a kind with that many items in the match first vanishes the
## loose one of the kind that the cap ranks first (on the ground: the lowest TaskType.cap_tier, PE10
## of the photo ADR, #782; then the one that has lain longest: the earliest rest tick, then the
## lowest id; Items.vanish, ItemVanished), so a take is never refused for spam; with none loose
## (every one held, locked or flying) the intent is refused `unavailable` (refusal(), before
## anything is paid) and nothing is spawned.
##
## Emits: ItemVanished (the cap), ItemSpawned, then what Items.give emits: for a full belt
## ItemPlaced (put_down) and item_rested for the item put down at the feet, then ItemPickedUp; all
## to everyone. As a rule effect only on an intent that names a target (Interact; ModeCheck), never
## in a reaction or a row, which have no actor.

## The kind given: one-handed (Items.give never gives a two-handed item) and capped (`max_items`
## set), as its check asks.
@export var kind: ItemKind


func run(ctx: MatchContext) -> void:
	give_new(ctx, kind, target_spot(ctx))


func refusal(ctx: MatchContext) -> StringName:
	return cap_problem(ctx.state, kind)


func emits() -> Array[Script]:
	return [ItemVanishedEvent, ItemSpawnedEvent, ItemPlacedEvent, ItemPickedUpEvent]


## The condition classes the rule of a take must hold, not negated, in this order (ModeCheck; the
## refusal order of ADR §2): at an item (an item kind's target_actions) it lies on the ground, in
## reach and in sight; at a station the actor is at it and has it in sight. The host checks reach
## and sight, never the content's goodwill.
static func required_conditions(at_item: bool) -> Array[Script]:
	if at_item:
		return [ItemOnGround, InReach, InSight]
	return [AtStation, StationInSight]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == null:
		found.append("GiveItem has no kind")
		return found
	if mode.find_item_kind(kind.id) == null:
		found.append("GiveItem: item kind %s is not an item kind of the mode" % kind.id)
	if kind.is_two_handed():
		found.append(
			"GiveItem gives item kind %s, which is two-handed: Items.give refuses it" % kind.id
		)
	if not kind.is_capped():
		found.append(
			"GiveItem gives item kind %s, which sets no max_items: nothing would bound it" % kind.id
		)
	return found


## Where the rule's target is: the position of the item the intent names, else of the station it
## names; the actor's position when it names neither (Match refuses that intent `bad_args` first).
static func target_spot(ctx: MatchContext) -> Vector3:
	var item := Items.target_of(ctx)
	if item != null:
		return item.position
	var station := Stations.target_of(ctx)
	if station != null:
		return station.position
	ctx.error("GiveItem: the intent names no item and no station")
	var player := ctx.state.player(ctx.actor)
	return player.position if player != null else Vector3.ZERO


## Why a new item of `given` cannot be given now, or empty: `unavailable` when the kind is at its
## cap and none of its items is loose (CE3).
static func cap_problem(state: MatchState, given: ItemKind) -> StringName:
	if given == null or not given.is_capped():
		return &""
	if _count(state, given) < given.max_items or _first_loose(state, given) != null:
		return &""
	return ItemOnGround.UNAVAILABLE


## A new item of `given` spawned at `at` and given to the actor (CE2), after the cap (CE3): at the
## cap the loose one that has lain longest vanishes first. Returns the new item, or null when
## nothing was spawned: the cap with none loose (the intent is refused `unavailable`, as
## refusal() would have), or every item id in use (a rule error, logged).
static func give_new(ctx: MatchContext, given: ItemKind, at: Vector3) -> ItemState:
	if given == null:
		ctx.error("GiveItem: no kind to give")
		return null
	if not make_room(ctx, given):
		if ctx.command != null:
			ctx.reject(ctx.command, ItemOnGround.UNAVAILABLE)
		return null
	var made := Items.spawn(ctx, given, at)
	if made == null:
		return null
	ctx.emit(ItemSpawnedEvent.new(made.id, given.id, at))
	Items.give(ctx, ctx.actor, made)
	return made


## The cap before a new item of `given` (CE3; the photo ADR's PE10): with `max_items` items of the
## kind in the match, the loose one first in the cap's order (_first_loose) vanishes (Items.vanish,
## ItemVanished). False, with nothing changed, when the kind is at its cap and none is loose: no
## new item may come. True otherwise (an uncapped kind, or room). A printer's photos (PhotoTask)
## make room through it too.
static func make_room(ctx: MatchContext, given: ItemKind) -> bool:
	if not given.is_capped() or _count(ctx.state, given) < given.max_items:
		return true
	var first := _first_loose(ctx.state, given)
	if first == null:
		return false
	Items.vanish(ctx, first)
	return true


## How many items of `given` the match holds, wherever they are.
static func _count(state: MatchState, given: ItemKind) -> int:
	var count := 0
	for item: ItemState in state.items.values():
		if item.kind == given:
			count += 1
	return count


## The item of `given` lying on the ground that the cap vanishes first, or null: a held, locked or
## flying item is never loose. The lowest tier first (TaskType.cap_tier, the highest answer of the
## match's dealt task types; the photo ADR's PE10: the camera's film last), then the one that has
## lain longest (the earliest rest tick, then the lowest id).
static func _first_loose(state: MatchState, given: ItemKind) -> ItemState:
	var found: ItemState = null
	var found_tier := 0
	for item: ItemState in state.items.values():
		if item.kind != given or item.where != ItemState.Where.GROUND:
			continue
		var tier := _tier(state, item)
		if (
			found == null
			or tier < found_tier
			or (tier == found_tier and item.rest_tick < found.rest_tick)
			or (tier == found_tier and item.rest_tick == found.rest_tick and item.id < found.id)
		):
			found = item
			found_tier = tier
	return found


## The highest cap_tier any task of the match gives `item` (0 with no task).
static func _tier(state: MatchState, item: ItemState) -> int:
	var tier := 0
	for task: MatchTask in state.tasks.values():
		if task.type != null:
			tier = maxi(tier, task.type.cap_tier(state, item))
	return tier
