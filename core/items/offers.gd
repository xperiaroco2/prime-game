class_name Offers
extends RefCounted
## The open hand-over offers (#1434; ARCHITECTURE §7.1, §9.4; GDD §6 "Handing over"): a living
## player holding an item aims at another and presses E (HandOver); the item stays in the giver's
## hand, held out, until the receiver presses E on the giver (TakeOffer) and takes it as it would
## pick it up from the floor (Items.take_offered). One offer per giver, kept in the match's
## per-part state (MatchState.part_state, cleared by ResetMatch), never in a snapshot: every peer
## learns of it through the public OfferMade and OfferEnded.
##
## An offer is live while its item is still the giver's hand item (live()). It ends on the take,
## on the giver's CancelOffer, and through OfferTicks when the item leaves the hand (a Put down,
## Swap, Draw or Throw), when either player is no longer present, alive and standing (limp, downed,
## dead, gone), out of reach, or after the timeout; EndOffers ends every one on a row out of the
## phases that list OfferTicks. Each end emits one OfferEnded.

const PART_KEY := &"offers"
## The reason a TakeOffer or a CancelOffer gets when there is no live offer for it (OfferedTo,
## Offering): the same answer for no offer and for an offer to someone else, so a refusal tells
## nothing the public OfferMade did not.
const NO_OFFER := &"no_offer"


## One open offer: `giver` holds item `item` out to `target` since the tick `opened_tick`.
class Offer:
	extends RefCounted
	var giver: int
	var target: int
	var item: int
	var opened_tick: int

	func _init(by: int, to: int, item_id: int, tick: int) -> void:
		giver = by
		target = to
		item = item_id
		opened_tick = tick


## The open offers by giver.
class Table:
	extends RefCounted
	var by_giver: Dictionary[int, Offer] = {}


## `giver`'s open offer, or null; it may no longer be live (live()) until OfferTicks ends it.
static func of_giver(state: MatchState, giver: int) -> Offer:
	return _table(state).by_giver.get(giver)


## `giver`'s offer while its item is still the giver's hand item, else null.
static func live(state: MatchState, giver: int) -> Offer:
	var offer := of_giver(state, giver)
	if offer == null:
		return null
	var hand := Items.held_by(state, giver)
	return offer if hand != null and hand.id == offer.item else null


## Every open offer, in giver order (deterministic).
static func all(state: MatchState) -> Array[Offer]:
	var found: Array[Offer] = []
	var givers := _table(state).by_giver.keys()
	givers.sort()
	for giver: int in givers:
		found.append(_table(state).by_giver[giver])
	return found


## `giver` offers its hand item `item` to `target` (HandOver): OfferMade to everyone. An offer of
## the giver's that is no longer live ends first (OfferEnded); a live one is a rule error (the
## mode's HandOver rule refuses it with a negated Offering), logged, and it ends first too.
static func open(ctx: MatchContext, giver: int, target: int, item: ItemState) -> void:
	if item == null or item.where != ItemState.Where.HAND or item.holder != giver:
		ctx.error("offer: player %d holds no item in the hand to offer" % giver)
		if ctx.command != null:
			ctx.reject(ctx.command, HoldsItem.EMPTY_HAND)
		return
	var old := of_giver(ctx.state, giver)
	if old != null:
		if live(ctx.state, giver) != null:
			ctx.error("offer: player %d already offers item %d" % [giver, old.item])
		close(ctx, old)
	_table(ctx.state).by_giver[giver] = Offer.new(giver, target, item.id, ctx.tick)
	ctx.emit(OfferMadeEvent.new(giver, target))


## `offer` ends (a take, a cancel, OfferTicks, EndOffers): OfferEnded to everyone.
static func close(ctx: MatchContext, offer: Offer) -> void:
	var table := _table(ctx.state)
	if table.by_giver.get(offer.giver) != offer:
		return
	table.by_giver.erase(offer.giver)
	ctx.emit(OfferEndedEvent.new(offer.giver, offer.target))


## `receiver` takes `giver`'s live offer to it (TakeOffer): the item moves as a pick-up from the
## floor would move it (Items.take_offered), then the offer ends. The rule's OfferedTo checked
## the offer; none here is a rule error, logged, and the sender gets `no_offer`.
static func take(ctx: MatchContext, giver: int, receiver: int) -> void:
	var offer := live(ctx.state, giver)
	if offer == null or offer.target != receiver:
		ctx.error("take offer: player %d offers nothing to player %d" % [giver, receiver])
		if ctx.command != null:
			ctx.reject(ctx.command, NO_OFFER)
		return
	Items.take_offered(ctx, receiver, ctx.state.items[offer.item])
	close(ctx, offer)


## Every open offer ends (EndOffers), in giver order.
static func end_all(ctx: MatchContext) -> void:
	for offer: Offer in all(ctx.state):
		close(ctx, offer)


static func _table(state: MatchState) -> Table:
	return state.part_state(PART_KEY, func() -> RefCounted: return Table.new()) as Table
