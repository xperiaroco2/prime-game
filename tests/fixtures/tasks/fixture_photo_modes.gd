class_name FixturePhotoModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the photo task (core/tasks/photo_task.gd,
## #781), built in code (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its numbers
## are fixture values, not the engineer's provisional ones (those land in data with House).
##
## basic(): FixtureCombatModes.raising() (PickUp, PutDown, the two-handed package, the tool, the
## knife, the raise, the give-up; the eye at 1.6 m; max 4 players) plus the item kinds `film` and
## `photo` (one-handed, their caps at PhotoTask's floors for 4 players), the settings `tasks` (1),
## `banned_task_types` and `photos` (0 to MOST_PHOTOS), the task type PhotoTask (FRAMES frames,
## FOV_DEG, ASPECT, RANGE_M) whose kinds `camera`, `film_box`, `printer` and `board` (radius 1 m,
## height 2 m) each have the Interact rule HandNotTwoHanded, AtStation, StationInSight,
## StationUsable; UseStation (the box's with a Cooldown first), `photo_spot` a display kind with no
## rule; the deal (DealTasks) before PlacePlayers on `lobby, all_ready -> round`, Round accepting
## Interact from the living.
##
## winning(): the same photo task on FixtureWinModes.basic() (roles dealt), for the role-swap check.
##
## layouts(): the fixture lobby and map (round_player markers at (10 + i, 0, 5)) plus one marker of
## each station kind and item kind: the camera at CAMERA_AT looking along +Z at the photo spot
## SPOT_AT, the others aside.

const RADIUS_M := 1.0
const HEIGHT_M := 2.0
const FRAMES := 2
const FOV_DEG := 60.0
const ASPECT := 1.5
const RANGE_M := 10.0
const MOST_PHOTOS := 3
const BOX_COOLDOWN_S := 1.0
const CAMERA_AT := Vector3(0, 0, 20)
const SPOT_AT := Vector3(0, 0, 30)
const BOX_AT := Vector3(-6, 0, 20)
const PRINTER_AT := Vector3(-10, 0, 20)
const BOARD_AT := Vector3(-14, 0, 20)
const FILM_AT := Vector3(-6, 0, 22)
const PHOTO_AT := Vector3(-10, 0, 22)
## Where a player stands to use a station: 0.5 m short of its marker, inside its cylinder.
const SHORT := Vector3(0, 0, -0.5)
## A spot in the middle of the frame, 6 m in front of the lens.
const IN_FRAME := Vector3(0, 0, 26)


static func basic(photos: int = 2) -> GameMode:
	var mode := FixtureCombatModes.raising()
	_add_photo(mode, photos)
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


## FixtureWinModes.basic() (DealRoles with `dissidents` 1, DealTasks, the clock, the base mode's win
## conditions, EndMatch and ResetMatch) with the photo task in place of Delivery.
static func winning(photos: int = 2) -> GameMode:
	var mode := FixtureWinModes.basic(0)
	mode.settings.erase(mode.find_setting(&"packages"))
	_add_photo(mode, photos)
	return mode


## Adds the film and photo kinds, the settings, the PhotoTask in place of the mode's task types and
## Interact from the living in Round.
static func _add_photo(mode: GameMode, photos: int) -> void:
	var players := mode.max_players
	mode.item_kinds.append(item(&"film", 2 * players + 1))
	mode.item_kinds.append(item(&"photo", 2 * players + MOST_PHOTOS + FRAMES + 1))
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"photos", photos, 0, MOST_PHOTOS))
	mode.task_types = [photo_type(mode)]
	mode.find_phase(&"round").accepts.append(
		AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING)
	)


static func photo_type(mode: GameMode) -> PhotoTask:
	var made := PhotoTask.new()
	made.id = &"photo"
	made.description = "Take a photo with a person in it and hang it on the board."
	made.camera = kind(&"camera")
	made.photo_spot = kind(&"photo_spot")
	made.photo_spot.display = true
	made.photo_spot.actions = []
	made.film_box = kind(&"film_box")
	made.film_box.actions = [box_rule()]
	made.printer = kind(&"printer")
	made.board = kind(&"board")
	made.film = mode.find_item_kind(&"film")
	made.photo = mode.find_item_kind(&"photo")
	made.subtasks_setting = &"photos"
	made.frames_per_film = FRAMES
	made.fov_deg = FOV_DEG
	made.aspect = ASPECT
	made.range_m = RANGE_M
	return made


## A one-handed item kind with no actions and the cap `cap`.
static func item(id: StringName, cap: int) -> ItemKind:
	var made := FixtureItemModes.item_kind(id, [])
	made.max_items = cap
	return made


