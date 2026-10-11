class_name FixtureGeneratorModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the Generator (core/tasks/generator.gd,
## #797), built in code (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its numbers
## are fixture values, not the engineer's provisional ones (those land in data, G9).
##
## basic(): FixtureCombatModes.raising() (PickUp, PutDown, the two-handed package, the knife, the
## raise, the give-up; Round lists LifeTicks, then ChannelTicks) with the settings `tasks` (1),
## `banned_task_types` and `active_switches` (0 to SWITCHES), the task type Generator (SWITCHES
## switches, SECONDS: NEEDED host ticks) whose kinds `generator` and `switch` (radius 1 m, height
## 2 m) each have the Interact rule HandNotTwoHanded, AtStation, StationInSight, StationUsable;
## UseStation, the deal (DealTasks) before PlacePlayers on `lobby, all_ready -> round`, Round
## accepting Interact from the living, and TaskTicks last in Round.
##
## winning(): FixtureWinModes.basic() (DealRoles, the clock, the base mode's win conditions,
## EndMatch and ResetMatch) with the Generator in place of Delivery, and Interact and TaskTicks
## in Round.
##
## layouts(): the fixture lobby and map (round_player markers at (10 + i, 0, 5)) plus a `generator`
## marker at GENERATOR_AT and a `switch` marker at each of SWITCH_SPOTS, far from the players. A
## test stands a player at a station (use) before it names it.

const RADIUS_M := 1.0
const HEIGHT_M := 2.0
const SECONDS := 1.0
const NEEDED := 20
const SWITCHES := 4
const GENERATOR_AT := Vector3(0, 0, 20)
## The switch markers, in level order.
const SWITCH_SPOTS: Array[Vector3] = [
	Vector3(4, 0, 20), Vector3(8, 0, 20), Vector3(12, 0, 20), Vector3(16, 0, 20)
]
## Where a player stands to use a station: 0.5 m short of its marker, inside its cylinder.
const SHORT := Vector3(0, 0, -0.5)


static func basic(active: int = SWITCHES) -> GameMode:
	var mode := FixtureCombatModes.raising()
	_add_generator(mode, active)
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


static func winning(active: int = SWITCHES) -> GameMode:
	var mode := FixtureWinModes.basic(0)
	mode.settings.erase(mode.find_setting(&"packages"))
	_add_generator(mode, active)
	return mode


static func generator_type() -> Generator:
	var made := Generator.new()
	made.id = &"generator"
	made.description = "Turn on the switches, then start the generator."
	made.generator = kind(&"generator")
	made.switch = kind(&"switch")
	made.subtasks_setting = &"active_switches"
	made.switches = SWITCHES
	made.seconds = SECONDS
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


## The mode's Generator.
static func type_of(mode: GameMode) -> Generator:
	for type: TaskType in mode.task_types:
		if type is Generator:
			return type as Generator
	return null


## The fixture layouts with the generator marker at `generator_at` and a `switch` marker at each
## of `switch_spots`.
static func layouts(
	switch_spots: Array[Vector3] = SWITCH_SPOTS, generator_at: Vector3 = GENERATOR_AT
) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	found[FixtureModes.MAP].add_marker(&"generator", generator_at)
	for spot: Vector3 in switch_spots:
		found[FixtureModes.MAP].add_marker(&"switch", spot)
	return found


## A match of `mode` in `world` (flat, no walls, by default) on `found_layouts` (layouts() when
## empty), that keeps its history, with `peers` joined, `settings` over the defaults, `forced`
## roles (peer -> role id), and all ready: the deal has run and the match is in the round.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	settings: Dictionary[StringName, int] = {},
	seed_value: int = 7,
	forced: Dictionary[int, StringName] = {},
	world: WorldQuery = null
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
	for id: StringName in settings:
		game.state.settings[id] = settings[id]
	for peer: int in forced:
		game.state.forced_roles[peer] = forced[peer]
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## The match's Generator task (null before the deal or when it dealt none).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is Generator:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> Generator.State:
	return task_of(game).state as Generator.State


## The generator's station id.
static func button_of(game: Match) -> int:
	return state_of(game).generator


## The station id of active switch `index`.
static func switch_of(game: Match, index: int) -> int:
	return state_of(game).switches[index]


## `peer` stands at `station` (SHORT of its marker) and names it in an Interact, applied on the
## next host tick.
static func use(game: Match, peer: int, station: int, seq: int = 0) -> void:
	FixtureItemModes.stand(game, peer, game.state.stations[station].position + SHORT)
	FixtureStationModes.interact(game, peer, station, seq)


## `peer` turns on every active switch, from where it stands at each.
static func switch_all_on(game: Match, peer: int) -> void:
	var task_state := state_of(game)
	for i in task_state.switches.size():
		if not task_state.on[i]:
			use(game, peer, task_state.switches[i])


## The ZoneProgress events `peer` received, as plain data, in order.
static func progress(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"ZoneProgress"):
		found.append(event.to_dict())
	return found


## A ZoneProgress of the generator `station` as plain data.
static func sent(station: int, ticks: int, counting: bool, at_tick: int) -> Dictionary:
	return {
		"station": station, "ticks": ticks, "needed": NEEDED, "counting": counting, "tick": at_tick
	}


## The names of the events `peer` received among `names`, in order.
static func stream(game: Match, peer: int, names: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(peer).events:
		if event.event_name() in names:
			found.append(event.event_name())
	return found


## Adds the `active_switches` setting (`active` of 0 to SWITCHES), the Generator in place of the
## mode's task types, Interact from the living and TaskTicks last in Round; the settings `tasks`
## and `banned_task_types` when missing.
static func _add_generator(mode: GameMode, active: int) -> void:
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"active_switches", active, 0, SWITCHES))
	mode.task_types = [generator_type()]
	var round_phase := mode.find_phase(&"round")
	round_phase.accepts.append(AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(TaskTicks.new())
