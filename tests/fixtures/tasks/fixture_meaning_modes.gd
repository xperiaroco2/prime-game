class_name FixtureMeaningModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of DeliveryByMeaning (#828), built in code on
## FixtureItemModes.basic() (a part's unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): the item fixture mode (PickUp 2 m, PutDown 1 m, kinds `package` and `tool`) plus the
## two-handed kinds `wine`, `oil`, `gnome` and `parasol` (spawn tag `package`, or `crate` for the
## gnome and the parasol with `two_tags`), the settings `tasks` (1), `banned_task_types` and
## `packages`, the task type DeliveryByMeaning with four routes (wine -> drop_a, oil -> drop_b,
## gnome -> drop_c, parasol -> drop_d; each drop-off radius 1 m, height 2 m, no palette), the deal
## (DealTasks) before PlacePlayers on `lobby, all_ready -> round`, and a reaction on subtask_done
## that notes the fact to the server audience (FixtureSubtaskNote).
##
## layouts(): the fixture lobby and map, plus on the map one marker per drop-off tag at
## (20 j, 0, 20), `packages` `package` markers at (10 i, 0, -20) and `crates` `crate` markers at
## (10 i, 0, -40), far apart, so no item spawns in a drop-off.

const RADIUS_M := 1.0
const HEIGHT_M := 2.0
const KINDS: Array[StringName] = [&"wine", &"oil", &"gnome", &"parasol"]
const DROP_OFFS: Array[StringName] = [&"drop_a", &"drop_b", &"drop_c", &"drop_d"]


## The mode with `packages` at `packages` (0 to 12); `two_tags` puts the gnome and the parasol on
## the `crate` tag.
static func basic(packages: int = 4, two_tags: bool = false) -> GameMode:
	var mode := FixtureItemModes.basic()
	for i in KINDS.size():
		var kind := FixtureItemModes.item_kind(KINDS[i], [], 2)
		kind.spawn_tag = &"crate" if two_tags and i >= 2 else &"package"
		mode.item_kinds.append(kind)
	mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"packages", packages, 0, 12))
	mode.task_types = [by_meaning(mode)]
	mode.reactions = [FixtureModes.rule(Facts.SUBTASK_DONE, [], [FixtureSubtaskNote.new()])]
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


## DeliveryByMeaning (id `delivery`) with the routes KINDS[i] -> DROP_OFFS[i] of `mode`'s kinds.
static func by_meaning(mode: GameMode) -> DeliveryByMeaning:
	var made := DeliveryByMeaning.new()
	made.id = &"delivery"
	made.description = "Carry each item to its place."
	made.subtasks_setting = &"packages"
	for i in KINDS.size():
		made.routes.append(route(mode.find_item_kind(KINDS[i]), drop_off(DROP_OFFS[i])))
	return made


static func route(item: ItemKind, place: StationKind) -> DeliveryRoute:
	var made := DeliveryRoute.new()
	made.item = item
	made.drop_off = place
	return made


static func drop_off(tag: StringName) -> StationKind:
	var kind := StationKind.new()
	kind.id = tag
	kind.spawn_tag = tag
	kind.radius_m = RADIUS_M
	kind.height_m = HEIGHT_M
	return kind


## The mode's DeliveryByMeaning.
static func type_of(mode: GameMode) -> DeliveryByMeaning:
	for type: TaskType in mode.task_types:
		if type is DeliveryByMeaning:
			return type as DeliveryByMeaning
	return null


## The fixture layouts with one marker per drop-off tag at (20 j, 0, 20), `packages` package
## markers at (10 i, 0, -20) and `crates` crate markers at (10 i, 0, -40) on the map.
static func layouts(packages: int = 10, crates: int = 0) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	add_markers(found[FixtureModes.MAP], packages, crates)
	return found


static func add_markers(map: LevelLayout, packages: int = 10, crates: int = 0) -> void:
	for j in DROP_OFFS.size():
		map.add_marker(DROP_OFFS[j], Vector3(20 * j, 0, 20))
	for i in packages:
		map.add_marker(&"package", Vector3(10 * i, 0, -20))
	for i in crates:
		map.add_marker(&"crate", Vector3(10 * i, 0, -40))


## A match of `mode` on `found_layouts` (layouts() when empty), with `peers` joined, ready and in
## the round: the deal has run.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	seed_value: int = 7
) -> Match:
	return FixtureDeliveryModes.in_round(
		mode, peers, found_layouts if not found_layouts.is_empty() else layouts(), null, seed_value
	)


## The match's DeliveryByMeaning task (null before the deal or when it dealt none).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is DeliveryByMeaning:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> DeliveryByMeaning.State:
	return task_of(game).state as DeliveryByMeaning.State


## The item of subtask `index`.
static func item_of(game: Match, index: int) -> ItemState:
	return game.state.items[state_of(game).items[index]]


## The drop-off station of subtask `index`.
static func station_of(game: Match, index: int) -> StationState:
	return game.state.stations[state_of(game).stations[index]]


## A station of this round other than `station`, or null.
static func other_station(game: Match, station: StationState) -> StationState:
	for id: int in game.state.stations:
		if id != station.id:
			return game.state.stations[id]
	return null
