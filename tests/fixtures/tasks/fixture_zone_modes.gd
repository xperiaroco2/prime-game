class_name FixtureZoneModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the zone task (core/tasks/zone_task.gd),
## built in code (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its numbers are
## fixture values, not the engineer's provisional ones (those land in data, M7-Z3).
##
## basic(): FixtureCombatModes.raising() (PickUp, PutDown, the knife, the raise, the give-up, a
## Respawn; Round lists LifeTicks, then ChannelTicks) with the settings `tasks` (1),
## `banned_task_types` and `zones`, the task type ZoneTask (zone radius 1.5 m, height 2.5 m, a
## palette of 12 colours, SECONDS: NEEDED host ticks), the deal (DealTasks) before PlacePlayers on
## `lobby, all_ready -> round`, TaskTicks last in Round, and a reaction on subtask_done that notes
## the fact to the server audience (FixtureSubtaskNote). The item fixture's reaction on
## item_rested is dropped. The win conditions are FixtureModes.basic()'s counters, never bumped.
##
## winning(): FixtureWinModes.basic() (DealRoles, the clock, the base mode's win conditions,
## EndMatch and ResetMatch) with ZoneTask in place of Delivery and TaskTicks in Round.
##
## layouts(): the fixture lobby and map (round_player markers at (10 + i, 0, 5)) plus `zone`
## markers, by default SPOTS: the first on player 1's spot, the second on player 4's, 3 m apart.

const RADIUS_M := 1.5
const HEIGHT_M := 2.5
const SECONDS := 1.0
const NEEDED := 20
## Default zone markers: (10, 0, 5) is where PlacePlayers puts peer 1, (13, 0, 5) peer 4's spot.
const SPOTS: Array[Vector3] = [Vector3(10, 0, 5), Vector3(13, 0, 5)]
## A walking step a tick: under the walk speed (0.225 m a tick) and its slack.
const STEP_M := 0.2


static func basic(zones: int = 1, seconds: float = SECONDS) -> GameMode:
	var mode := FixtureCombatModes.raising()
	_add_zones(mode, zones, seconds)
	mode.reactions = [FixtureModes.rule(Facts.SUBTASK_DONE, [], [FixtureSubtaskNote.new()])]
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


static func winning(zones: int = 1) -> GameMode:
	var mode := FixtureWinModes.basic(0)
	mode.settings.erase(mode.find_setting(&"packages"))
	_add_zones(mode, zones, SECONDS)
	return mode


static func zone_task(seconds: float = SECONDS) -> ZoneTask:
	var made := ZoneTask.new()
	made.id = &"zone"
	made.description = "Stand in the zones."
	made.zone = zone_kind()
	made.subtasks_setting = &"zones"
	made.seconds = seconds
	return made


static func zone_kind() -> StationKind:
	var kind := StationKind.new()
	kind.id = &"zone"
	kind.spawn_tag = &"zone"
	kind.radius_m = RADIUS_M
	kind.height_m = HEIGHT_M
	kind.palette = PackedColorArray(FixtureDeliveryModes.PALETTE)
	return kind


## The mode's ZoneTask.
static func zone_task_of(mode: GameMode) -> ZoneTask:
	for type: TaskType in mode.task_types:
		if type is ZoneTask:
			return type as ZoneTask
	return null


## The fixture layouts with a `zone` marker at each of `spots`.
static func layouts(spots: Array[Vector3] = SPOTS) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	for spot: Vector3 in spots:
		found[FixtureModes.MAP].add_marker(&"zone", spot)
	return found


## `count` zone spots far from the players, 5 m apart along x at z = 30.
static func far_spots(count: int) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for i in count:
		found.append(Vector3(5 * i, 0, 30))
	return found


## A match of `mode` on `found_layouts` (layouts() when empty), that keeps its history, with
## `peers` joined, `settings` over the defaults, `forced` roles (peer -> role id), and all ready:
## the deal has run and the match is in the round. No player has claimed yet.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	settings: Dictionary[StringName, int] = {},
	seed_value: int = 7,
	forced: Dictionary[int, StringName] = {}
) -> Match:
	var game := Match.new(
		mode,
		seed_value,
		FlatWorldQuery.new(),
		found_layouts if not found_layouts.is_empty() else layouts()
	)
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for id: StringName in settings:
		game.state.settings[id] = settings[id]
	for peer: int in forced:
		game.state.forced_roles[peer] = forced[peer]
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## The match's zone task (null before the deal or when it dealt none).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is ZoneTask:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> ZoneTask.State:
	return task_of(game).state as ZoneTask.State


## The zone of subtask `index`.
static func zone_of(game: Match, index: int) -> StationState:
	return game.state.stations[state_of(game).stations[index]]


## The ticks zone `index` counted so far.
static func ticks_of(game: Match, index: int) -> int:
	return state_of(game).ticks[index]


## One tick: each of `peers` claims where the host has it, then the tick runs.
static func hold(game: Match, peers: Array[int], ticks: int = 1) -> void:
	for i in ticks:
		for peer: int in peers:
			FixtureMoves.claim(game, peer, game.state.player(peer).position)
		FixtureModes.run_ticks(game, 1)


## `peer` walks to `to` in steps of at most `step_m` (a downed player crawls 0.05 m a tick), one
## claim and one tick each, while `others` hold where they are. Returns the ticks it took.
static func walk(
	game: Match, peer: int, to: Vector3, others: Array[int] = [], step_m: float = STEP_M
) -> int:
	var taken := 0
	var player := game.state.player(peer)
	while not player.position.is_equal_approx(to):
		var left := to - player.position
		var step := left if left.length() <= step_m else left.normalized() * step_m
		for other: int in others:
			FixtureMoves.claim(game, other, game.state.player(other).position)
		FixtureMoves.claim(game, peer, player.position + step)
		FixtureModes.run_ticks(game, 1)
		taken += 1
		if taken > 1000:
			break
	return taken


## The ZoneProgress events `peer` received, as plain data, in order.
static func progress(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"ZoneProgress"):
		found.append(event.to_dict())
	return found


## A ZoneProgress as plain data.
static func sent(station: int, ticks: int, counting: bool, at_tick: int) -> Dictionary:
	return {
		"station": station, "ticks": ticks, "needed": NEEDED, "counting": counting, "tick": at_tick
	}


## Adds the `zones` setting (`zones` zones, 0 to 12), ZoneTask in place of the mode's task types,
## and TaskTicks last in Round; the settings `tasks` and `banned_task_types` when missing.
static func _add_zones(mode: GameMode, zones: int, seconds: float) -> void:
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"zones", zones, 0, 12))
	mode.task_types = [zone_task(seconds)]
	mode.find_phase(&"round").tick_systems.append(TaskTicks.new())
