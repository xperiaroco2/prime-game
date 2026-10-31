class_name FixtureEngineKindModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the ship engine's problem kinds
## (core/tasks/gills_problem.gd, breakers_problem.gd, crystal_problem.gd, #1461), built in code on
## FixtureEngineModes (a part's unit tests never load `content/`, ARCHITECTURE §9.6). Its numbers
## are fixture values, not the engineer's provisional ones.
##
## of(kinds): FixtureEngineModes.basic() with `kinds` as the engine's only kinds, the two crystal
## item kinds (two-handed, never vanishing; the mode has the pick-up and put-down rules). layouts():
## FixtureEngineModes.layouts() plus the kinds' markers, all inside the aboard box: two gill
## buttons, two boards with four breakers each (nearer their own board), four sockets and two
## chargers.

## Twenty host ticks a second (FixtureEngineModes.STAGE_TICKS for 1 s).
const STEP_SECONDS := 0.5
const STEP_TICKS := 10
const GILLS_SECONDS := 10.0
const GILLS_TICKS := 200
const BREAKERS_SECONDS := 30.0
const BREAKERS_TICKS := 600
const RAMP_SECONDS := 1.0
const RAMP_TICKS := 20
const GREEN_SECONDS := 2.0
const GREEN_TICKS := 40
const CRYSTAL_SECONDS := 30.0
const CRYSTAL_TICKS := 600
const CHARGE_SECONDS := 1.0
const CHARGE_TICKS := 20
const GILL_BUTTONS: Array[Vector3] = [Vector3(4, 0, 17), Vector3(8, 0, 17)]
const BOARDS: Array[Vector3] = [Vector3(4, 0, 22), Vector3(22, 0, 22)]
const BREAKERS: Array[Vector3] = [
	Vector3(2, 0, 24),
	Vector3(3.5, 0, 24),
	Vector3(5, 0, 24),
	Vector3(6.5, 0, 24),
	Vector3(20, 0, 24),
	Vector3(21.5, 0, 24),
	Vector3(23, 0, 24),
	Vector3(24.5, 0, 24),
]
const SOCKETS: Array[Vector3] = [
	Vector3(12, 0, 17), Vector3(14, 0, 17), Vector3(16, 0, 17), Vector3(18, 0, 17)
]
const CHARGERS: Array[Vector3] = [Vector3(12, 0, 23), Vector3(18, 0, 23)]
## Outside the aboard box, past its high x side (the ramp).
const OUTSIDE := Vector3(34, 0, 20)


## FixtureEngineModes.basic(`stages`) with `kinds` as the engine's kinds; the crystal item kinds
## (two-handed).
static func of(kinds: Array[ProblemKind], stages: int = 3) -> GameMode:
	var mode := FixtureEngineModes.basic(stages)
	FixtureEngineModes.type_of(mode).kinds = kinds
	mode.item_kinds.append(FixtureItemModes.item_kind(&"crystal_spent", [], 2))
	mode.item_kinds.append(FixtureItemModes.item_kind(&"crystal_charged", [], 2))
	for kind: ProblemKind in kinds:
		if kind is CrystalProblem:
			(kind as CrystalProblem).spent = mode.find_item_kind(&"crystal_spent")
			(kind as CrystalProblem).charged = mode.find_item_kind(&"crystal_charged")
	return mode


static func gills() -> GillsProblem:
	var made := GillsProblem.new()
	made.id = &"gills"
	made.site = FixtureEngineModes.kind(&"gill_button")
	made.site_count = 2
	made.seconds = GILLS_SECONDS
	made.step_seconds = STEP_SECONDS
	return made


static func breakers() -> BreakersProblem:
	var made := BreakersProblem.new()
	made.id = &"breakers"
	made.site = FixtureEngineModes.kind(&"breaker_board")
	made.site_count = 2
	made.fixtures = [FixtureEngineModes.kind(&"breaker")]
	made.seconds = BREAKERS_SECONDS
	made.trips = PackedInt32Array([2, 4, 6])
	made.side_changes = PackedInt32Array([0, 1, 5])
	made.ramp_seconds = RAMP_SECONDS
	made.green_seconds = GREEN_SECONDS
	return made


## The crystal kind; of() sets its item kinds.
static func crystal() -> CrystalProblem:
	var made := CrystalProblem.new()
	made.id = &"crystal"
	made.site = two_handed_kind(&"cartridge_socket")
	made.site_count = 4
	made.fixtures = [two_handed_kind(&"cartridge_charger")]
	made.seconds = CRYSTAL_SECONDS
	made.charge_seconds = CHARGE_SECONDS
	return made


## A station kind whose spawn tag is its id, with the use rule without HandNotTwoHanded (the crystal
## is two-handed).
static func two_handed_kind(kind_id: StringName) -> StationKind:
	var made := FixtureEngineModes.kind(kind_id)
	made.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new(), StationUsable.new()],
			[UseStation.new()]
		)
	]
	return made


## FixtureEngineModes.layouts() plus every kind's markers but `leave_out`'s; `breakers` of the
## eight breaker markers.
static func layouts(
	leave_out: StringName = &"", breakers_count: int = 8
) -> Dictionary[String, LevelLayout]:
	var found := FixtureEngineModes.layouts()
	var map := found[FixtureModes.MAP]
	var markers: Dictionary[StringName, Array] = {
		&"gill_button": GILL_BUTTONS,
		&"breaker_board": BOARDS,
		&"breaker": BREAKERS.slice(0, breakers_count),
		&"cartridge_socket": SOCKETS,
		&"cartridge_charger": CHARGERS,
	}
	for tag: StringName in markers:
		if tag == leave_out:
			continue
		for spot: Vector3 in markers[tag]:
			map.add_marker(tag, spot)
	return found


## A match of `mode` with `peers` in the round, on layouts(), seeded `seed_value`.
static func in_round(mode: GameMode, peers: Array[int], seed_value: int = 7) -> Match:
	return FixtureEngineModes.in_round(mode, peers, layouts(), {}, seed_value)


## `peer` starts the engine, then the ticks run until a problem is open (at most `most`).
static func start_to_problem(game: Match, peer: int, most: int = 200) -> EngineProblem:
	FixtureEngineModes.start(game, peer)
	var task_state := FixtureEngineModes.state_of(game)
	for i in most:
		if not task_state.problems.is_empty():
			return task_state.problems[0]
		FixtureModes.run_ticks(game, 1)
	return null


## Runs the ticks until `tick` is the last one run.
static func run_to(game: Match, tick: int) -> void:
	FixtureModes.run_ticks(game, maxi(0, tick - game.ticked_through()))


## `peer` uses `station` in the next tick, which runs; returns that tick.
static func press(game: Match, peer: int, station: int) -> int:
	FixtureEngineModes.use(game, peer, station)
	FixtureModes.run_ticks(game, 1)
	return game.ticked_through()


## `peer` uses `station` in host tick `tick` (later than the last one run).
static func press_at(game: Match, peer: int, station: int, tick: int) -> void:
	run_to(game, tick - 1)
	press(game, peer, station)


## The `name` events `peer` received from the tick after `after` on, as plain data.
static func since(game: Match, peer: int, name: StringName, after: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.tick > after and emitted.event.event_name() == name:
			if emitted.recipients.has(peer):
				found.append(emitted.event.to_dict())
	return found


## The reason of the last Rejected `peer` received, or empty.
static func last_reason(game: Match, peer: int) -> StringName:
	var found := FixtureEngineModes.dicts(game, peer, &"Rejected")
	return found[-1]["reason"] if not found.is_empty() else &""
