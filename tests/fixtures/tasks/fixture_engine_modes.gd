class_name FixtureEngineModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the ship's engine (core/tasks/
## ship_engine.gd, #1453), built in code (a part's unit tests never load `content/`, ARCHITECTURE
## §9.6). Its numbers are fixture values, not the engineer's provisional ones.
##
## basic(): FixtureCombatModes.raising() (Round lists LifeTicks, here with a Respawn, then
## ChannelTicks) with the settings `tasks` (1), `banned_task_types` and `engine_stages` (0 to 3),
## the task type ShipEngine (stages of 2, 4 and 6 problems, STAGE_SECONDS: STAGE_TICKS host ticks
## each) with the start kind `engine_start` and two stub problem kinds: `stub_a` (2 `site_a`
## sites, A_SECONDS) and `stub_b` (3 `site_b` sites and a `fixture_b` fixture, B_SECONDS), every
## station kind with the Interact use rule; the deal before PlacePlayers, Round accepting Interact
## from the living, and TaskTicks last in Round.
##
## layouts(): the fixture lobby and map (round_player markers at (10 + i, 0, 5), outside the aboard
## box) plus the engine's markers along z = 20 and the two aboard corners INSIDE_HIGH, INSIDE_LOW.

const RADIUS_M := 1.0
const HEIGHT_M := 2.0
const STAGE_SECONDS := 1.0
const STAGE_TICKS := 20
const A_SECONDS := 2.0
const A_TICKS := 40
const B_SECONDS := 3.0
const B_TICKS := 60
const START_AT := Vector3(0, 0, 20)
const SITE_A: Array[Vector3] = [Vector3(4, 0, 20), Vector3(8, 0, 20)]
const SITE_B: Array[Vector3] = [Vector3(12, 0, 20), Vector3(16, 0, 20), Vector3(20, 0, 20)]
const FIXTURE_B := Vector3(24, 0, 20)
## The aboard box's corners, in level order (the high one first, as a level may list them).
const INSIDE_HIGH := Vector3(30, 4, 25)
const INSIDE_LOW := Vector3(-2, 0, 15)
## A spot aboard, away from every station.
const ABOARD := Vector3(2, 0, 23)
## Where a player stands to use a station: 0.5 m short of its marker, inside its cylinder.
const SHORT := Vector3(0, 0, -0.5)


static func basic(stages: int = 3) -> GameMode:
	var mode := FixtureCombatModes.raising()
	if mode.find_setting(&"tasks") == null:
		mode.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if mode.find_setting(&"banned_task_types") == null:
		mode.settings.append(FixtureDealModes.banned_setting())
	mode.settings.append(FixtureModes.setting(&"engine_stages", stages, 0, 3))
	mode.task_types = [engine_type()]
	var round_phase := mode.find_phase(&"round")
	round_phase.accepts.append(AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(TaskTicks.new())
	FixtureCombatModes.life_ticks(mode).respawn = FixtureCombatModes.respawn()
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_tasks())
	return mode


static func engine_type() -> ShipEngine:
	var made := ShipEngine.new()
	made.id = &"engine"
	made.description = "Start the ship's engine and fix its problems."
	made.subtasks_setting = &"engine_stages"
	made.start = kind(&"engine_start")
	var stub_b := problem_kind(&"stub_b", &"site_b", 3, B_SECONDS)
	stub_b.fixtures = [kind(&"fixture_b")]
	made.kinds = [problem_kind(&"stub_a", &"site_a", 2, A_SECONDS), stub_b]
	made.stage_problems = PackedInt32Array([2, 4, 6])
	made.stage_seconds = STAGE_SECONDS
	return made


static func problem_kind(
	kind_id: StringName, site_tag: StringName, count: int, seconds: float
) -> StubProblemKind:
	var made := StubProblemKind.new()
	made.id = kind_id
	made.site = kind(site_tag)
	made.site_count = count
	made.seconds = seconds
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


## The mode's ShipEngine.
static func type_of(mode: GameMode) -> ShipEngine:
	return mode.task_types[0] as ShipEngine


## The mode's stub kind `index` (0: stub_a, 1: stub_b).
static func stub_of(mode: GameMode, index: int) -> StubProblemKind:
	return type_of(mode).kinds[index] as StubProblemKind


## The fixture layouts with every engine marker but `leave_out`'s, and `corners` aboard corners.
static func layouts(
	leave_out: StringName = &"", corners: int = 2
) -> Dictionary[String, LevelLayout]:
	var found := FixtureModes.layouts()
	var map := found[FixtureModes.MAP]
	var markers: Dictionary[StringName, Array] = {
		&"engine_start": [START_AT],
		&"site_a": SITE_A,
		&"site_b": SITE_B,
		&"fixture_b": [FIXTURE_B],
	}
	for tag: StringName in markers:
		if tag == leave_out:
			continue
		for spot: Vector3 in markers[tag]:
			map.add_marker(tag, spot)
	var aboard: Array[Vector3] = [INSIDE_HIGH, INSIDE_LOW]
	for i in corners:
		map.add_marker(&"engine_aboard", aboard[i])
	return found


## A match of `mode` on `found_layouts` (layouts() when empty) with `peers` joined, `settings` over
## the defaults, `forced` roles, all ready: the deal has run and the match is in the round.
static func in_round(
	mode: GameMode,
	peers: Array[int],
	found_layouts: Dictionary[String, LevelLayout] = {},
	settings: Dictionary[StringName, int] = {},
	seed_value: int = 7,
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


## The match's engine task (null before the deal or when it dealt none).
static func task_of(game: Match) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type is ShipEngine:
			return game.state.tasks[id]
	return null


static func state_of(game: Match) -> ShipEngine.State:
	return task_of(game).state as ShipEngine.State


## `peer` stands at `station` (SHORT of its marker) and names it in an Interact, applied on the
## next host tick.
static func use(game: Match, peer: int, station: int, seq: int = 0) -> void:
	FixtureItemModes.stand(game, peer, game.state.stations[station].position + SHORT)
	FixtureStationModes.interact(game, peer, station, seq)


## `peer` presses the start, and that tick runs.
static func start(game: Match, peer: int) -> void:
	use(game, peer, state_of(game).console)
	FixtureModes.run_ticks(game, 1)


## `peer` uses a station of every open problem, each in its own tick.
static func fix_all(game: Match, peer: int) -> void:
	for problem: EngineProblem in state_of(game).problems.duplicate():
		use(game, peer, problem.stations[0])
		FixtureModes.run_ticks(game, 1)


## Runs ticks, `peer` fixing every open problem as soon as it opens, until the engine stands on
## `stage` or is done; at most `most` ticks.
static func play_to(game: Match, peer: int, stage: int, most: int = 2000) -> void:
	var task_state := state_of(game)
	for i in most:
		if task_state.done or task_state.stage >= stage:
			return
		if task_state.problems.is_empty():
			FixtureModes.run_ticks(game, 1)
		else:
			fix_all(game, peer)


## The `name` events `peer` received, as plain data, in order.
static func dicts(game: Match, peer: int, name: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(name):
		found.append(event.to_dict())
	return found


## The names of the events `peer` received among `names`, in order.
static func stream(game: Match, peer: int, names: Array[StringName]) -> Array[StringName]:
	return FixtureGeneratorModes.stream(game, peer, names)
