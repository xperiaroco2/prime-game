class_name FixtureToggles
extends RefCounted
## FixtureBaseMode with world toggles (#1295; a part's unit test never loads `content/`,
## ARCHITECTURE §9.6): the round accepts Interact from the living, and Loading -> Pregame places
## (PlaceToggles, after the row's own actions) the kinds `cover` (key `cover`, tag `cover`), `book`
## and `bottle` (one key, `bookcase`: the bookcase and its wine rack) and `breaker` (no key). Each
## kind's Interact at it and in sight runs ToggleStation. The map holds two `cover` markers
## (COVERS), one `book` (BOOK), one `bottle` (BOTTLE) and one `breaker` (BREAKER).

const P1 := 2
const P2 := 3
const COVERS: Array[Vector3] = [Vector3(40, 0, 0), Vector3(44, 0, 0)]
const BOOK := Vector3(50, 0, 0)
const BOTTLE := Vector3(50, 0, 8)
const BREAKER := Vector3(60, 0, 0)
## The fixture's toggle Cooldown (a test number, as the tap's 0.25 s).
const COOLDOWN_S := 0.25


static func mode() -> GameMode:
	var made := FixtureBaseMode.mode()
	made.find_phase(&"round").accepts.append(
		AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING)
	)
	var placing := PlaceToggles.new()
	placing.kinds = [
		kind(&"cover", &"cover"),
		kind(&"book", &"bookcase"),
		kind(&"bottle", &"bookcase"),
		kind(&"breaker", &""),
	]
	for row: Transition in made.transitions:
		if row.to == &"pregame":
			row.actions.append(placing)
	return made


## A toggle kind `id` (spawn tag `id`, key `key`): radius 1.5 m, height 2 m, its Interact at it, in
## sight and past cooldown() runs ToggleStation.
static func kind(id: StringName, key: StringName) -> StationKind:
	var made := StationKind.new()
	made.id = id
	made.spawn_tag = id
	made.toggle_key = key
	made.radius_m = 1.5
	made.height_m = 2.0
	made.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new(), cooldown()] as Array[Condition],
			[ToggleStation.new()] as Array[RuleEffect]
		)
	]
	return made


## The toggles' flood guard (ToggleStation's required Cooldown): one flip per player per COOLDOWN_S.
static func cooldown() -> Cooldown:
	var made := Cooldown.new()
	made.key = &"toggle"
	made.seconds = COOLDOWN_S
	return made


## FixtureBaseMode's layouts with the toggles' markers on the map.
static func layouts() -> Dictionary[String, LevelLayout]:
	var made := FixtureBaseMode.layouts()
	var map := made[FixtureBaseMode.MAP]
	for spot: Vector3 in COVERS:
		map.add_marker(&"cover", spot)
	map.add_marker(&"book", BOOK)
	map.add_marker(&"bottle", BOTTLE)
	map.add_marker(&"breaker", BREAKER)
	return made


## A match of `made` on `world` that keeps its history, `peers` joined, ready and loaded: in the
## pregame, whose entry placed the toggles.
static func in_pregame(made: GameMode, world: WorldQuery, peers: Array[int]) -> Match:
	var game := Match.new(made, 7, world, layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	return game


## in_pregame, then through the pregame: the round.
static func in_round(made: GameMode, world: WorldQuery, peers: Array[int]) -> Match:
	var game := in_pregame(made, world, peers)
	FixtureBaseMode.through_pregame(game)
	return game


## The ids of the stations of kind `kind_id`, in id order.
static func ids_of(game: Match, kind_id: StringName) -> Array[int]:
	var found: Array[int] = []
	var ids: Array[int] = []
	ids.assign(game.state.stations.keys())
	ids.sort()
	for id: int in ids:
		if game.state.stations[id].kind.id == kind_id:
			found.append(id)
	return found


## `peer` stands half a metre beside `at` and sends Interact naming `station`.
static func flip(game: Match, peer: int, station: int, at: Vector3, seq: int = 1) -> void:
	FixtureItemModes.stand(game, peer, at + Vector3(0.5, 0, 0))
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": station}, seq)
	FixtureModes.run_ticks(game, 1)
