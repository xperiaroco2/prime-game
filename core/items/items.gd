class_name Items
extends RefCounted
## The hand and belt slots and how items come to rest (ARCHITECTURE §7.1, §9.2, §9.4; vision
## revision 1, Two hands): the one place that moves an item between the ground, a hand and a belt,
## emits ItemPickedUp, Swapped and ItemPlaced, and raises the fact `item_rested`. The parts of
## core/items/ call it, and so do the parts of later stages:
##
## A player's three places (PlayerState.places: the hand and the two belt slots, GDD §6 "Drawing
## from the belt"): an item keeps its place, the selected place is in the hand. A take or a give
## fills the selected place when it is empty, else the lowest free place, which becomes selected
## (the hand item stays in its place, now on the belt); with all three full the hand item leaves.
##
## - take(): a pickup, into the hand; the hand item stays on the belt or rests where the picked one
##   lay. Beside a two-handed hand item a one-handed picked item goes onto the belt instead
##   (give()'s belt move, the cooking ADR CE21).
## - give(): an item a source hands out (a box's, a bed's, the grill's take; the cooking ADR §2's
##   table, CD3 (b), CD5 (b), CE19, CE20) goes to a player, who makes room: the hand item stays on
##   the belt when a place is free, else it is put down at the taker's feet; beside a two-handed
##   hand item the new item goes onto the belt, a full belt's lower item first down at the feet.
## - select(), back(): another place comes into the hand (a Draw: keys 1, 2, 3 and the wheel; X:
##   back to the place held last); a two-handed hand item is put down at the feet first.
## - change_kind(): an item becomes another kind, in place (the cooking ADR, CE4): ItemChanged.
## - lock_at(), lay_on_station(): an item goes onto a station (the cooking ADR, CE5): locked at
##   the station's spot (a patty on the grill, an ingredient on a plate), or lying there,
##   interactive, with item_rested (`on_station`; a wrong ingredient at a place until #1101, no
##   caller since). The station's own event announces both.
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
##   a throw's landing, give()'s put-down at the feet), spawn() (a deal's spawn) and
##   lay_on_station() (no caller since #1101). Emits nothing.
## - spawn(): a new item of a kind lying at a spot (MatchState.add_item, then lay()); the deals
##   emit ItemSpawned and raise item_rested themselves.
## - lock(): an item at rest becomes locked where it is (a delivered package): not interactive,
##   not lying, so it never vanishes.
## - vanish(): an item leaves the match for good (VanishTicks; C1's cap): ItemVanished to everyone,
##   its id freed for reuse (MatchState.remove_item).
##
## A move into a hand, onto a belt, into flight or into the locked state (take(), give(),
## launch(), lock(), lock_at()) clears the rest tick. Every lay and every move into a hand, onto a
## belt, into flight or into the locked state bumps the move serial, ItemState.moves (the photo
## ADR, PE17); select() between one player's own places does not.
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
## item_rested only: the item was laid on a station, interactive (the cooking ADR CE5's wrong
## ingredient at a place until #1101); the station's own event announces it.
const ON_STATION := &"on_station"


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


## The first item `peer` carries on the belt (the lower-numbered belt place's, else the higher
## one's), or null. Every belt item: belted_items().
static func belted_by(state: MatchState, peer: int) -> ItemState:
	var belt := belted_items(state, peer)
	return belt[0] if not belt.is_empty() else null


## The items `peer` carries on the belt, in place order; empty without a player.
static func belted_items(state: MatchState, peer: int) -> Array[ItemState]:
	var belt: Array[ItemState] = []
	var player := state.player(peer)
	if player == null:
		return belt
	for at in player.belt_places():
		var item: ItemState = state.items.get(player.places[at])
		if item != null:
			belt.append(item)
	return belt


## The items `peer` carries, the hand's first, then the belt's in place order
## (PlayerState.carried_items); empty without a player.
static func carried_by(state: MatchState, peer: int) -> Array[ItemState]:
	var carried: Array[ItemState] = []
	var player := state.player(peer)
	if player == null:
		return carried
	for id in player.carried_items():
		var item: ItemState = state.items.get(id)
		if item != null:
			carried.append(item)
	return carried


