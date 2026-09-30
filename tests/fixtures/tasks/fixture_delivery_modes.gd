class_name FixtureDeliveryModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of core/tasks/, built in code on
## FixtureItemModes.basic() (a part's unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): the item fixture mode (PickUp 2 m, PutDown 1 m, kinds `package` and `tool`) with the
## settings `tasks` (1), `banned_task_types` and `packages`, the task type Delivery (circle radius
## 1 m, height 2 m, a palette of 12 colours), the deal (DealTasks, purpose `task_types`) before
## PlacePlayers on `lobby, all_ready -> round`, and a reaction on subtask_done that notes the
## fact to the server audience (FixtureSubtaskNote). The item fixture's reaction on item_rested
## is dropped.
##
## layouts(): the fixture lobby and map, plus on the map 10 `circle` markers at (10 i, 0, 20) and
## 10 `package` markers at (10 i, 0, -20), far apart, so no package spawns in a circle.

const RADIUS_M := 1.0
const HEIGHT_M := 2.0
const PALETTE: Array[Color] = [
	Color(0.9, 0.1, 0.1),
	Color(0.1, 0.6, 0.1),
	Color(0.1, 0.2, 0.9),
	Color(0.9, 0.8, 0.1),
	Color(0.6, 0.1, 0.7),
	Color(0.1, 0.8, 0.8),
	Color(0.9, 0.5, 0.1),
	Color(0.5, 0.3, 0.1),
	Color(0.9, 0.4, 0.7),
	Color(0.5, 0.5, 0.5),
	Color(0.1, 0.1, 0.1),
	Color(0.6, 0.9, 0.3),
]


## The mode with Delivery's `packages` at `packages` (0 to 12).
static func basic(packages: int = 2) -> GameMode:
	var mode := FixtureItemModes.basic()
	mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"packages", packages, 0, 12))
	mode.task_types = [delivery(mode.find_item_kind(&"package"))]
	mode.reactions = [FixtureModes.rule(Facts.SUBTASK_DONE, [], [FixtureSubtaskNote.new()])]
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


static func delivery(package: ItemKind) -> Delivery:
	var made := Delivery.new()
	made.id = &"delivery"
	made.package = package
	made.circle = circle()
	made.subtasks_setting = &"packages"
	return made


static func circle() -> StationKind:
	var kind := StationKind.new()
	kind.id = &"circle"
	kind.spawn_tag = &"circle"
	kind.radius_m = RADIUS_M
	kind.height_m = HEIGHT_M
	kind.palette = PackedColorArray(PALETTE)
	return kind


## The mode's Delivery.
static func delivery_of(mode: GameMode) -> Delivery:
	return mode.task_types[0] as Delivery


## The fixture layouts with `circles` circle markers at (10 i, 0, 20) and `packages` package
## markers at (10 i, 0, -20) on the map.
static func layouts(circles: int = 10, packages: int = 10) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	var map := found[FixtureModes.MAP]
	for i in circles:
		map.add_marker(&"circle", Vector3(10 * i, 0, 20))
	for i in packages:
		map.add_marker(&"package", Vector3(10 * i, 0, -20))
	return found


## A match of `mode` on `found_layouts` asking `world`, that keeps its history, with `peers`
## joined, ready and in the round: the deal has run.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	world: WorldQuery = null,
	seed_value: int = 7
) -> Match:
	var game := Match.new(
		mode,
		seed_value,
		world if world != null else FlatWorldQuery.new(),
		found_layouts if not found_layouts.is_empty() else layouts()
	)
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## The match's one task, Delivery's shared task (null before the deal or when it dealt none).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		return game.state.tasks[id]
	return null


## The package of subtask `index` of `task`.
static func package_of(game: Match, task: MatchTask, index: int) -> ItemState:
	return game.state.items[(task.state as Delivery.State).packages[index]]


## The circle of subtask `index` of `task`.
static func circle_of(game: Match, task: MatchTask, index: int) -> StationState:
	return game.state.stations[(task.state as Delivery.State).circles[index]]


## `peer` stands beside `item`, picks it up, then stands 1 m (the put-down distance) short of
## `target` along +x and puts it down facing +x: it rests at `target`, on the world's floor.
static func carry_to(game: Match, peer: int, item: ItemState, target: Vector3) -> void:
	FixtureItemModes.stand(game, peer, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, peer, item)
	FixtureItemModes.stand(game, peer, target - Vector3(FixtureItemModes.DISTANCE_M, 0, 0))
	FixtureItemModes.put_down(game, peer, Vector3.RIGHT)
