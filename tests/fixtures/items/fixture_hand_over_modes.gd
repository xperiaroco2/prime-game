class_name FixtureHandOverModes
extends RefCounted
## The hand-over offer (#1389, #1434) for the unit tests of core/items/ and core/life/, built in
## code on FixtureItemModes.basic() (a part's unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): FixtureItemModes.basic() (`package` two-handed, `tool` one-handed, PickUp and PutDown)
## with the kinds `gift` and `cup` (one-handed), Swap and Draw (to move the hand item away), and
## the base mode's offer as actions: HandOver (HoldsItem, a negated Offering, TargetLiving,
## TargetInReach (2 m), TargetInSight (at the eye)), TakeOffer (OfferedTo, TargetLiving,
## TargetInReach (2 m), TargetInSight (at the eye)) and CancelOffer (Offering). Round accepts the
## three from the living only, lists an OfferTicks (5 s, 2 m), and every row out of it runs an
## EndOffers.

const REACH_M := 2.0
const TIMEOUT_S := 5.0


static func basic() -> GameMode:
	return handing(FixtureItemModes.drawing(FixtureItemModes.swapping(FixtureItemModes.basic())))


## `mode` with the kinds `gift` and `cup`, the offer's rules, the Round's rows and its OfferTicks.
static func handing(mode: GameMode) -> GameMode:
	for id: StringName in [&"gift", &"cup"]:
		mode.item_kinds.append(FixtureItemModes.item_kind(id, []))
	mode.actions.append(hand_over_rule(conditions()))
	mode.actions.append(take_offer_rule())
	mode.actions.append(cancel_offer_rule())
	var round_spec := mode.find_phase(&"round")
	for intent: StringName in [Intents.HAND_OVER, Intents.TAKE_OFFER, Intents.CANCEL_OFFER]:
		round_spec.accepts.append(AcceptSpec.of(intent, AcceptSpec.From.LIVING))
	round_spec.tick_systems.append(offer_ticks())
	for row: Transition in mode.transitions:
		if row.from == &"round" and row.to != &"round":
			row.actions.append(EndOffers.new())
	return mode


## The HandOver rule's five conditions, in the base mode's order.
static func conditions() -> Array[Condition]:
	var one := Offering.new()
	one.negate = true
	return [HoldsItem.new(), one, TargetLiving.new(), reach(), sight()]


static func hand_over_rule(holding: Array[Condition]) -> Rule:
	return FixtureModes.rule(Intents.HAND_OVER, holding, [HandOver.new()])


static func take_offer_rule() -> Rule:
	var holding: Array[Condition] = [OfferedTo.new(), TargetLiving.new(), reach(), sight()]
	return FixtureModes.rule(Intents.TAKE_OFFER, holding, [TakeOffer.new()])


static func cancel_offer_rule() -> Rule:
	var holding: Array[Condition] = [Offering.new()]
	return FixtureModes.rule(Intents.CANCEL_OFFER, holding, [CancelOffer.new()])


static func offer_ticks() -> OfferTicks:
	var ticks := OfferTicks.new()
	ticks.timeout_s = TIMEOUT_S
	ticks.reach_m = REACH_M
	return ticks


static func reach() -> TargetInReach:
	var made := TargetInReach.new()
	made.reach_m = REACH_M
	return made


static func sight() -> TargetInSight:
	var made := TargetInSight.new()
	made.at_eye = true
	return made


## An item of the kind `kind_id` laid at `peer`'s feet and picked up by it, through its PickUp.
static func hold(game: Match, peer: int, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, game.state.player(peer).position)
	FixtureItemModes.pick_up(game, peer, item)
	return item


static func hand_over(game: Match, peer: int, target: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.HAND_OVER, peer, {"target": target}, seq)


static func take_offer(game: Match, peer: int, giver: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.TAKE_OFFER, peer, {"target": giver}, seq)


static func cancel_offer(game: Match, peer: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.CANCEL_OFFER, peer, {}, seq)


## Every item's and player's state that a hand-over may change, as one comparable string.
static func signature(game: Match) -> String:
	var parts := PackedStringArray()
	for id: int in game.state.items:
		var item: ItemState = game.state.items[id]
		parts.append(
			(
				"%d:%d:%d:%d:%s:%d"
				% [id, item.where, item.holder, item.moves, item.position, item.rest_tick]
			)
		)
	for player: PlayerState in game.state.players.values():
		parts.append(
			"p%d:%s:%d:%s" % [player.peer, player.places, player.selected_place, player.position]
		)
	return ",".join(parts)


## `peer` lies limp from now on (the mode lists no LimpTicks, so it stays limp): what GoLimp leaves.
static func make_limp(game: Match, peer: int) -> void:
	game.state.player(peer).limp = LimpState.new(1 << 30)
