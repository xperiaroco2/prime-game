class_name FixtureHandOverModes
extends RefCounted
## The hand-over (#1389) for the unit tests of core/items/ and core/life/, built in code on
## FixtureItemModes.basic() (a part's unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): FixtureItemModes.basic() (`package` two-handed, `tool` one-handed and not handable,
## PickUp and PutDown) with the kinds `gift` and `cup` (one-handed, handable), Swap (to put the
## hand item on the belt), and the base mode's HandOver as an action: HoldsItem, HandNotTwoHanded,
## HandHandable, TargetLiving, TargetInReach (2 m), TargetInSight (at the eye); HandOver. Round
## accepts HandOver from the living only.

const REACH_M := 2.0


static func basic() -> GameMode:
	return handing(FixtureItemModes.swapping(FixtureItemModes.basic()))


## `mode` with the kinds `gift` and `cup`, the HandOver rule and the Round's HandOver row.
static func handing(mode: GameMode) -> GameMode:
	for id: StringName in [&"gift", &"cup"]:
		var kind := FixtureItemModes.item_kind(id, [])
		kind.handable = true
		mode.item_kinds.append(kind)
	mode.actions.append(hand_over_rule(conditions()))
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts.append(AcceptSpec.of(Intents.HAND_OVER, AcceptSpec.From.LIVING))
	return mode


## The six conditions, in the base mode's order.
static func conditions() -> Array[Condition]:
	var reach := TargetInReach.new()
	reach.reach_m = REACH_M
	var sight := TargetInSight.new()
	sight.at_eye = true
	return [
		HoldsItem.new(),
		HandNotTwoHanded.new(),
		HandHandable.new(),
		TargetLiving.new(),
		reach,
		sight
	]


static func hand_over_rule(holding: Array[Condition]) -> Rule:
	return FixtureModes.rule(Intents.HAND_OVER, holding, [HandOver.new()])


## An item of the kind `kind_id` laid at `peer`'s feet and picked up by it, through its PickUp.
static func hold(game: Match, peer: int, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, game.state.player(peer).position)
	FixtureItemModes.pick_up(game, peer, item)
	return item


static func hand_over(game: Match, peer: int, target: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.HAND_OVER, peer, {"target": target}, seq)


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
