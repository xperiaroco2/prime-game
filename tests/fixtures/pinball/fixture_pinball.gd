class_name FixturePinball
extends RefCounted
## FixtureLobbyHands with a pinball machine as the base mode has one (#1398; a part's unit test
## never loads `content/`, ARCHITECTURE §9.6): the station kind `pinball` (spawn tag `pinball`,
## radius RADIUS), whose Interact at it and in sight, with the seat free or its own, runs a
## UsePinball of BALLS balls and the targets `bumper` (BUMPER) and `target` (TARGET); the mode's
## Flippers rule (PinballSeated, SetFlippers). Lobby and Countdown accept Flippers from the living
## and run StationTicks (the machine) and PinballTicks; `countdown_done` runs ClearItems,
## EndPinball and ClearStations. The lobby layout holds one `pinball` marker at MACHINE.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2
const P3 := FixtureLobbyHands.P3
const MACHINE := Vector3(1, 0, 0)
const RADIUS := 1.5
const BALLS := 3
const BUMPER := 100
const TARGET := 500


static func mode() -> GameMode:
	return with_machine(FixtureLobbyHands.clearing(FixtureLobbyHands.mode()))


## `made` (FixtureLobbyHands' clearing mode, or one built the same way from another base) with the
## machine as mode() has it.
static func with_machine(made: GameMode) -> GameMode:
	made.actions.append(
		FixtureModes.rule(
			Intents.FLIPPERS,
			[PinballSeated.new()] as Array[Condition],
			[SetFlippers.new()] as Array[RuleEffect]
		)
	)
	var placing := StationTicks.new()
	placing.kind = machine_kind()
	var ticks := PinballTicks.new()
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		spec.accepts.append(AcceptSpec.of(Intents.FLIPPERS, AcceptSpec.From.LIVING))
		spec.tick_systems.append(placing)
		spec.tick_systems.append(ticks)
	for row: Transition in made.transitions:
		if row.from == &"countdown" and row.outcome == CountdownPhase.COUNTDOWN_DONE:
			row.actions.append(EndPinball.new())
			row.actions.append(ClearStations.new())
	return made


## The station kind `pinball`: radius RADIUS, height 2 m, its Interact runs a UsePinball.
static func machine_kind() -> StationKind:
	var use := UsePinball.new()
	use.balls = BALLS
	use.targets = [target(&"bumper", BUMPER), target(&"target", TARGET)]
	var kind := StationKind.new()
	kind.id = &"pinball"
	kind.spawn_tag = &"pinball"
	kind.radius_m = RADIUS
	kind.height_m = 2.0
	kind.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new(), PinballUsable.new()] as Array[Condition],
			[use] as Array[RuleEffect]
		)
	]
	return kind


static func target(id: StringName, points: int) -> PinballTarget:
	var made := PinballTarget.new()
	made.id = id
	made.points = points
	return made


## FixtureBaseMode's layouts with the `pinball` marker at MACHINE in the lobby.
static func layouts() -> Dictionary[String, LevelLayout]:
	var made := FixtureBaseMode.layouts()
	made[FixtureBaseMode.LOBBY].add_marker(&"pinball", MACHINE)
	return made


## A started match of `made` that keeps its history, `peers` joined and standing at the machine,
## after one tick (the machine stands).
static func at_machine(made: GameMode, peers: Array[int]) -> Match:
	var game := Match.new(made, 7, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		stand_at(game, peer)
	return game


## `peer` stands at the machine, inside its cylinder.
static func stand_at(game: Match, peer: int) -> void:
	FixtureItemModes.stand(game, peer, MACHINE + Vector3(0.3 * peer, 0, 0.5))


## The id of the machine's station, or -1.
static func machine_id(game: Match) -> int:
	for id: int in game.state.stations:
		if game.state.stations[id].kind.id == &"pinball":
			return id
	return -1


## `peer` presses E at the machine (Interact) with `seq`, then a tick runs.
static func interact(game: Match, peer: int, seq := 0) -> void:
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": machine_id(game)}, seq)
	FixtureModes.run_ticks(game, 1)


## `peer` sends its flippers with `seq`, then a tick runs.
static func flippers(game: Match, peer: int, left: bool, right: bool, seq := 0) -> void:
	FixtureModes.send(game, Intents.FLIPPERS, peer, {"left": left, "right": right}, seq)
	FixtureModes.run_ticks(game, 1)


## The PinballState events `peer` received, as plain data, in order.
static func states(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"PinballState"):
		found.append(event.to_dict())
	return found


## The last PinballState `peer` received, or empty.
static func last(game: Match, peer: int) -> Dictionary:
	var found := states(game, peer)
	return found.back() if not found.is_empty() else {}
