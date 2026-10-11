class_name Items
extends RefCounted
## The hand and belt slots and how items come to rest (ARCHITECTURE §7.1, §9.2, §9.4; vision
## revision 1, Two hands): the one place that moves an item between the ground, a hand and a belt,
## emits ItemPickedUp, Swapped and ItemPlaced, and raises the fact `item_rested`. The parts of
## core/items/ call it, and so do the parts of later stages:
##
## - take(): a pickup, into the hand; the hand item goes to the belt or rests where the picked one
##   lay.
## - swap(): the hand and belt items change places.
## - place(): an item comes to rest at a spot (a put-down, a pickup's swap, a dead player's items
##   at its body: the life rule, 2g, after player_died): ItemPlaced, then item_rested.
## - drop_carried(): a leaving player's items, the hand's first, fall to the floor below the
##   player's last accepted position: ItemPlaced (leave), then item_rested, for each. The life
##   rule (2g) calls it after the life state changed and player_left was raised.
## - launch(): a thrown item leaves the hand or belt into its flight (ItemState.Where.FLYING);
##   FlightTicks flies it and rests it through place() with the cause `thrown` (§7.1.16).
## - fallback_rest(): where a thrown item rests when its flight ends over no floor, asked at the
##   launch.
## - raise_rested(): item_rested for an item that is already at rest and announced by its own
##   event (the spawn: SpawnItems 2c and Delivery's deal 2f emit ItemSpawned, then call this).
## - lay(): the one writer of an item's ground state (the cooking ADR, CE3, C10): the item lies at
##   a spot, out of any hand, belt or flight, its rest tick this tick. Every move that leaves an
##   item lying goes through it: place() (a put-down, a swap's rest, a death's or a leave's drop,
##   a throw's landing) and spawn() (a deal's spawn); a later part's lay (C2's `on_station` lay at
##   a place, Items.give's put-down) calls it or place(). Emits nothing.
## - spawn(): a new item of a kind lying at a spot (MatchState.add_item, then lay()); the deals
##   emit ItemSpawned and raise item_rested themselves.
## - lock(): an item at rest becomes locked where it is (a delivered package): not interactive,
##   not lying, so it never vanishes.
## - vanish(): an item leaves the match for good (VanishTicks; C1's cap): ItemVanished to everyone,
##   its id freed for reuse (MatchState.remove_item).
##
## A move into a hand, onto a belt or into flight (take(), swap(), launch()) clears the rest tick.
## - free_markers(): the markers of a tag where no item rests, which every part that places items
##   in a deal draws from, so a deal puts at most one item on a marker.
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
## The end of a thrown item's flight (FlightTicks, §7.1.16).
const THROWN := &"thrown"


## The item an intent or a fact is about: the `item` field of the intent being handled, else the
## fact's item. Null when there is none or it does not exist.
static func target_of(ctx: MatchContext) -> ItemState:
	var id := -1
	if ctx.command != null:
		id = ctx.command.get_int("item", -1)
	elif ctx.fact != null:
		id = ctx.fact.item
	return ctx.state.items.get(id)


## The item `peer` holds in the hand, or null.
static func held_by(state: MatchState, peer: int) -> ItemState:
	var player := state.player(peer)
	if player == null or player.held_item < 0:
		return null
	return state.items.get(player.held_item)


## The item `peer` carries on the belt, or null.
static func belted_by(state: MatchState, peer: int) -> ItemState:
	var player := state.player(peer)
	if player == null or player.belt_item < 0:
		return null
	return state.items.get(player.belt_item)


## `item`, lying on the ground, goes into `peer`'s hand (vision revision 1, Two hands). The hand
## item, if any, moves to the belt when it is one-handed and the belt is empty; otherwise it rests
## where the picked-up one lay, a spot already known to be valid (§7.1), whichever of the two is
## two-handed. Emits ItemPickedUp (with `belted`, the item moved to the belt, E29), then for a
## hand item that rests ItemPlaced (swap) and item_rested. The rule's conditions checked the
## ground, the reach and the sight; an item that is not on the ground here is a rule error, and
## the sender of the intent gets `unavailable`.
static func take(ctx: MatchContext, peer: int, item: ItemState) -> void:
	var player := ctx.state.player(peer)
	if player == null or item == null or item.where != ItemState.Where.GROUND:
		ctx.error("take: item %s is not on the ground for player %d" % [_id(item), peer])
		# The sender still gets an answer to its PickUp, as if ItemOnGround had rejected it.
		if ctx.command != null:
			ctx.reject(ctx.command, ItemOnGround.UNAVAILABLE)
		return
	var before := held_by(ctx.state, peer)
	var spot := item.position
	var belted: ItemState = null
	var rests: ItemState = null
	if before != null:
		if not before.kind.is_two_handed() and player.belt_item < 0:
			belted = before
			belted.where = ItemState.Where.BELT
			player.belt_item = belted.id
		else:
			rests = before
	item.where = ItemState.Where.HAND
	item.rest_tick = -1
	item.holder = peer
	player.held_item = item.id
	ctx.emit(ItemPickedUpEvent.new(peer, item.id, belted.id if belted != null else -1))
	if rests != null:
		place(ctx, rests, spot, SWAP)


