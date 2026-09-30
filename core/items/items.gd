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

## How far the rules lift a WorldQuery point that lies on a surface (an item's rest position, a
## player's feet) before asking about it: a physics WorldQuery (M3) may count the surface a line
## ends on as a wall, or miss the floor a ray starts on. A tolerance, not a game rule.
const SURFACE_CLEARANCE_M := 0.05

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
## reach and the sight; an item that is not on the ground here is a rule error, and the sender
## of the intent gets `unavailable`.
static func take(ctx: MatchContext, peer: int, item: ItemState) -> void:
	var player := ctx.state.player(peer)
	if player == null or item == null or item.where != ItemState.Where.GROUND:
		ctx.error("take: item %s is not on the ground for player %d" % [_id(item), peer])
		# The sender still gets an answer to its PickUp, as if ItemOnGround had rejected it.
		if ctx.command != null:
			ctx.reject(ctx.command, ItemOnGround.UNAVAILABLE)
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
## (WorldQuery.floor_below, asked from just above the feet: Items.lifted), never in mid-air:
## ItemPlaced (`cause`: death or leave), then item_rested. With no floor below (a level without one
## there) it rests at that position, and the error is logged. The life rule (2g) calls this after
## the life state changed and after player_died or player_left was raised (§3.4, §9.2).
static func drop_held(ctx: MatchContext, peer: int, cause: StringName) -> void:
	var item := held_by(ctx.state, peer)
	if item == null:
		return
	var from := ctx.state.player(peer).position
	var at := ctx.world.floor_below(lifted(from))
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


## `player`'s eye for the item rules (InSight, PutDownInFront): the floor below its last accepted
## position (WorldQuery.floor_below) raised by the mode's PlayerRules.eye_height_m. A jump does
## not raise it, so a player cannot see or put an item over a wall from the top of a jump. With
## no floor below, the eye is raised from the position itself.
static func eye_of(ctx: MatchContext, player: PlayerState) -> Vector3:
	var base := player.position
	var ground := ctx.world.floor_below(lifted(base))
	if ground != WorldQuery.NO_FLOOR:
		base.y = ground.y
	return base + Vector3.UP * ctx.state.player_rules.eye_height_m


## `point` lifted by SURFACE_CLEARANCE_M, off the surface it lies on.
static func lifted(point: Vector3) -> Vector3:
	return point + Vector3.UP * SURFACE_CLEARANCE_M


static func _id(item: ItemState) -> String:
	return str(item.id) if item != null else "none"
