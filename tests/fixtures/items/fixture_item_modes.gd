class_name FixtureItemModes
extends RefCounted
## Game modes and drivers for the unit tests of core/items/, built in code on FixtureModes.basic()
## (a part's unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): the fixture mode with the eye at 1.6 m; item kinds `package` (no actions) and `tool`
## (a Use rule that notes "tool used"); the mode's actions PickUp (ItemOnGround, InReach 2 m,
## InSight; TakeIntoHand) and PutDown (HoldsItem; PutDownInFront 1 m); Round accepts both from
## the living only; a reaction on item_rested notes "rested <item> <cause> <position>".

const EYE_HEIGHT_M := 1.6
const REACH_M := 2.0
const DISTANCE_M := 1.0


static func basic() -> GameMode:
	var mode := FixtureModes.basic()
	mode.player_rules.eye_height_m = EYE_HEIGHT_M
	mode.item_kinds = [
		item_kind(&"package", []),
		item_kind(&"tool", [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("tool used")])]),
	]
	mode.actions = [pick_up_rule(REACH_M), put_down_rule(DISTANCE_M)]
	mode.reactions = [FixtureModes.rule(Facts.ITEM_RESTED, [], [FixtureRestedNote.new()])]
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts.append(AcceptSpec.of(Intents.PICK_UP, AcceptSpec.From.LIVING))
	round_spec.accepts.append(AcceptSpec.of(Intents.PUT_DOWN, AcceptSpec.From.LIVING))
	return mode


static func item_kind(id: StringName, actions: Array[Rule]) -> ItemKind:
	var kind := ItemKind.new()
	kind.id = id
	kind.display_name = String(id).capitalize()
	kind.spawn_tag = id
	kind.actions = actions
	return kind


static func pick_up_rule(reach_m: float) -> Rule:
	var reach := InReach.new()
	reach.reach_m = reach_m
	return FixtureModes.rule(
		Intents.PICK_UP, [ItemOnGround.new(), reach, InSight.new()], [TakeIntoHand.new()]
	)


static func put_down_rule(distance_m: float) -> Rule:
	var put := PutDownInFront.new()
	put.distance_m = distance_m
	return FixtureModes.rule(Intents.PUT_DOWN, [HoldsItem.new()], [put])


## A match of `mode` asking `world`, that keeps its history, with `peers` joined, ready and in
## the round.
static func in_round(
	mode: GameMode, peers: Array[int], world: WorldQuery = null, seed_value: int = 7
) -> Match:
	var game := Match.new(
		mode, seed_value, world if world != null else FlatWorldQuery.new(), FixtureModes.layouts()
	)
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## Sets `peer`'s last accepted position (what a MoveClaim the movement rule accepted leaves).
static func stand(game: Match, peer: int, at: Vector3) -> void:
	game.state.player(peer).position = at


## An item of the mode's kind `kind_id` lying at `at`, straight into the match state.
static func lay(game: Match, kind_id: StringName, at: Vector3) -> ItemState:
	return game.state.add_item(game.mode.find_item_kind(kind_id), at)


static func pick_up(game: Match, peer: int, item: ItemState, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.PICK_UP, peer, {"item": item.id}, seq)


static func put_down(game: Match, peer: int, facing: Vector3, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.PUT_DOWN, peer, {"facing": facing}, seq)


## The names of the events `peer` received after its first `skip` events.
static func names_after(game: Match, peer: int, skip: int) -> Array[StringName]:
	return game.view_of(peer).event_names().slice(skip)
