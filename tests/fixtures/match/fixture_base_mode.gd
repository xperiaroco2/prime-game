class_name FixtureBaseMode
extends RefCounted
## The base mode's phase classes in a mode built in code, for the unit tests of 2b (a part's unit
## test never loads `content/`, ARCHITECTURE §9.6): lobby (LobbyPhase) -> countdown
## (CountdownPhase, 5 s) -> loading (LoadingPhase, 60 s) -> round (RoundPhase) -> end (EndPhase)
## -> lobby, with the base mode's rows. The `all_loaded` row places players on `round_player` and
## demands `knife` markers by `knives` and `circle` markers and colours by `circles`
## (FixtureDemand); `End -> Lobby` runs ResetMatch, then PlacePlayers on `lobby_player`. 1 to 4
## players. The crew wins when peer 0's counter `crew_win` is at least 1.

const LOBBY := "fixture://lobby"
const MAP := "fixture://map"
## A second map with one knife and one circle marker.
const SMALL_MAP := "fixture://small_map"
const MAX_PLAYERS := 4
const HOST := 1


static func mode() -> GameMode:
	var made := GameMode.new()
	made.min_players = 1
	made.max_players = MAX_PLAYERS
	made.player_rules = FixtureModes.player_rules()
	made.settings = [
		FixtureModes.setting(&"knives", 2, 0, 10), FixtureModes.setting(&"circles", 1, 0, 10)
	]
	made.sides = [FixtureModes.side(&"crew"), FixtureModes.side(&"dissidents")]
	made.lobby_level = LOBBY
	made.maps = PackedStringArray([MAP, SMALL_MAP])
	made.win_conditions = [FixtureModes.win(&"crew", FixtureCounterAtLeast.of(&"crew_win"))]
	var newcomer := AcceptSpec.From.NEWCOMER
	var player := AcceptSpec.From.PLAYER
	var living := AcceptSpec.From.LIVING
	var host := AcceptSpec.From.HOST
	var lobby := (
		FixtureModes
		. phase(
			&"lobby",
			LobbyPhase,
			{},
			[
				AcceptSpec.of(Intents.HELLO, newcomer),
				AcceptSpec.of(Intents.MOVE_CLAIM, living),
				AcceptSpec.of(Intents.SET_READY, player),
				AcceptSpec.of(Intents.CHANGE_SETTINGS, host),
			]
		)
	)
	lobby.level = PhaseSpec.Level.LOBBY
	lobby.snapshots = true
	var countdown := (
		FixtureModes
		. phase(
			&"countdown",
			CountdownPhase,
			{&"seconds": 5.0},
			[
				AcceptSpec.of(Intents.HELLO, newcomer),
				AcceptSpec.of(Intents.MOVE_CLAIM, living),
				AcceptSpec.of(Intents.SET_READY, player),
			]
		)
	)
	countdown.level = PhaseSpec.Level.LOBBY
	countdown.snapshots = true
	var loading := FixtureModes.phase(
		&"loading",
		LoadingPhase,
		{&"deadline_seconds": 60.0},
		[AcceptSpec.of(Intents.LOAD_ACK, player)]
	)
	loading.level = PhaseSpec.Level.MAP
	var round_spec := FixtureModes.phase(
		&"round",
		RoundPhase,
		{},
		[AcceptSpec.of(Intents.MOVE_CLAIM, living | AcceptSpec.From.GHOST)]
	)
	round_spec.level = PhaseSpec.Level.MAP
	round_spec.checks_wins = true
	round_spec.snapshots = true
	var end := FixtureModes.phase(
		&"end", EndPhase, {}, [AcceptSpec.of(Intents.RETURN_TO_LOBBY, host)]
	)
	end.level = PhaseSpec.Level.MAP
	made.phases = [lobby, countdown, loading, round_spec, end]
	made.first_phase = &"lobby"
	var circle := StationKind.new()
	circle.id = &"circle"
	circle.spawn_tag = &"circle"
	circle.palette = PackedColorArray([Color.RED, Color.BLUE])
	made.transitions = [
		FixtureModes.row(&"lobby", LobbyPhase.ALL_READY, &"countdown", []),
		FixtureModes.row(&"countdown", CountdownPhase.CANCELLED, &"lobby", []),
		FixtureModes.row(&"countdown", CountdownPhase.COUNTDOWN_DONE, &"loading", []),
		(
			FixtureModes
			. row(
				&"loading",
				LoadingPhase.ALL_LOADED,
				&"round",
				[
					FixtureModes.place(&"round_player"),
					FixtureDemand.of(&"knife", &"knives"),
					FixtureDemand.of(&"circle", &"circles", circle),
				]
			)
		),
		FixtureModes.row(&"round", Match.WON, &"end", []),
		FixtureModes.row(
			&"end", EndPhase.BACK, &"lobby", [ResetMatch.new(), FixtureModes.place(&"lobby_player")]
		),
	]
	return made


