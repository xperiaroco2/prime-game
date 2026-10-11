class_name FixtureGiveModes
extends RefCounted
## Game modes and drivers for the unit tests of an Interact naming an item and of GiveItem (the
## cooking ADR's CE1 to CE3, #770), built in code (a part's unit tests never load `content/`,
## ARCHITECTURE §9.6). Its numbers are fixture values, not decisions.
##
## basic(): FixtureStationModes.plain() (PickUp, PutDown, the two-handed package, the tool, the
## `panel` stations 1 and 2 and Round accepting Interact from the living) plus the item kinds `bun`
## (one-handed, max_items BUN_CAP, no rules) and `box` (two-handed), whose target_actions hold the
## take: Interact with ItemOnGround, InReach (REACH_M), InSight; GiveItem(bun).

const BUN_CAP := 2
const REACH_M := 2.0
## Where P1 stands (round_player markers are at (10 + i, 0, 5); the panels far away at z 20).
const HERE := Vector3(10, 0, 5)
## Where the box lies: within REACH_M of HERE, on the flat fixture world.
const BOX_AT := Vector3(11, 0, 5)


static func basic() -> GameMode:
	var mode := FixtureStationModes.plain()
	var bun := FixtureItemModes.item_kind(&"bun", [])
	bun.max_items = BUN_CAP
	var box := FixtureItemModes.item_kind(&"box", [], 2)
	box.target_actions = [take_rule(bun)]
	mode.item_kinds.append(bun)
	mode.item_kinds.append(box)
	return mode


## The box's take: a bun of `given` from a box on the ground within reach and in sight.
static func take_rule(given: ItemKind) -> Rule:
	var reach := InReach.new()
	reach.reach_m = REACH_M
	var give := GiveItem.new()
	give.kind = given
	return FixtureModes.rule(Intents.INTERACT, [ItemOnGround.new(), reach, InSight.new()], [give])


## A match of `mode` (basic() by default) in the round with `peers`, P1 standing at HERE and a box
## lying at BOX_AT.
static func in_round(peers: Array[int], mode: GameMode = null) -> Match:
	var game := FixtureStationModes.in_round(mode if mode != null else basic(), peers)
	FixtureItemModes.stand(game, peers[0], HERE)
	FixtureItemModes.lay(game, &"box", BOX_AT)
	return game


## The box basic()'s in_round() laid.
static func box_of(game: Match) -> ItemState:
	for item: ItemState in game.state.items.values():
		if item.kind.id == &"box":
			return item
	return null


## A bun lying at `at` straight in the match state, as if it came to rest at `rest_tick`.
static func lay_bun(game: Match, at: Vector3, rest_tick: int) -> ItemState:
	var bun := FixtureItemModes.lay(game, &"bun", at)
	bun.rest_tick = rest_tick
	return bun


## `peer` sends Interact naming the item `item` (and no station), applied on the next host tick.
static func interact_item(game: Match, peer: int, item: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": -1, "item": item}, seq)


## The ids of the items of `kind_id` in the match, lowest first.
static func ids_of(game: Match, kind_id: StringName) -> Array[int]:
	var found: Array[int] = []
	for item: ItemState in game.state.items.values():
		if item.kind.id == kind_id:
			found.append(item.id)
	found.sort()
	return found