## `item`, lying on the ground, goes to `peer` (vision revision 1, Two hands, as the cooking ADR's
## CE21 amends it). Beside a two-handed hand item a one-handed `item` goes onto the belt through
## give()'s belt move (a full belt's item down at the taker's feet first, ItemPlaced `put_down`;
## ItemPickedUp with `belted` the item itself), the two-handed item staying in the hand.
## Otherwise `item` goes into the hand (GDD §6): into the selected place when it is empty; beside a
## one-handed hand item into the lowest free place, which becomes selected, the hand item staying
## in its place, now on the belt; with all three places full the one-handed hand item drops at the
## taker's feet first (ItemPlaced `put_down` and item_rested, as give()'s; GDD §6, #1218) and
## `item` takes the selected place; beside a two-handed hand item a two-handed `item` (the belt
## holds only a one-handed item) swaps: the hand item rests where the picked-up one lay, a spot
## already known to be valid (§7.1). Emits ItemPickedUp (with `belted`, the hand item that went
## onto the belt, E29, and `place`), then for a hand item that rests ItemPlaced (swap) and
## item_rested. The rule's conditions checked the ground, the reach and the sight; an item that is
## not on the ground here is a rule error, and the sender of the intent gets `unavailable`.
static func take(ctx: MatchContext, peer: int, item: ItemState) -> void:
	var player := ctx.state.player(peer)
	if player == null or item == null or item.where != ItemState.Where.GROUND:
		ctx.error("take: item %s is not on the ground for player %d" % [_id(item), peer])
		# The sender still gets an answer to its PickUp, as if ItemOnGround had rejected it.
		if ctx.command != null:
			ctx.reject(ctx.command, ItemOnGround.UNAVAILABLE)
		return
	var before := held_by(ctx.state, peer)
	if before != null and before.kind.is_two_handed() and not item.kind.is_two_handed():
		_onto_belt(ctx, peer, item)
		return
	var spot := item.position
	var belted: ItemState = null
	var rests: ItemState = null
	var into := player.selected_place
	if before != null:
		var free := _free_place(player)
		if before.kind.is_two_handed():
			rests = before
		elif free >= 0:
			belted = before
			into = free
		else:
			place(ctx, before, _feet(ctx, player), PUT_DOWN)
	_into_hand(ctx, peer, item, belted, into)
	if rests != null:
		place(ctx, rests, spot, SWAP)


## `item`, a new item from a source or one locked on a station (a box's, a bed's or the grill's
## take, the cooking ADR §2), goes to `peer`, who makes room (§2's table; CD3 (b), CD5 (b), both
## the engineer's; CE19, CE20):
## - an empty hand (the selected place empty): into the hand;
## - a one-handed hand item and a free place: into the lowest free place, which becomes selected;
##   the hand item stays in its place, now on the belt (ItemPickedUp's `belted`, as a pickup's);
## - a one-handed hand item and all three places full: into the hand, the hand item put down at
##   the taker's feet first (ItemPlaced `put_down`, then item_rested);
## - a two-handed hand item: onto the belt's lowest free place, a full belt's lower item put down
##   at the feet first; the two-handed item stays in the hand, and ItemPickedUp's `belted` names
##   `item` itself.
## The feet: WorldQuery.rest_position from the eye straight down, the spot PutDownInFront uses for a
## facing with no horizontal direction. A given kind is one-handed (CE14): a two-handed one, or an
## item carried or in flight, is a rule error, logged, and nothing moves. Emits ItemPickedUp last.
static func give(ctx: MatchContext, peer: int, item: ItemState) -> void:
	var player := ctx.state.player(peer)
	if player == null or item == null or item.is_carried() or item.is_in_flight():
		ctx.error("give: item %s cannot go to player %d" % [_id(item), peer])
		return
	if item.kind.is_two_handed():
		ctx.error("give: item %d of kind %s is two-handed" % [item.id, item.kind.id])
		return
	var hand := held_by(ctx.state, peer)
	if hand != null and hand.kind.is_two_handed():
		_onto_belt(ctx, peer, item)
		return
	var belted: ItemState = null
	var into := player.selected_place
	if hand != null:
		var free := _free_place(player)
		if free >= 0:
			belted = hand
			into = free
		else:
			place(ctx, hand, _feet(ctx, player), PUT_DOWN)
	_into_hand(ctx, peer, item, belted, into)


## `item` becomes `kind` where it is (the cooking ADR, CE4: a patty on the grill turning fried,
## then burnt): it keeps its id, its place, its holder and its rest tick. ItemChanged to everyone;
## nothing at all when it already is that kind. A missing item or kind is a rule error, logged.
static func change_kind(ctx: MatchContext, item: ItemState, kind: ItemKind) -> void:
	if item == null or kind == null:
		ctx.error("change_kind: item %s or its new kind is missing" % _id(item))
		return
	if item.kind == kind:
		return
	item.kind = kind
	ctx.emit(ItemChangedEvent.new(item.id, kind.id))