## `peer`'s hand and belt items change places; either may be empty. Swapped (everyone). The rule's
## conditions (CarriesItem, HandNotTwoHanded) refuse a swap with both slots empty or a two-handed
## item in the hand; one that would put a two-handed item on the belt here is a rule error,
## logged, and nothing moves: the sender's Swap is rejected with `two_handed`, as `take` rejects its
## own rule error.
static func swap(ctx: MatchContext, peer: int) -> void:
	var player := ctx.state.player(peer)
	if player == null:
		ctx.error("swap: no player %d" % peer)
		return
	var hand := held_by(ctx.state, peer)
	var belt := belted_by(ctx.state, peer)
	if hand != null and hand.kind.is_two_handed():
		ctx.error("swap: player %d holds two-handed item %d" % [peer, hand.id])
		if ctx.command != null:
			ctx.reject(ctx.command, HandNotTwoHanded.TWO_HANDED)
		return
	player.held_item = belt.id if belt != null else -1
	player.belt_item = hand.id if hand != null else -1
	if belt != null:
		belt.where = ItemState.Where.HAND
	if hand != null:
		hand.where = ItemState.Where.BELT
	ctx.emit(SwappedEvent.new(peer))


## `item` comes to rest at `at` for `cause`: on the ground, out of any hand, belt or flight.
## Emits ItemPlaced to everyone, then raises item_rested (Delivery's check runs on it, §7.1).
static func place(ctx: MatchContext, item: ItemState, at: Vector3, cause: StringName) -> void:
	lay(ctx, item, at)
	ctx.emit(ItemPlacedEvent.new(item.id, at, cause))
	raise_rested(ctx, item, cause)


## `item` lies on the ground at `at` from this tick: out of any hand, belt or flight, its rest tick
## ctx.tick, so VanishTicks counts its time from now. The one writer of an item's ground state
## (the cooking ADR, CE3): every move that leaves an item lying comes through here. Emits nothing;
## the caller announces the move (place(): ItemPlaced and item_rested; a deal: ItemSpawned).
static func lay(ctx: MatchContext, item: ItemState, at: Vector3) -> void:
	_release(ctx, item)
	item.where = ItemState.Where.GROUND
	item.holder = 0
	item.position = at
	item.flight = null
	item.rest_tick = ctx.tick


## A new item of `kind` lying at `at` from this tick (MatchState.add_item, then lay()), or null,
## with the error logged, when every item id is in use. Emits nothing: a deal emits ItemSpawned and
## raises item_rested (raise_rested) itself.
static func spawn(ctx: MatchContext, kind: ItemKind, at: Vector3) -> ItemState:
	var item := ctx.state.add_item(kind, at)
	if item == null:
		ctx.error("spawn: every item id is in use; no %s at %s" % [kind.id, at])
		return null
	lay(ctx, item, at)
	return item


## `item`, at rest, becomes locked where it lies (a delivered package, Delivery 2f): not
## interactive (no PickUp takes it) and not lying, so it never vanishes. Emits nothing: the part
## that locks it announces it (PackageDelivered).
static func lock(item: ItemState) -> void:
	item.where = ItemState.Where.LOCKED
	item.rest_tick = -1


## `item` leaves the match for good (VanishTicks; C1's cap of a given kind): out of any hand or
## belt that held it, removed from MatchState, its id queued for reuse (MatchState.remove_item,
## CE3); ItemVanished to everyone. Raises no fact.
static func vanish(ctx: MatchContext, item: ItemState) -> void:
	_release(ctx, item)
	ctx.state.remove_item(item.id)
	ctx.emit(ItemVanishedEvent.new(item.id))


## `item` leaves the hand or belt that holds it into `flight` (§7.1.16): FLYING, held by nobody,
## its position the flight's origin. The launch tick is this one, in which FlightTicks does not
## move it. Emits nothing: the throw's own effect announces it. FlightTicks ends the flight.
static func launch(ctx: MatchContext, item: ItemState, flight: ItemFlight) -> void:
	_release(ctx, item)
	flight.launch_tick = ctx.tick
	item.where = ItemState.Where.FLYING
	item.rest_tick = -1
	item.holder = 0
	item.position = flight.origin
	item.flight = flight