## A lobby with a lobby_player marker per player of the mode; the map with as many
## round_player markers, 3 knife and 3 circle markers; the small map with 1 of each.
static func layouts() -> Dictionary[String, LevelLayout]:
	var lobby := LevelLayout.new(LOBBY)
	var map := LevelLayout.new(MAP)
	var small := LevelLayout.new(SMALL_MAP)
	for i in MAX_PLAYERS:
		lobby.add_marker(LayoutCheck.LOBBY_PLAYER, Vector3(i * 2, 0, 0))
		map.add_marker(&"round_player", Vector3(10 + i, 0, 5))
		small.add_marker(&"round_player", Vector3(10 + i, 0, 5))
	for i in 3:
		map.add_marker(&"knife", Vector3(20 + i, 0, 0))
		map.add_marker(&"circle", Vector3(30 + i, 0, 0))
	small.add_marker(&"knife", Vector3(20, 0, 0))
	small.add_marker(&"circle", Vector3(30, 0, 0))
	return {LOBBY: lobby, MAP: map, SMALL_MAP: small}


## A started match (the lobby) that keeps its history for view_of().
static func started(seed_value: int = 7) -> Match:
	var game := Match.new(mode(), seed_value, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	return game


## `peer` connects and says Hello with `player_name` and the host's version.
static func join(game: Match, peer: int, player_name: String = "") -> void:
	FixtureModes.send(game, Intents.PEER_CONNECTED, peer)
	hello(game, peer, player_name if not player_name.is_empty() else "p%d" % peer)


static func hello(
	game: Match,
	peer: int,
	player_name: String,
	version: int = JoinRules.PROTOCOL_VERSION,
	seq: int = 0
) -> void:
	FixtureModes.send(game, Intents.HELLO, peer, {"name": player_name, "version": version}, seq)


static func ready(game: Match, peer: int, is_ready: bool = true, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.SET_READY, peer, {"ready": is_ready}, seq)


## A lobby with `peers` joined and all ready: the match is in the countdown.
static func in_countdown(peers: Array[int], seed_value: int = 7) -> Match:
	var game := started(seed_value)
	for peer: int in peers:
		join(game, peer)
	for peer: int in peers:
		ready(game, peer)
	return game


## `peers` in the countdown, then its ticks through its end tick (entry + 100): loading.
static func in_loading(peers: Array[int], seed_value: int = 7) -> Match:
	var game := in_countdown(peers, seed_value)
	FixtureModes.run_ticks(game, 101)
	return game


static func load_ack(game: Match, peer: int, match_id: int = -1, seq: int = 0) -> void:
	var id := match_id if match_id >= 0 else game.state.match_id()
	FixtureModes.send(game, Intents.LOAD_ACK, peer, {"match_id": id}, seq)


## `peers` loaded: the match is in the round.
static func in_round(peers: Array[int], seed_value: int = 7) -> Match:
	var game := in_loading(peers, seed_value)
	for peer: int in peers:
		load_ack(game, peer)
	return game


## `peers` in the round, then the crew wins: the match is in End.
static func in_end(peers: Array[int], seed_value: int = 7) -> Match:
	var game := in_round(peers, seed_value)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	return game


## The events `peer` received since the `from`-th, by name.
static func names_since(game: Match, peer: int, from: int) -> Array[StringName]:
	return game.view_of(peer).event_names().slice(from)


## The names of the server directives emitted so far, in order.
static func directives(game: Match) -> Array[String]:
	var found: Array[String] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.is_directive:
			var fields := emitted.event.to_dict()
			var text := String(emitted.event.event_name())
			if fields.has("peer"):
				text += " %d" % fields["peer"]
			found.append(text)
	return found
