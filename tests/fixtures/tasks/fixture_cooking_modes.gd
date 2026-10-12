class_name FixtureCookingModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of Cooking (core/tasks/cooking.gd, #772),
## built in code (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its kinds, ids and
## numbers are fixture values, not the engineer's provisional ones (those land in data, C6).
##
## basic(burgers): FixtureCombatModes.raising() (PickUp, PutDown, the two-handed package, the knife,
## the raise; Round lists LifeTicks, then ChannelTicks) with VanishTicks added to Round, Interact
## from the living in Round, the settings `tasks` (1), `banned_task_types` and `burgers` (`burgers`
## by default, 0 to MOST_BURGERS), and the task type Cooking in place of the mode's: the display
## kinds `order_board` and `herb_board`, the kinds `grill`, `herb_bed` and `place` with the use
## rule (FixtureGeneratorModes.kind), the buns `bun_a` and `bun_b`, the raw patties `raw_a` and
## `raw_b`, the fried `fried_a` and `fried_b`, `burnt`, the herbs `herb_a` to `herb_c` (no spawn
## tag, `vanish_seconds` VANISH, the given ones `max_items` CAP) and one two-handed box per bun and
## raw patty (`box_bun_a` ...), each on its own tag with FixtureGiveModes' take. The deal
## (DealTasks) runs before PlacePlayers on `lobby, all_ready -> round`.
##
## layouts(): the fixture lobby and map plus the cooking markers below, far from the players.

const MOST_BURGERS := 3
const CAP := 64
const VANISH := 60
const FRY_SECONDS := 1.0
const BURN_SECONDS := 2.0
const ORDER_BOARD_AT := Vector3(0, 0, 20)
const HERB_BOARD_AT := Vector3(2, 0, 20)
const GRILL_AT := Vector3(4, 0, 20)
## The bed markers, in level order: one per herb.
const BED_SPOTS: Array[Vector3] = [Vector3(6, 0, 20), Vector3(8, 0, 20), Vector3(10, 0, 20)]
## The place markers, in level order: one per burger at most.
const PLACE_SPOTS: Array[Vector3] = [Vector3(0, 0, 30), Vector3(3, 0, 30), Vector3(6, 0, 30)]
## The box kinds, in the type's order, and the item kind each gives.
const BOXES := {
	&"box_bun_a": &"bun_a", &"box_bun_b": &"bun_b", &"box_raw_a": &"raw_a", &"box_raw_b": &"raw_b"
}
## Each box tag's markers: two each, so the deal draws one.
const BOX_X := 20.0


static func basic(burgers: int = 1) -> GameMode:
	var mode := FixtureCombatModes.raising()
	_add_cooking(mode, burgers)
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


## FixtureWinModes.basic() (DealRoles, DealTasks, the clock, the win conditions, EndMatch, and
## ResetMatch on `end, back -> lobby`) with Cooking in place of Delivery.
static func winning(burgers: int = 1) -> GameMode:
	var mode := FixtureWinModes.basic(0)
	mode.settings.erase(mode.find_setting(&"packages"))
	_add_cooking(mode, burgers)
	return mode


## Adds the settings, the type and its item kinds, Interact from the living and VanishTicks in
## Round.
static func _add_cooking(mode: GameMode, burgers: int) -> void:
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"burgers", burgers, 0, MOST_BURGERS))
	var type := cooking_type()
	for kind: ItemKind in type.ingredients():
		mode.item_kinds.append(kind)
	for kind: ItemKind in type.boxes:
		mode.item_kinds.append(kind)
	mode.task_types = [type]
	var round_phase := mode.find_phase(&"round")
	round_phase.accepts.append(AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(VanishTicks.new())


static func cooking_type() -> Cooking:
	var made := Cooking.new()
	made.id = &"cooking"
	made.description = "Cook the burgers on the order board."
	made.order_board = board(&"order_board")
	made.herb_board = board(&"herb_board")
	made.grill = FixtureGeneratorModes.kind(&"grill")
	made.herb_bed = FixtureGeneratorModes.kind(&"herb_bed")
	made.place = FixtureGeneratorModes.kind(&"place")
	made.buns = [ingredient(&"bun_a", true), ingredient(&"bun_b", true)]
	made.raw_patties = [ingredient(&"raw_a", true), ingredient(&"raw_b", true)]
	made.fried_patties = [ingredient(&"fried_a", false), ingredient(&"fried_b", false)]
	made.burnt = ingredient(&"burnt", false)
	made.herbs = [
		ingredient(&"herb_a", true), ingredient(&"herb_b", true), ingredient(&"herb_c", true)
	]
	var given: Array[ItemKind] = []
	given.append_array(made.buns)
	given.append_array(made.raw_patties)
	for box_id: StringName in BOXES:
		var box := FixtureItemModes.item_kind(box_id, [], 2)
		for kind: ItemKind in given:
			if kind.id == BOXES[box_id]:
				box.target_actions = [FixtureGiveModes.take_rule(kind)]
		made.boxes.append(box)
	made.subtasks_setting = &"burgers"
	made.fry_seconds = FRY_SECONDS
	made.burn_seconds = BURN_SECONDS
	return made


## A display station kind (a board): no rule, its spawn tag its id.
static func board(kind_id: StringName) -> StationKind:
	var made := FixtureGeneratorModes.kind(kind_id)
	made.actions = []
	made.display = true
	return made


## A one-handed ingredient kind with no spawn tag that vanishes; `is_given` capped at CAP.
static func ingredient(kind_id: StringName, is_given: bool) -> ItemKind:
	var made := FixtureItemModes.item_kind(kind_id, [])
	made.spawn_tag = &""
	made.vanish_seconds = VANISH
	if is_given:
		made.max_items = CAP
	return made


## The mode's Cooking.
static func type_of(mode: GameMode) -> Cooking:
	for type: TaskType in mode.task_types:
		if type is Cooking:
			return type as Cooking
	return null


## The fixture layouts with every cooking marker: `beds` bed markers (BED_SPOTS by default),
## `places` place markers and two markers per box tag.
static func layouts(
	beds: Array[Vector3] = BED_SPOTS, places: Array[Vector3] = PLACE_SPOTS
) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	var map := found[FixtureModes.MAP]
	map.add_marker(&"order_board", ORDER_BOARD_AT)
	map.add_marker(&"herb_board", HERB_BOARD_AT)
	map.add_marker(&"grill", GRILL_AT)
	for spot: Vector3 in beds:
		map.add_marker(&"herb_bed", spot)
	for spot: Vector3 in places:
		map.add_marker(&"place", spot)
	var z := 40.0
	for box_id: StringName in BOXES:
		map.add_marker(box_id, Vector3(BOX_X, 0, z))
		map.add_marker(box_id, Vector3(BOX_X + 2, 0, z))
		z += 2.0
	return found


## A match of `mode` on `found_layouts` (layouts() when empty) with `peers` all ready: the deal has
## run and the match is in the round (FixtureGeneratorModes.in_round).
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	seed_value: int = 7
) -> Match:
	return FixtureGeneratorModes.in_round(
		mode, peers, found_layouts if not found_layouts.is_empty() else layouts(), {}, seed_value
	)


## The match's Cooking task (null before the deal).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is Cooking:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> Cooking.State:
	return task_of(game).state as Cooking.State


## The events named `event_name` that `peer` received, as plain data, in order.
static func dicts(game: Match, peer: int, event_name: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(event_name):
		found.append(event.to_dict())
	return found
