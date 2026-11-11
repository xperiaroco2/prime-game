class_name FixtureMirror
extends RefCounted
## FixtureLobbyHands with a mirror as the base mode has one (#1394; a part's unit test never loads
## `content/`, ARCHITECTURE §9.6): the station kind `mirror` (spawn tag `mirror`, radius RADIUS),
## whose Interact at a place and in sight, with the place free or its own, runs a UseMirror. Lobby
## and Countdown run StationTicks with `every_marker` (the places) and MirrorTicks;
## `countdown_done` runs ClearItems, EndMirror and ClearStations. The lobby layout holds two
## `mirror` markers, PLACES.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2
const P3 := FixtureLobbyHands.P3
## The two places, 1.5 m apart, away from the lobby's spawn markers.
const PLACES: Array[Vector3] = [Vector3(-5, 0, 0), Vector3(-5, 0, 1.5)]
const RADIUS := 0.6


static func mode() -> GameMode:
	return with_mirror(FixtureLobbyHands.clearing(FixtureLobbyHands.mode()))


## `made` (FixtureLobbyHands' clearing mode, or one built the same way from another base) with the
## mirror as mode() has it.
static func with_mirror(made: GameMode) -> GameMode:
	var placing := StationTicks.new()
	placing.kind = mirror_kind()
	placing.every_marker = true
	var ticks := MirrorTicks.new()
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		spec.tick_systems.append(placing)
		spec.tick_systems.append(ticks)
	for row: Transition in made.transitions:
		if row.from == &"countdown" and row.outcome == CountdownPhase.COUNTDOWN_DONE:
			row.actions.append(EndMirror.new())
			row.actions.append(ClearStations.new())
	return made


## The station kind `mirror`: radius RADIUS, height 2.5 m, its Interact runs a UseMirror.
static func mirror_kind() -> StationKind:
	var kind := StationKind.new()
	kind.id = &"mirror"
	kind.spawn_tag = &"mirror"
	kind.radius_m = RADIUS
	kind.height_m = 2.5
	kind.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new(), MirrorFree.new()] as Array[Condition],
			[UseMirror.new()] as Array[RuleEffect]
		)
	]
	return kind


## FixtureBaseMode's layouts with the `mirror` markers at PLACES in the lobby.
static func layouts() -> Dictionary[String, LevelLayout]:
	var made := FixtureBaseMode.layouts()
	for at: Vector3 in PLACES:
		made[FixtureBaseMode.LOBBY].add_marker(&"mirror", at)
	return made


## A started match of `made` that keeps its history, `peers` joined, after one tick (the places
## stand).
static func joined(made: GameMode, peers: Array[int]) -> Match:
	var game := Match.new(made, 7, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	return game


## The station of place `index` (PLACES' order), or -1.
static func place(game: Match, index: int) -> int:
	for id: int in game.state.stations:
		var station := game.state.stations[id]
		if station.kind.id == &"mirror" and station.position == PLACES[index]:
			return id
	return -1


## `peer` stands at place `index`, inside its cylinder.
static func stand_at(game: Match, peer: int, index: int) -> void:
	FixtureItemModes.stand(game, peer, PLACES[index] + Vector3(0.2, 0, 0))


## `peer` stands at place `index` and presses E at it (Interact) with `seq`, then a tick runs.
static func use(game: Match, peer: int, index: int, seq := 0) -> void:
	stand_at(game, peer, index)
	interact(game, peer, index, seq)


## `peer` presses E at place `index` (Interact) with `seq` from where it stands, then a tick runs.
static func interact(game: Match, peer: int, index: int, seq := 0) -> void:
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": place(game, index)}, seq)
	FixtureModes.run_ticks(game, 1)


## `peer` asks for colour `colour` keeping its name (SetProfile) with `seq`, then a tick runs.
static func set_colour(game: Match, peer: int, colour: int, seq := 0) -> void:
	var fields := {"name": game.state.player(peer).name, "colour": colour}
	FixtureModes.send(game, Intents.SET_PROFILE, peer, fields, seq)
	FixtureModes.run_ticks(game, 1)


## The MirrorPlaces events `peer` received, as plain data, in order.
static func told(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"MirrorPlaces"):
		found.append(event.to_dict())
	return found


## The places in use as the last MirrorPlaces `peer` received showed them: station -> peer.
static func shown(game: Match, peer: int) -> Dictionary[int, int]:
	var found := told(game, peer)
	var held: Dictionary[int, int] = {}
	if found.is_empty():
		return held
	var last: Dictionary = found.back()
	var stations: PackedInt32Array = last["stations"]
	var peers: PackedInt32Array = last["peers"]
	for i in stations.size():
		held[stations[i]] = peers[i]
	return held
