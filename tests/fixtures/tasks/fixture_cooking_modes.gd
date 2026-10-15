class_name FixtureCookingModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of Cooking (core/tasks/cooking.gd, #772),
## built in code (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its kinds, ids and
## numbers are fixture values, not the engineer's provisional ones (those land in data, C6).
##
## basic(burgers): FixtureCombatModes.raising() (PickUp, PutDown, the two-handed package, the knife,
## the raise; Round lists LifeTicks, then ChannelTicks) with VanishTicks and then TaskTicks added
## to Round, Interact from the living in Round, the settings `tasks` (1), `banned_task_types` and
## `burgers` (`burgers` by default, 0 to MOST_BURGERS), and the task type Cooking in place of the
## mode's: the display kind `herb_board`, the kinds `order_board` (a serve, #1101), `grill` and
## `herb_bed` with the use rule less HandNotTwoHanded (a take beside a box, CD3 (b): AtStation,
## StationInSight, StationUsable; UseStation) and `place` with the whole use rule
## (FixtureGeneratorModes.kind, HandNotTwoHanded first), the buns `bun_a` and `bun_b`, the raw
## patties `raw_a` and `raw_b`, the fried `fried_a` and `fried_b`, `burnt`, the herbs `herb_a` to
## `herb_c`, the `burger` (no spawn tag, `vanish_seconds` VANISH, the given ones `max_items` CAP;
## the burger uncapped) and one two-handed box per bun and
## raw patty (`box_bun_a` ...), each on its own tag with FixtureGiveModes' take. The deal
## (DealTasks) runs before PlacePlayers on `lobby, all_ready -> round`.
##
## layouts(): the fixture lobby and map plus the cooking markers below, far from the players.

const MOST_BURGERS := 3
const CAP := 64
const VANISH := 60
const FRY_SECONDS := 1.0
const BURN_SECONDS := 2.0
## The beds' Cooldown (CE17): one tick, so a second use in the same tick is `too_soon`.
const BED_SECONDS := 0.05
const BED_KEY := &"herb_take"
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


## Adds the settings, the type and its item kinds, Interact from the living, and VanishTicks and
## then TaskTicks last in Round.
static func _add_cooking(mode: GameMode, burgers: int) -> void:
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"burgers", burgers, 0, MOST_BURGERS))
	var type := cooking_type()
	for kind: ItemKind in type.kinds():
		mode.item_kinds.append(kind)
	for kind: ItemKind in type.boxes:
		mode.item_kinds.append(kind)
	mode.task_types = [type]
	var round_phase := mode.find_phase(&"round")
	round_phase.accepts.append(AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(VanishTicks.new())
	round_phase.tick_systems.append(TaskTicks.new())


static func cooking_type() -> Cooking:
	var made := Cooking.new()
	made.id = &"cooking"
	made.description = "Cook the burgers on the order board."
	made.order_board = taking(&"order_board")
	made.herb_board = board(&"herb_board")
	made.grill = taking(&"grill")
	made.herb_bed = bed(&"herb_bed")
	made.place = FixtureGeneratorModes.kind(&"place")
	made.buns = [ingredient(&"bun_a", true), ingredient(&"bun_b", true)]
	made.raw_patties = [ingredient(&"raw_a", true), ingredient(&"raw_b", true)]
	made.fried_patties = [ingredient(&"fried_a", false), ingredient(&"fried_b", false)]
	made.burnt = ingredient(&"burnt", false)
	made.herbs = [
		ingredient(&"herb_a", true), ingredient(&"herb_b", true), ingredient(&"herb_c", true)
	]
	made.burger = ingredient(&"burger", false)
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


## A station kind whose use is (or may be) a take, so its rule has no HandNotTwoHanded (CD3 (b)):
## AtStation, StationInSight, StationUsable; UseStation. Its spawn tag its id.
static func taking(kind_id: StringName) -> StationKind:
	var made := FixtureGeneratorModes.kind(kind_id)
	made.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new(), StationUsable.new()],
			[UseStation.new()]
		)
	]
	return made