## `item` (in a hand, say) is locked at `at`, a station's spot (the cooking ADR, CE5: a patty on
## the grill, a right ingredient on a place): out of any hand or belt, held by nobody, not
## interactive (no PickUp takes it) and not lying, so it never vanishes. Only give() hands it out
## again. Emits nothing: the station's event (GrillLoaded, IngredientPlaced) announces it. No item
## is a rule error, logged, and nothing moves.
static func lock_at(ctx: MatchContext, item: ItemState, at: Vector3) -> void:
	if item == null:
		ctx.error("lock_at: no item to lock at %s" % at)
		return
	_release(ctx, item)
	item.holder = 0
	item.position = at
	item.flight = null
	lock(item)


## `item` lies on the ground at `at`, a station's spot, interactive (the cooking ADR, CE5: a wrong
## ingredient at a place, which PickUp takes back; no caller since #1101 checks a burger when it
## is served, kept with its test for a station that lays an item so), its rest tick this tick
## (lay()); raises item_rested with the cause `on_station`. No ItemPlaced: the station's event
## says where it went. No item is a rule error, logged, and nothing moves.
static func lay_on_station(ctx: MatchContext, item: ItemState, at: Vector3) -> void:
	if item == null:
		ctx.error("lay_on_station: no item to lay at %s" % at)
		return
	lay(ctx, item, at)
	raise_rested(ctx, item, ON_STATION)


## `peer`'s place `to` (0..2) comes into the hand (GDD §6, a Draw: keys 1, 2, 3 and the wheel): the
## hand item stays in its place, now on the belt, and the place held so far becomes the last place
## (X goes back to it). An empty place is an empty hand. A two-handed hand item is put down at the
## player's feet first (ItemPlaced `put_down`, then item_rested: no refusal), since the belt holds
## only a one-handed item. Swapped (everyone) with the new place. The rule's conditions
## (PlaceInRange, PlaceChanges) refuse a place out of range or the selected one; either here is a
## rule error, logged, and nothing moves: the sender's intent is rejected with that condition's
## reason.
static func select(ctx: MatchContext, peer: int, to: int) -> void:
	var player := ctx.state.player(peer)
	if player == null:
		ctx.error("select: no player %d" % peer)
		return
	if to < 0 or to >= PlayerState.PLACES or to == player.selected_place:
		ctx.error("select: player %d cannot draw place %d" % [peer, to])
		if ctx.command != null:
			var bad := to < 0 or to >= PlayerState.PLACES
			ctx.reject(ctx.command, PlaceInRange.NO_SUCH_PLACE if bad else PlaceChanges.SAME_PLACE)
		return
	var hand := held_by(ctx.state, peer)
	if hand != null and hand.kind.is_two_handed():
		place(ctx, hand, _feet(ctx, player), PUT_DOWN)
	_move_selection(ctx, player, to)
	ctx.emit(SwappedEvent.new(peer, to))


## X (Swap): `peer`'s last place comes back into the hand (select()), so with one item X moves it
## between the hand and the belt, as the swap of one belt slot did. X keeps V13: the rule's
## conditions (CarriesItem, HandNotTwoHanded) refuse it with every place empty or a two-handed
## item in the hand (GDD §6 puts a two-handed item down only for 1, 2, 3 and the wheel). A
## two-handed hand item here is a rule error, logged, and nothing moves: the sender's Swap is
## rejected with `two_handed`, as `take` rejects its own rule error.
static func back(ctx: MatchContext, peer: int) -> void:
	var player := ctx.state.player(peer)
	if player == null:
		ctx.error("back: no player %d" % peer)
		return
	var hand := held_by(ctx.state, peer)
	if hand != null and hand.kind.is_two_handed():
		ctx.error("back: player %d holds two-handed item %d" % [peer, hand.id])
		if ctx.command != null:
			ctx.reject(ctx.command, HandNotTwoHanded.TWO_HANDED)
		return
	select(ctx, peer, player.last_place)


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
	item.moves += 1


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
	item.moves += 1


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
	item.moves += 1
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
	if carried_by(ctx.state, peer).is_empty():
		return
	var from := ctx.state.player(peer).position
	var at := ctx.world.floor_below(lifted(from))
	if at == WorldQuery.NO_FLOOR:
		ctx.error("drop: no floor below %s for the items of player %d" % [from, peer])
		at = from
	place_carried(ctx, peer, at, cause)


