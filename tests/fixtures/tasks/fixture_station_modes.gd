class_name FixtureStationModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of Interact and the station parts (AtStation,
## StationInSight, StationUsable, UseStation; the Generator ADR's GE1 to GE4, #796), built in code
## (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its numbers are fixture values.
##
## basic(): FixtureCombatModes.raising() (PickUp, PutDown, the two-handed package, the knife, the
## raise, the give-up) with the settings `tasks` (1) and `banned_task_types`, the task type
## FixtureStationType whose kind `panel` (radius 1 m, height 2 m) has the Interact rule
## HandNotTwoHanded, AtStation, StationInSight, StationUsable; UseStation, the deal (DealTasks)
## before PlacePlayers on `lobby, all_ready -> round`, and Round accepting Interact from `from`
## (the living by default).
##
## layouts(): the fixture lobby and map (round_player markers at (10 + i, 0, 5)) plus a `panel`
## marker at each of SPOTS, far from the players: stations 1 and 2 (task 1), in that order.

const RADIUS_M := 1.0
const HEIGHT_M := 2.0
const SPOTS: Array[Vector3] = [Vector3(0, 0, 20), Vector3(6, 0, 20)]


static func basic(from: int = AcceptSpec.From.LIVING) -> GameMode:
	return _with_stations(FixtureCombatModes.raising(), from)


## basic() on FixtureItemModes.basic(): no knife and no raise, so no channel (ModeCheck's
## role-reveal warning about a channel stays out of the way).
static func plain() -> GameMode:
	return _with_stations(FixtureItemModes.basic(), AcceptSpec.From.LIVING)


static func _with_stations(mode: GameMode, from: int) -> GameMode:
	mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	mode.settings.append(FixtureDealModes.banned_setting())
	mode.task_types = [station_type()]
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	mode.find_phase(&"round").accepts.append(AcceptSpec.of(Intents.INTERACT, from))
	return mode


static func station_type() -> FixtureStationType:
	var made := FixtureStationType.new()
	made.panel = panel_kind()
	return made


static func panel_kind() -> StationKind:
	var kind := StationKind.new()
	kind.id = &"panel"
	kind.spawn_tag = &"panel"
	kind.radius_m = RADIUS_M
	kind.height_m = HEIGHT_M
	kind.palette = PackedColorArray([Color.ORANGE])
	kind.actions = [use_rule()]
	return kind


## The panel's Interact rule, as a Generator's switch would have it.
static func use_rule() -> Rule:
	return FixtureModes.rule(
		Intents.INTERACT,
		[HandNotTwoHanded.new(), AtStation.new(), StationInSight.new(), StationUsable.new()],
		[UseStation.new()]
	)


## The mode's FixtureStationType.
static func type_of(mode: GameMode) -> FixtureStationType:
	return mode.task_types[0] as FixtureStationType


## The fixture layouts with a `panel` marker at each of `spots`.
static func layouts(spots: Array[Vector3] = SPOTS) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	for spot: Vector3 in spots:
		found[FixtureModes.MAP].add_marker(&"panel", spot)
	return found


## A match of `mode` in `world` (flat, no walls, by default) on layouts(), that keeps its history,
## with `peers` joined and all ready: the deal has run and the match is in the round.
static func in_round(mode: GameMode, peers: Array[int], world: WorldQuery = null) -> Match:
	var game := Match.new(mode, 7, world if world != null else FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## `peer` sends Interact naming `station`, applied on the next host tick.
static func interact(game: Match, peer: int, station: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": station}, seq)
