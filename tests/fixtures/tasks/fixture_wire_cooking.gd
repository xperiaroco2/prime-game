class_name FixtureWireCooking
extends RefCounted
## The fixture mode, map and Cooking of the cooking wire test (#778, the cooking ADR's §7 "The
## wire, without bots"; tests/integration/server/host_session_cooking_test.gd), built in code (a
## part's tests never load `content/`, ARCHITECTURE §9.6). Its kinds, ids and numbers are fixture
## values, not the engineer's provisional ones.
##
## mode(): the harness's fixture mode (FixtureBaseMode's phases with res:// levels) on the one map
## KITCHEN, with the mode's actions PickUp (2 m) and PutDown (1 m), the two-handed `package` on
## the `package` tag, one dealt by SpawnItems (the setting `packages`, 1) after the deal,
## FixtureCookingModes.cooking_type() playing on KITCHEN only (`TaskType.maps`) with its station
## kinds reaching REACH_M, the boxes' and the beds' take paying the Cooldown
## TAKE_KEY of TAKE_SECONDS (CE17's flood guard, 5 ticks), its ingredients vanishing after
## VANISH_SECONDS and capped at CAP, the settings `tasks` (1), `banned_task_types` and `burgers`
## (1, 0 to FixtureCookingModes.MOST_BURGERS), the deal (DealTasks) first on `loading, all_loaded
## -> pregame`, Round accepting PickUp, PutDown and Interact from the living and listing
## VanishTicks, then TaskTicks.
##
## layouts(): the harness's lobby and KITCHEN, whose markers all lie within reach of the players'
## spots (PLAYER_SPOTS), so no client walks: every box and the package within 1 m of every spot,
## every station's cylinder holding every spot.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The fixture map: the one path in the mode's `maps`, the layouts' keys and Cooking's `maps`.
const KITCHEN := "res://tests/fixtures/server/kitchen.tscn"
## The cooking stations' cylinder radius: every station holds every player spot.
const REACH_M := 3.0
const TAKE_KEY := &"cooking_take"
## CE17's 0.25 s: 5 host ticks at 20 Hz.
const TAKE_SECONDS := 0.25
const TAKE_TICKS := 5
const VANISH_SECONDS := 6
## The least cap Cooking.check allows: twice the mode's 4 players, 3 burgers, 1.
const CAP := 12
## The round_player markers, the players' spots in the round.
const PLAYER_SPOTS: Array[Vector3] = [
	Vector3(10, 0, 5), Vector3(11, 0, 5), Vector3(10, 0, 6), Vector3(11, 0, 6)
]
const ORDER_BOARD_AT := Vector3(8, 0, 8)
const HERB_BOARD_AT := Vector3(9, 0, 8)
const GRILL_AT := Vector3(10.5, 0, 7.5)
const BED_SPOTS: Array[Vector3] = [Vector3(9, 0, 5.5), Vector3(12, 0, 5.5), Vector3(10.5, 0, 3.5)]
const PLACE_SPOTS: Array[Vector3] = [Vector3(12, 0, 7), Vector3(9, 0, 7), Vector3(12, 0, 4)]
## Every box marker and the package lie at the middle of the spots, give or take 0.1 m.
const MIDDLE := Vector3(10.5, 0, 5.5)


static func mode() -> GameMode:
	var made := Harness.fixture_mode()
	made.maps = PackedStringArray([KITCHEN])
	made.actions.append(FixtureItemModes.pick_up_rule(FixtureItemModes.REACH_M))
	made.actions.append(FixtureItemModes.put_down_rule(FixtureItemModes.DISTANCE_M))
	var package := FixtureItemModes.item_kind(&"package", [], 2)
	made.item_kinds.append(package)
	made.settings.append(FixtureModes.setting(&"packages", 1, 0, 1))
	made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	made.settings.append(FixtureDealModes.banned_setting())
	made.settings.append(FixtureModes.setting(&"burgers", 1, 0, FixtureCookingModes.MOST_BURGERS))
	var type := cooking_type()
	for kind: ItemKind in type.kinds():
		made.item_kinds.append(kind)
	for kind: ItemKind in type.boxes:
		made.item_kinds.append(kind)
	made.task_types = [type]
	var loaded := made.find_transition(&"loading", LoadingPhase.ALL_LOADED)
	loaded.actions.insert(0, FixtureDealModes.deal_tasks())
	var spawn := FixtureDealModes.spawn_items(package)
	spawn.count_setting = &"packages"
	spawn.rng_purpose = &"packages"
	loaded.actions.insert(1, spawn)
	var round_phase := made.find_phase(&"round")
	for intent: StringName in [Intents.PICK_UP, Intents.PUT_DOWN, Intents.INTERACT]:
		round_phase.accepts.append(AcceptSpec.of(intent, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(VanishTicks.new())
	round_phase.tick_systems.append(TaskTicks.new())
	return made


## FixtureCookingModes' Cooking on KITCHEN only, with the changes of the class comment.
static func cooking_type() -> Cooking:
	var made := FixtureCookingModes.cooking_type()
	made.maps = PackedStringArray([KITCHEN])
	made.herb_bed = FixtureCookingModes.taking(&"herb_bed")
	made.herb_bed.actions[0].conditions.append(take_cooldown())
	for kind: StationKind in [made.order_board, made.grill, made.herb_bed, made.place]:
		kind.radius_m = REACH_M
	for kind: ItemKind in made.kinds():
		kind.vanish_seconds = VANISH_SECONDS
		if kind.max_items > 0:
			kind.max_items = CAP
	for box: ItemKind in made.boxes:
		var take: Rule = box.target_actions[0]
		take.conditions.append(take_cooldown())
	return made


static func take_cooldown() -> Cooldown:
	return FixtureCombatModes.cooldown(TAKE_KEY, TAKE_SECONDS)


## The harness's lobby and KITCHEN with the base mode's knife and circle markers (its demands),
## the players' spots, one package, and the cooking markers: the boards, the grill, a bed per
## herb, the places and two markers per box tag.
static func layouts() -> Dictionary[String, LevelLayout]:
	var lobby: LevelLayout = Harness.layouts()[Harness.LOBBY]
	var map := LevelLayout.new(KITCHEN)
	for spot: Vector3 in PLAYER_SPOTS:
		map.add_marker(&"round_player", spot)
	for i in 3:
		map.add_marker(&"knife", Vector3(20 + i, 0, 0))
		map.add_marker(&"circle", Vector3(30 + i, 0, 0))
	map.add_marker(&"package", MIDDLE + Vector3(0.1, 0, 0.1))
	map.add_marker(&"order_board", ORDER_BOARD_AT)
	map.add_marker(&"herb_board", HERB_BOARD_AT)
	map.add_marker(&"grill", GRILL_AT)
	for spot: Vector3 in BED_SPOTS:
		map.add_marker(&"herb_bed", spot)
	for spot: Vector3 in PLACE_SPOTS:
		map.add_marker(&"place", spot)
	var offset := -0.1
	for box_id: StringName in FixtureCookingModes.BOXES:
		map.add_marker(box_id, MIDDLE + Vector3(0, 0, offset))
		map.add_marker(box_id, MIDDLE + Vector3(offset, 0, 0))
		offset += 0.05
	return {Harness.LOBBY: lobby, KITCHEN: map}