## Places the items `peer` carries at `at` for `cause`, the hand's first, then the belt's in place
## order: a death's at the body (LifeRules.die), a leave's below the player (drop_carried).
static func place_carried(ctx: MatchContext, peer: int, at: Vector3, cause: StringName) -> void:
	# One at a time, looked up again after each item_rested, whose reactions ran in between.
	for _place in PlayerState.PLACES:
		var carried := carried_by(ctx.state, peer)
		if carried.is_empty():
			return
		place(ctx, carried[0], at, cause)


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
## footprint, E10) raised by the mode's PlayerRules.eye_height_m, or crouch_eye_height_m while it is
## crouched (the crouch ADR, KE2). A jump does not raise it, so a
## player cannot see or put an item over a wall from the top of a jump. With no floor below, the
## eye is raised from the position itself.
static func eye_of(ctx: MatchContext, player: PlayerState) -> Vector3:
	var base := player.position
	var ground := ctx.world.stand_floor_below(lifted(base))
	if ground != WorldQuery.NO_FLOOR:
		base.y = ground.y
	return base + Vector3.UP * ctx.state.player_rules.eye_height_of(player.crouched)


## `point` lifted by SURFACE_CLEARANCE_M, off the surface it lies on.
static func lifted(point: Vector3) -> Vector3:
	return point + Vector3.UP * SURFACE_CLEARANCE_M


## give()'s belt move, which take() shares beside a two-handed hand item (CE21): `item` onto the
## belt's lowest free place; with both belt places full the lower one's item is put down at
## `peer`'s feet first (ItemPlaced `put_down`, item_rested). ItemPickedUp with `belted` the item
## itself (CE20) and its place. The hand item and the selection stay as they are.
static func _onto_belt(ctx: MatchContext, peer: int, item: ItemState) -> void:
	var player := ctx.state.player(peer)
	var into := _free_place(player)
	if into < 0:
		into = player.belt_places()[0]
		var full: ItemState = ctx.state.items.get(player.places[into])
		if full != null:
			place(ctx, full, _feet(ctx, player), PUT_DOWN)
	item.holder = peer
	item.rest_tick = -1
	item.moves += 1
	item.where = ItemState.Where.BELT
	player.places[into] = item.id
	ctx.emit(ItemPickedUpEvent.new(peer, item.id, item.id, into))


## `item` into `peer`'s place `into`, held by it, no longer lying; `into` becomes the selected place
## when it is not (_move_selection: the hand item stays in its place, on the belt). ItemPickedUp
## with `belted` (the hand item that went onto the belt, or none) and the place.
static func _into_hand(
	ctx: MatchContext, peer: int, item: ItemState, belted: ItemState, into: int
) -> void:
	var player := ctx.state.player(peer)
	if into != player.selected_place:
		_move_selection(ctx, player, into)
	item.where = ItemState.Where.HAND
	item.rest_tick = -1
	item.moves += 1
	item.holder = peer
	player.places[into] = item.id
	ctx.emit(ItemPickedUpEvent.new(peer, item.id, belted.id if belted != null else -1, into))


## `to` becomes `player`'s selected place and the one held so far its last place: the item there
## (if any) comes into the hand, the old hand item (if any) onto the belt. No move serial bump:
## the items stay with their player.
static func _move_selection(ctx: MatchContext, player: PlayerState, to: int) -> void:
	var hand: ItemState = ctx.state.items.get(player.held_item)
	if hand != null:
		hand.where = ItemState.Where.BELT
	player.last_place = player.selected_place
	player.selected_place = to
	var drawn: ItemState = ctx.state.items.get(player.held_item)
	if drawn != null:
		drawn.where = ItemState.Where.HAND


## `player`'s lowest-numbered empty place, or -1 when all three are full.
static func _free_place(player: PlayerState) -> int:
	return player.places.find(-1)


## Where an item a take displaces is put down (CE19): below `player`'s eye (Items.eye_of), as
## PutDownInFront does for a facing with no horizontal direction. Without PlayerRules (a mode the
## check refuses) the error is logged and the player's last accepted position stands in.
static func _feet(ctx: MatchContext, player: PlayerState) -> Vector3:
	if ctx.state.player_rules == null:
		ctx.error(
			"give: the mode has no PlayerRules; the put-down rests at player %d" % player.peer
		)
		return player.position
	var eye := eye_of(ctx, player)
	return ctx.world.rest_position(eye, eye)


## Empties the place that holds `item`, if any; the selection stays (an empty place is an empty
## hand).
static func _release(ctx: MatchContext, item: ItemState) -> void:
	if not item.is_carried():
		return
	var holder := ctx.state.player(item.holder)
	if holder == null:
		return
	var at := holder.place_of(item.id)
	if at >= 0:
		holder.places[at] = -1


static func _id(item: ItemState) -> String:
	return str(item.id) if item != null else "none"
