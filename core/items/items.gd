class_name Items
extends RefCounted
## The hand slot and how items come to rest (ARCHITECTURE §7.1, §9.2, §9.4): the one place that
## moves an item between the ground and a hand, emits ItemPickedUp and ItemPlaced, and raises the
## fact `item_rested`. The parts of core/items/ call it, and so do the parts of later stages:
##
## - place(): an item comes to rest at a spot (a put-down, a swap): ItemPlaced, then item_rested.
## - drop_held(): a dying or leaving player's held item falls to the floor below the player's last
##   accepted position: ItemPlaced (death or leave), then item_rested. The life rule (2g) calls it
##   from player_died and player_left, after the life state changed and the fact was raised.
## - raise_rested(): item_rested for an item that is already at rest and announced by its own
##   event (the spawn: SpawnItems 2c and Delivery's deal 2f emit ItemSpawned, then call this).
##
## Every range rule reads the player's last accepted position in PlayerState, never a position
## inside an intent (§7.1). The rest position comes from WorldQuery, never from a client.

## Why an item came to rest: the `cause` of ItemPlaced and of the fact item_rested.
const PUT_DOWN := &"put_down"
const SWAP := &"swap"
const DEATH := &"death"
const LEAVE := &"leave"
## item_rested only: the item was placed by a deal (ItemSpawned announces it).
const SPAWN := &"spawn"


## The item an intent or a fact is about: the `item` field of the intent being handled, else the
## fact's item. Null when there is none or it does not exist.
static func target_of(ctx: MatchContext) -> ItemState:
	var id := -1
	if ctx.command != null:
		id = ctx.command.get_int("item", -1)
	elif ctx.fact != null:
		id = ctx.fact.item
	return ctx.state.items.get(id)


## The item `peer` holds, or null.
static func held_by(state: MatchState, peer: int) -> ItemState:
	var player := state.player(peer)
	if player == null or player.held_item < 0:
		return null
	return state.items.get(player.held_item)


## `item`, lying on the ground, goes into `peer`'s hand. A held item is swapped: it comes to rest
## where the picked-up one lay, a spot already known to be valid (§7.1). Emits ItemPickedUp, then
## for a swap ItemPlaced (swap) and item_rested. The rule's conditions checked the ground, the
## reach and the sight; an item that is not on the ground here is a rule error.
static func take(ctx: MatchContext, peer: int, item: ItemState) -> void:
	var player := ctx.state.player(peer)
	if player == null or item == null or item.where != ItemState.Where.GROUND:
		ctx.error("take: item %s is not on the ground for player %d" % [_id(item), peer])
		return
	var swapped := held_by(ctx.state, peer)
	var spot := item.position
	item.where = ItemState.Where.HAND
	item.holder = peer
	player.held_item = item.id
	ctx.emit(ItemPickedUpEvent.new(peer, item.id))
	if swapped != null:
		place(ctx, swapped, spot, SWAP)


## `item` comes to rest at `at` for `cause`: on the ground, out of any hand. Emits ItemPlaced to
## everyone, then raises item_rested (Delivery's check runs on it, §7.1).
static func place(ctx: MatchContext, item: ItemState, at: Vector3, cause: StringName) -> void:
	if item.where == ItemState.Where.HAND:
		var holder := ctx.state.player(item.holder)
		if holder != null and holder.held_item == item.id:
			holder.held_item = -1
	item.where = ItemState.Where.GROUND
	item.holder = 0
	item.position = at
	ctx.emit(ItemPlacedEvent.new(item.id, at, cause))
	raise_rested(ctx, item, cause)


## Drops the item `peer` holds, if any, to the floor below the player's last accepted position
## (WorldQuery.floor_below), never in mid-air: ItemPlaced (`cause`: death or leave), then
## item_rested. With no floor below (a level without one there) it rests at that position, and
## the error is logged. The life rule (2g) calls this after the life state changed and after
## player_died or player_left was raised (§3.4, §9.2).
static func drop_held(ctx: MatchContext, peer: int, cause: StringName) -> void:
	var item := held_by(ctx.state, peer)
	if item == null:
		return
	var from := ctx.state.player(peer).position
	var at := ctx.world.floor_below(from)
	if at == WorldQuery.NO_FLOOR:
		ctx.error("drop: no floor below %s for item %d of player %d" % [from, item.id, peer])
		at = from
	place(ctx, item, at, cause)


## Raises item_rested for `item`, at rest where it is, with `cause` (§9.2). Use it for an item
## that came to rest without ItemPlaced: the spawn (`SPAWN`), after ItemSpawned.
static func raise_rested(ctx: MatchContext, item: ItemState, cause: StringName) -> void:
	var fact := Fact.new(Facts.ITEM_RESTED)
	fact.item = item.id
	fact.position = item.position
	fact.cause = cause
	ctx.raise_fact(fact)


static func _id(item: ItemState) -> String:
	return str(item.id) if item != null else "none"