## A bed's station kind: `taking`'s rule with a Cooldown of BED_SECONDS (CE17's flood guard) among
## its conditions.
static func bed(kind_id: StringName) -> StationKind:
	var made := taking(kind_id)
	made.actions[0].conditions.append(FixtureCombatModes.cooldown(BED_KEY, BED_SECONDS))
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
## run and the match is in the round (FixtureGeneratorModes.in_round), with `settings` over the
## defaults and `forced` roles (peer -> role id).
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	seed_value: int = 7,
	settings: Dictionary[StringName, int] = {},
	forced: Dictionary[int, StringName] = {}
) -> Match:
	return FixtureGeneratorModes.in_round(
		mode,
		peers,
		found_layouts if not found_layouts.is_empty() else layouts(),
		settings,
		seed_value,
		forced
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


## The grill's station id.
static func grill_of(game: Match) -> int:
	return state_of(game).grill


## The station id of the bed whose herb of the round is `herb_id`.
static func bed_of(game: Match, herb_id: StringName) -> int:
	var task_state := state_of(game)
	for i in task_state.beds.size():
		if task_state.bed_herbs[i].id == herb_id:
			return task_state.beds[i]
	return -1


## The station id of place `index`: order `index`'s.
static func place_of(game: Match, index: int) -> int:
	return state_of(game).orders[index].station


## `peer` stands at `station` (inside its cylinder) and names it in an Interact.
static func use(game: Match, peer: int, station: int, seq: int = 0) -> void:
	FixtureGeneratorModes.use(game, peer, station, seq)


## The box that gives `kind_id`, where the deal laid it.
static func box_giving(game: Match, kind_id: StringName) -> ItemState:
	for item: ItemState in game.state.items.values():
		if BOXES.get(item.kind.id, &"") == kind_id:
			return item
	return null


## `peer` stands 1 m from the box that gives `kind_id` and takes from it (Interact naming it).
static func take(game: Match, peer: int, kind_id: StringName, seq: int = 0) -> void:
	var box := box_giving(game, kind_id)
	FixtureItemModes.stand(game, peer, box.position + Vector3(0, 0, 1))
	FixtureGiveModes.interact_item(game, peer, box.id, seq)


## `peer` picks the herb `herb_id` at its bed.
static func pick(game: Match, peer: int, herb_id: StringName, seq: int = 0) -> void:
	use(game, peer, bed_of(game, herb_id), seq)


## The item in `peer`'s hand, or null.
static func held(game: Match, peer: int) -> ItemState:
	return Items.held_by(game.state, peer)


## The item on `peer`'s belt, or null.
static func belted(game: Match, peer: int) -> ItemState:
	return Items.belted_by(game.state, peer)


## `peer` takes a raw patty of `raw_id` from its box, puts it on the empty grill, runs the ticks
## through the one it turns fried in and takes it off, fried: it is in `peer`'s hand. Returns it.
static func fry(game: Match, peer: int, raw_id: StringName) -> ItemState:
	take(game, peer, raw_id)
	var patty := held(game, peer)
	use(game, peer, grill_of(game))
	FixtureModes.run_ticks(game, type_of(game.mode).fried_ticks() + 1)
	use(game, peer, grill_of(game))
	return patty


## The order board's station id.
static func board_of(game: Match) -> int:
	return state_of(game).order_board


## Order `index`'s burger made right and served (#1101): plate(), take_burger(), serve().
static func cook(game: Match, peer: int, index: int) -> void:
	plate(game, peer, index)
	take_burger(game, peer, index)
	serve(game, peer)


## Every right ingredient of order `index` into `peer`'s hand and onto its place, in the order bun,
## patty, herb, with one tick after each: the plate is full, nothing checked yet.
static func plate(game: Match, peer: int, index: int) -> void:
	var order := state_of(game).orders[index]
	put(game, peer, index, order.bun.id)
	put(game, peer, index, order.raw_patty.id)
	put(game, peer, index, order.herb.id)


## An item of `kind_id` into `peer`'s hand (a bun from its box, a raw patty from its box fried, a
## herb from its bed) and onto place `index`, then one tick.
static func put(game: Match, peer: int, index: int, kind_id: StringName) -> void:
	var type := type_of(game.mode)
	if type.raw_patties.any(func(kind: ItemKind) -> bool: return kind.id == kind_id):
		fry(game, peer, kind_id)
	elif type.herbs.any(func(kind: ItemKind) -> bool: return kind.id == kind_id):
		pick(game, peer, kind_id)
	else:
		take(game, peer, kind_id)
	use(game, peer, place_of(game, index))
	FixtureModes.run_ticks(game, 1)


## `peer` takes the plated burger off place `index` (E on its full plate), then one tick. Returns
## the burger in `peer`'s hand.
static func take_burger(game: Match, peer: int, index: int) -> ItemState:
	use(game, peer, place_of(game, index))
	FixtureModes.run_ticks(game, 1)
	return held(game, peer)


## `peer` serves the burger in hand at the order board (E there), then one tick.
static func serve(game: Match, peer: int) -> void:
	use(game, peer, board_of(game))
	FixtureModes.run_ticks(game, 1)
