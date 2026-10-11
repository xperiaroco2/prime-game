class_name FixtureMapTaskModes
extends RefCounted
## FixtureBaseMode with two task types, one of them on one map only (TaskType.maps, the Generator
## ADR's GE15, #803; a part's unit test never loads `content/`, ARCHITECTURE §9.6): `anywhere`
## (no maps listed: every map) deals 1 token on the `token` spawn tag, and `map_only` (listing
## FixtureBaseMode.MAP alone) 2 lone tokens on the `lone` tag, which only the map has markers of.
## The settings `tasks` (2, 1 to 2) and `banned_task_types`; DealTasks (purpose `task_types`)
## first on the `all_loaded` row. The map has 5 `token` and 3 `lone` markers, the small map 2
## `token` markers and no `lone` one. So on the small map only `anywhere` plays, and `tasks`'
## default of 2 is above its pool.

const TOKEN_TAG := &"token"
const LONE_TAG := &"lone"
const MAP_TOKENS := 5
const MAP_LONES := 3
const SMALL_MAP_TOKENS := 2


static func mode() -> GameMode:
	var made := FixtureBaseMode.mode()
	var token := _kind(&"token", TOKEN_TAG)
	var lone := _kind(&"lone_token", LONE_TAG)
	made.item_kinds = [token, lone]
	var map_only := FixtureDealtTaskType.new(&"map_only", lone, 2)
	map_only.maps = PackedStringArray([FixtureBaseMode.MAP])
	made.task_types = [FixtureDealtTaskType.new(&"anywhere", token, 1), map_only]
	made.settings.append(FixtureModes.setting(&"tasks", 2, 1, 2))
	made.settings.append(FixtureDealModes.banned_setting())
	made.find_transition(&"loading", LoadingPhase.ALL_LOADED).actions.insert(
		0, FixtureDealModes.deal_tasks()
	)
	return made


static func layouts() -> Dictionary[String, LevelLayout]:
	var found := FixtureBaseMode.layouts()
	for i in MAP_TOKENS:
		found[FixtureBaseMode.MAP].add_marker(TOKEN_TAG, Vector3(40 + i, 0, 0))
	for i in MAP_LONES:
		found[FixtureBaseMode.MAP].add_marker(LONE_TAG, Vector3(50 + i, 0, 0))
	for i in SMALL_MAP_TOKENS:
		found[FixtureBaseMode.SMALL_MAP].add_marker(TOKEN_TAG, Vector3(40 + i, 0, 0))
	return found


## A started match (the lobby) of `game_mode` (mode() when null) that keeps its history for
## view_of().
static func started(seed_value: int = 7, game_mode: GameMode = null) -> Match:
	var played := game_mode if game_mode != null else mode()
	var game := Match.new(played, seed_value, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	return game


## A match of mode() on `map` with the host (peer 1) alone, `settings` changed in the lobby
## (ChangeSettings: numbers and `banned_task_types`), played to the round: the deal has run.
static func in_round(map: String, settings: Dictionary = {}, seed_value: int = 7) -> Match:
	var game := started(seed_value)
	FixtureBaseMode.join(game, FixtureBaseMode.HOST)
	var changed := settings.duplicate()
	if map == FixtureBaseMode.SMALL_MAP:
		# The small map has 1 knife marker.
		changed["knives"] = 1
	FixtureModes.send(
		game, Intents.CHANGE_SETTINGS, FixtureBaseMode.HOST, {"map": map, "settings": changed}
	)
	FixtureBaseMode.ready(game, FixtureBaseMode.HOST)
	FixtureModes.run_ticks(game, 101)
	FixtureBaseMode.load_ack(game, FixtureBaseMode.HOST)
	FixtureBaseMode.through_pregame(game)
	return game


## The ids of the task types `game` dealt, in task-id order.
static func dealt_types(game: Match) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: int in game.state.tasks:
		found.append(game.state.tasks[id].type.id)
	return found


static func _kind(kind_id: StringName, tag: StringName) -> ItemKind:
	var kind := ItemKind.new()
	kind.id = kind_id
	kind.display_name = String(kind_id).capitalize()
	kind.spawn_tag = tag
	kind.hands = 1
	return kind
