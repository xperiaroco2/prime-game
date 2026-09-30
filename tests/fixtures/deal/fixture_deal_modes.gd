class_name FixtureDealModes
extends RefCounted
## A game mode with the deal, built in code for the deal's unit tests (a part's unit tests never
## load `content/`, ARCHITECTURE §9.6).
##
## deal_mode(): lobby (FixturePhase: Hello, SetReady, `all_ready`) -> round (RoundPhase). The
## `lobby, all_ready -> round` row runs the deal as the base mode's `Loading, all_loaded -> Round`
## does: DealRoles (Dissident by `dissidents`, leaving at least 1; default Crew; purpose `roles`),
## DealTasks (`tasks_per_player`), SpawnItems (Knife by `knives`; purpose `knives`), PlacePlayers
## (`round_player`). Its task types are FixtureDealtTaskTypes whose tokens share the knives'
## spawn tag `item`, so SpawnItems must skip the markers the tokens took.

const LOBBY := "fixture://deal_lobby"
const MAP := "fixture://deal_map"
## The spawn tag of the knives and the tokens.
const ITEM_TAG := &"item"
const MAX_PLAYERS := 10
## The map's `item` markers: enough for 10 players x 3 tasks and 5 knives.
const ITEM_MARKERS := 40
## The spawn tag of a FixtureDealtTaskType's stations, with a marker per token of 10 players x 3.
const STATION_TAG := &"station"
const STATION_MARKERS := 30


## The mode, with `task_types` (one FixtureDealtTaskType when empty).
static func deal_mode(task_types: Array[TaskType] = []) -> GameMode:
	var mode := GameMode.new()
	mode.min_players = 1
	mode.max_players = MAX_PLAYERS
	mode.player_rules = FixtureModes.player_rules()
	mode.settings = [
		FixtureModes.setting(&"dissidents", 1, 0, 9),
		FixtureModes.setting(&"tasks_per_player", 2, 0, 3),
		FixtureModes.setting(&"knives", 2, 0, 5),
	]
	mode.sides = [FixtureModes.side(&"crew"), FixtureModes.side(&"dissidents")]
	var crew := FixtureModes.role(&"crew", &"crew", false)
	var dissident := FixtureModes.role(&"dissident", &"dissidents", true)
	mode.roles = [crew, dissident]
	var knife := item_kind(&"knife")
	var token := item_kind(&"token")
	mode.item_kinds = [knife, token]
	if task_types.is_empty():
		mode.task_types = [FixtureDealtTaskType.new(&"fixture_dealt", token)]
	else:
		mode.task_types = task_types
	mode.lobby_level = LOBBY
	mode.maps = PackedStringArray([MAP])
	var lobby := (
		FixtureModes
		. phase(
			&"lobby",
			FixturePhase,
			{&"reports_all_ready": 1.0},
			[
				AcceptSpec.of(Intents.HELLO, AcceptSpec.From.NEWCOMER),
				AcceptSpec.of(Intents.SET_READY, AcceptSpec.From.PLAYER),
			]
		)
	)
	lobby.level = PhaseSpec.Level.LOBBY
	var round_spec := FixtureModes.phase(
		&"round",
		RoundPhase,
		{},
		[AcceptSpec.of(Intents.MOVE_CLAIM, AcceptSpec.From.LIVING | AcceptSpec.From.GHOST)]
	)
	round_spec.level = PhaseSpec.Level.MAP
	round_spec.snapshots = true
	mode.phases = [lobby, round_spec]
	mode.first_phase = &"lobby"
	mode.transitions = [
		(
			FixtureModes
			. row(
				&"lobby",
				&"all_ready",
				&"round",
				[
					deal_roles(dissident, crew),
					deal_tasks(),
					spawn_items(knife),
					FixtureModes.place(&"round_player"),
				]
			)
		),
	]
	return mode


## A token kind for a FixtureDealtTaskType of another mode's test, on the `item` tag.
static func item_kind(kind_id: StringName) -> ItemKind:
	var kind := ItemKind.new()
	kind.id = kind_id
	kind.display_name = String(kind_id).capitalize()
	kind.spawn_tag = ITEM_TAG
	return kind


static func deal_roles(quota_role: GameRole, default_role: GameRole) -> DealRoles:
	var quota := RoleQuota.new()
	quota.role = quota_role
	quota.count_setting = &"dissidents"
	quota.leave_at_least = 1
	var effect := DealRoles.new()
	effect.quotas = [quota]
	effect.default_role = default_role
	effect.rng_purpose = &"roles"
	return effect


static func deal_tasks() -> DealTasks:
	var effect := DealTasks.new()
	effect.tasks_setting = &"tasks_per_player"
	return effect


static func spawn_items(kind: ItemKind) -> SpawnItems:
	var effect := SpawnItems.new()
	effect.kind = kind
	effect.count_setting = &"knives"
	effect.rng_purpose = &"knives"
	return effect


## A lobby with MAX_PLAYERS lobby_player markers; a map with MAX_PLAYERS round_player markers,
## `item_markers` item markers and STATION_MARKERS station markers, all at distinct positions.
static func layouts(item_markers: int = ITEM_MARKERS) -> Dictionary[String, LevelLayout]:
	var lobby := LevelLayout.new(LOBBY)
	var map := LevelLayout.new(MAP)
	for i in MAX_PLAYERS:
		lobby.add_marker(&"lobby_player", Vector3(i, 0, 0))
		map.add_marker(&"round_player", Vector3(i, 0, -5))
	for i in item_markers:
		map.add_marker(ITEM_TAG, Vector3(i, 0, 5))
	for i in STATION_MARKERS:
		map.add_marker(STATION_TAG, Vector3(i, 0, 10))
	return {LOBBY: lobby, MAP: map}


## A match of `mode` whose players `peers` joined, with `settings` over the defaults, all ready:
## the deal has run and the match is in the round.
static func dealt(
	mode: GameMode,
	peers: Array[int],
	settings: Dictionary[StringName, int] = {},
	seed_value: int = 7,
	item_markers: int = ITEM_MARKERS
) -> Match:
	var game := Match.new(mode, seed_value, FlatWorldQuery.new(), layouts(item_markers))
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for id: StringName in settings:
		game.state.settings[id] = settings[id]
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## The players `game` dealt `role_id`, in peer-id order.
static func players_of(game: Match, role_id: StringName) -> Array[int]:
	var found: Array[int] = []
	for peer: int in game.state.peers():
		if game.state.player(peer).role == role_id:
			found.append(peer)
	return found


## Every item of `kind_id` in `game`, in id order.
static func items_of(game: Match, kind_id: StringName) -> Array[ItemState]:
	var found: Array[ItemState] = []
	for id: int in game.state.items:
		if game.state.items[id].kind.id == kind_id:
			found.append(game.state.items[id])
	return found