## Where a thrown item rests when its flight ends over no floor (TD11 (a)): the floor below the
## thrower's feet `feet` (its last accepted position, lifted as for a drop), asked once at the
## launch and kept in the flight. NO_FLOOR when there is none there either. Never the eye less
## the eye height: Items.eye_of stands on the footprint, so at a ledge's edge that point is in the
## air.
static func fallback_rest(ctx: MatchContext, feet: Vector3) -> Vector3:
	return ctx.world.floor_below(lifted(feet))


## Drops the items `peer` carries, the hand's first, then the belt's, to the floor below the
## player's last accepted position (WorldQuery.floor_below, asked once from just above the feet:
## Items.lifted), never in mid-air: for each, ItemPlaced (`cause`: leave), then item_rested. With
## no floor below (a level without one there) they rest at that position, and the error is logged.
## The life rule (2g) calls this after the life state changed and after player_left was raised
## (§3.4, §9.2); a death places the items at the body instead (place_carried), which was found the
## same way.
static func drop_carried(ctx: MatchContext, peer: int, cause: StringName) -> void:
	if held_by(ctx.state, peer) == null and belted_by(ctx.state, peer) == null:
		return
	var from := ctx.state.player(peer).position
	var at := ctx.world.floor_below(lifted(from))
	if at == WorldQuery.NO_FLOOR:
		ctx.error("drop: no floor below %s for the items of player %d" % [from, peer])
		at = from
	place_carried(ctx, peer, at, cause)


## Places the items `peer` carries at `at` for `cause`, the hand's first, then the belt's: a
## death's at the body (LifeRules.die), a leave's below the player (drop_carried).
static func place_carried(ctx: MatchContext, peer: int, at: Vector3, cause: StringName) -> void:
	var hand := held_by(ctx.state, peer)
	if hand != null:
		place(ctx, hand, at, cause)
	# Looked up after the hand's item_rested, whose reactions ran in between.
	var belt := belted_by(ctx.state, peer)
	if belt != null:
		place(ctx, belt, at, cause)


## Raises item_rested for `item`, at rest where it is, with `cause` (§9.2). Use it for an item
## that came to rest without ItemPlaced: the spawn (`SPAWN`), after ItemSpawned.
static func raise_rested(ctx: MatchContext, item: ItemState, cause: StringName) -> void:
	var fact := Fact.new(Facts.ITEM_RESTED)
	fact.item = item.id
	fact.position = item.position
	fact.cause = cause
	ctx.raise_fact(fact)


## The markers of `tag` in the level being entered, in level order, on which no item rests: a
## deal puts at most one item on a marker (§3.3, §9.6), so every part that places items in a deal
## (SpawnItems, Delivery's packages) draws from these. An item in flight rests nowhere yet (its
## position is the launch's origin). Needs ctx.layout.
static func free_markers(ctx: MatchContext, tag: StringName) -> PackedVector3Array:
	var free := PackedVector3Array()
	for at: Vector3 in ctx.layout.positions(tag):
		var taken := false
		for item: ItemState in ctx.state.items.values():
			if not item.is_carried() and not item.is_in_flight() and item.position == at:
				taken = true
				break
		if not taken:
			free.append(at)
	return free


## `player`'s eye for the item rules (InSight, PutDownInFront) and the knife's hit (Strike): the
## floor it stands on at its last accepted position (WorldQuery.stand_floor_below, the capsule's
## footprint, E10) raised by the mode's PlayerRules.eye_height_m. A jump does not raise it, so a
## player cannot see or put an item over a wall from the top of a jump. With no floor below, the
## eye is raised from the position itself.
static func eye_of(ctx: MatchContext, player: PlayerState) -> Vector3:
	var base := player.position
	var ground := ctx.world.stand_floor_below(lifted(base))
	if ground != WorldQuery.NO_FLOOR:
		base.y = ground.y
	return base + Vector3.UP * ctx.state.player_rules.eye_height_m


## `point` lifted by SURFACE_CLEARANCE_M, off the surface it lies on.
static func lifted(point: Vector3) -> Vector3:
	return point + Vector3.UP * SURFACE_CLEARANCE_M


## Empties the hand or belt slot that holds `item`, if any.
static func _release(ctx: MatchContext, item: ItemState) -> void:
	if not item.is_carried():
		return
	var holder := ctx.state.player(item.holder)
	if holder != null and holder.held_item == item.id:
		holder.held_item = -1
	if holder != null and holder.belt_item == item.id:
		holder.belt_item = -1


static func _id(item: ItemState) -> String:
	return str(item.id) if item != null else "none"
