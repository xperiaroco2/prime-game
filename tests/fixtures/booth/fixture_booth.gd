class_name FixtureBooth
extends RefCounted
## FixtureLobbyHands with a photo booth as the base mode has one (#1396; a part's unit test never
## loads `content/`, ARCHITECTURE §9.6): the item kind `strip` (one-handed, at most STRIPS,
## vanishing after STRIP_S, no rule); the station kind `booth` (spawn tag `booth`, RADIUS wide,
## HEIGHT tall), whose Interact at it and in sight starts a session (StartBooth: FRAMES flashes,
## COUNTDOWN_S then GAP_S apart). Lobby runs StationTicks (the booth), BoothTicks and VanishTicks;
## Countdown runs StationTicks and VanishTicks but no BoothTicks (a press there is refused);
## `all_ready` runs StopBooth, `countdown_done` ClearItems and ClearStations. The lobby layout
## holds one `booth` marker at BOOTH.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2
const P3 := FixtureLobbyHands.P3
const BOOTH := Vector3(-6, 0, -6)
const RADIUS := 1.2
const HEIGHT := 2.5
const FRAMES := 3
const COUNTDOWN_S := 1.0
const GAP_S := 0.5
## COUNTDOWN_S and GAP_S in ticks (20 a second).
const COUNTDOWN := 20
const GAP := 10
const STRIPS := 5
const STRIP_S := 30


static func mode() -> GameMode:
	var made := FixtureLobbyHands.clearing(FixtureLobbyHands.mode())
	var strip := FixtureItemModes.item_kind(&"strip", [])
	strip.max_items = STRIPS
	strip.vanish_seconds = STRIP_S
	made.item_kinds.append(strip)
	var placing := StationTicks.new()
	placing.kind = booth_kind(start_of(strip))
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		spec.tick_systems.append(placing)
		spec.tick_systems.append(VanishTicks.new())
	made.find_phase(&"lobby").tick_systems.append(BoothTicks.new())
	for row: Transition in made.transitions:
		if row.from == &"lobby" and row.outcome == LobbyPhase.ALL_READY:
			row.actions.append(StopBooth.new())
		if row.from == &"countdown" and row.outcome == CountdownPhase.COUNTDOWN_DONE:
			row.actions.append(ClearStations.new())
	return made


## A StartBooth of `strip` with the fixture's numbers.
static func start_of(strip: ItemKind) -> StartBooth:
	var start := StartBooth.new()
	start.strip = strip
	start.frames = FRAMES
	start.countdown_s = COUNTDOWN_S
	start.gap_s = GAP_S
	return start


## The station kind `booth`: RADIUS by HEIGHT, its Interact at it and in sight runs `start`.
static func booth_kind(start: RuleEffect) -> StationKind:
	var kind := StationKind.new()
	kind.id = &"booth"
	kind.spawn_tag = &"booth"
	kind.radius_m = RADIUS
	kind.height_m = HEIGHT
	kind.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new()] as Array[Condition],
			[start] as Array[RuleEffect]
		)
	]
	return kind


## The booth's StartBooth in `made`.
static func start_in(made: GameMode) -> StartBooth:
	for kind: StationKind in Stations.kinds_in(made):
		if kind.id == &"booth":
			return kind.actions[0].effects[0] as StartBooth
	return null


## FixtureBaseMode's layouts with the `booth` marker at BOOTH in the lobby.
static func layouts() -> Dictionary[String, LevelLayout]:
	var made := FixtureBaseMode.layouts()
	made[FixtureBaseMode.LOBBY].add_marker(&"booth", BOOTH)
	return made


## A started match of `made` that keeps its history, `peers` joined and standing inside the booth
## (0.3 m apart along x), after one tick (the booth stands).
static func in_booth(made: GameMode, peers: Array[int]) -> Match:
	var game := Match.new(made, 7, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		FixtureItemModes.stand(game, peer, inside(peer))
	return game


## A spot inside the booth for `peer`.
static func inside(peer: int) -> Vector3:
	return BOOTH + Vector3(0.3 * peer - 0.6, 0, 0.2)


## The id of the booth's station, or -1.
static func booth_id(game: Match) -> int:
	for id: int in game.state.stations:
		if game.state.stations[id].kind.id == &"booth":
			return id
	return -1


## `peer` presses the booth's button (Interact at the booth) with `seq`.
static func press(game: Match, peer: int, seq := 0) -> void:
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": booth_id(game)}, seq)


## The BoothStep events `peer` received, in order.
static func steps(game: Match, peer: int) -> Array[BoothStepEvent]:
	var found: Array[BoothStepEvent] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"BoothStep"):
		found.append(event as BoothStepEvent)
	return found


## The BoothStep events of `kind` (STARTED, FLASH, ...) `peer` received, in order.
static func steps_of(game: Match, peer: int, kind: int) -> Array[BoothStepEvent]:
	var found: Array[BoothStepEvent] = []
	for step: BoothStepEvent in steps(game, peer):
		if step.step == kind:
			found.append(step)
	return found


## The peers of a FLASH's record, in order.
static func peers_of(flash: BoothStepEvent) -> Array[int]:
	var found: Array[int] = []
	for row: Dictionary in flash.record:
		found.append(row["peer"] as int)
	return found


## The ticks from a press to its last flash and print.
static func whole() -> int:
	return COUNTDOWN + (FRAMES - 1) * GAP + 1