## A station kind whose spawn tag is its id, with the use rule.
static func kind(kind_id: StringName) -> StationKind:
	var made := StationKind.new()
	made.id = kind_id
	made.spawn_tag = kind_id
	made.radius_m = RADIUS_M
	made.height_m = HEIGHT_M
	made.actions = [FixtureStationModes.use_rule()]
	return made


## The film box's rule: the use rule paying a Cooldown (PE14).
static func box_rule() -> Rule:
	return (
		FixtureModes
		. rule(
			Intents.INTERACT,
			[
				HandNotTwoHanded.new(),
				AtStation.new(),
				StationInSight.new(),
				StationUsable.new(),
				FixtureCombatModes.cooldown(&"film_box", BOX_COOLDOWN_S),
			],
			[UseStation.new()]
		)
	)


## The mode's PhotoTask.
static func type_of(mode: GameMode) -> PhotoTask:
	for type: TaskType in mode.task_types:
		if type is PhotoTask:
			return type as PhotoTask
	return null


## The fixture layouts with one marker of each photo tag; the photo spot at `spot_at`.
static func layouts(spot_at: Vector3 = SPOT_AT) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	var map := found[FixtureModes.MAP]
	map.add_marker(&"camera", CAMERA_AT)
	map.add_marker(&"photo_spot", spot_at)
	map.add_marker(&"film_box", BOX_AT)
	map.add_marker(&"printer", PRINTER_AT)
	map.add_marker(&"board", BOARD_AT)
	map.add_marker(&"film", FILM_AT)
	map.add_marker(&"photo", PHOTO_AT)
	return found


## A match of `mode` in `world` (flat, no walls, by default) on layouts(), keeping its history, with
## `peers` joined, `settings` over the defaults, `forced` roles, and all ready: in the round.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	settings: Dictionary[StringName, int] = {},
	world: WorldQuery = null,
	forced: Dictionary[int, StringName] = {},
	seed_value: int = 7
) -> Match:
	return FixtureGeneratorModes.in_round(
		mode, peers, layouts(), settings, seed_value, forced, world
	)


## The match's photo task (null before the deal).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is PhotoTask:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> PhotoTask.State:
	return task_of(game).state as PhotoTask.State


static func camera_of(game: Match) -> int:
	return state_of(game).camera


## The dealt film (the first film item of the match).
static func dealt_film(game: Match) -> ItemState:
	for id: int in game.state.items:
		var found: ItemState = game.state.items[id]
		if found.kind.id == &"film":
			return found
	return null


## `peer` stands at `station` (SHORT of its marker) and names it in an Interact.
static func use(game: Match, peer: int, station: int, seq: int = 0) -> void:
	FixtureItemModes.stand(game, peer, game.state.stations[station].position + SHORT)
	FixtureStationModes.interact(game, peer, station, seq)


## `peer` stands by `lifted` and picks it up.
static func take(game: Match, peer: int, lifted: ItemState, seq: int = 0) -> void:
	FixtureItemModes.stand(game, peer, lifted.position + Vector3(0, 0, -0.5))
	FixtureItemModes.pick_up(game, peer, lifted, seq)


## `peer` puts its hand item down in front of it, facing +X (away from the camera's line).
static func put_down_at(game: Match, peer: int, seq: int = 0) -> void:
	FixtureItemModes.put_down(game, peer, Vector3.RIGHT, seq)


## A new film straight into `peer`'s hand (a test's shortcut for the box P3 builds).
static func give_film(game: Match, peer: int) -> ItemState:
	var made := FixtureItemModes.lay(game, &"film", Vector3(30, 0, 30))
	FixtureItemModes.stand(game, peer, made.position + Vector3(0, 0, -0.5))
	FixtureItemModes.pick_up(game, peer, made)
	return made


## The events named `name` that `peer` received, as plain data, in order.
static func received(game: Match, peer: int, name: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(name):
		found.append(event.to_dict())
	return found


## The Rejected reasons `peer` received, in order.
static func reasons(game: Match, peer: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"Rejected"):
		found.append(StringName(str(event.to_dict().get("reason", ""))))
	return found


## A round of `mode` with a FixtureKillTick on the round phase, queuing nobody until the test sets
## `queues` on it. Returns the match; the tick system is in `killers[0]`.
static func in_round_with_killer(peers: Array[int], killers: Array[FixtureKillTick]) -> Match:
	var mode := basic()
	var killer := FixtureKillTick.queuing([])
	killers.append(killer)
	mode.find_phase(&"round").tick_systems.append(killer)
	return in_round(mode, peers)
