class_name FixtureBanModes
extends RefCounted
## FixtureBaseMode with two task types, for the lobby's bans of task types (#79; a part's unit test
## never loads `content/`, ARCHITECTURE §9.6): `first` deals 2 tokens and `second` 4, both on the
## `token` spawn tag; the settings `tasks` (1, 1 to 2) and `banned_task_types`; DealTasks (purpose
## `task_types`) first on the `all_loaded` row. The map has 5 `token` markers, the small map 1.

const TOKEN_TAG := &"token"
const MAP_TOKENS := 5


static func mode() -> GameMode:
	var made := FixtureBaseMode.mode()
	var token := ItemKind.new()
	token.id = &"token"
	token.display_name = "Token"
	token.spawn_tag = TOKEN_TAG
	token.hands = 1
	made.item_kinds = [token]
	made.task_types = [
		FixtureDealtTaskType.new(&"first", token, 2), FixtureDealtTaskType.new(&"second", token, 4)
	]
	made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 2))
	made.settings.append(FixtureDealModes.banned_setting())
	made.find_transition(&"loading", LoadingPhase.ALL_LOADED).actions.insert(
		0, FixtureDealModes.deal_tasks()
	)
	return made


static func layouts() -> Dictionary[String, LevelLayout]:
	var found := FixtureBaseMode.layouts()
	for i in MAP_TOKENS:
		found[FixtureBaseMode.MAP].add_marker(TOKEN_TAG, Vector3(40 + i, 0, 0))
	found[FixtureBaseMode.SMALL_MAP].add_marker(TOKEN_TAG, Vector3(40, 0, 0))
	return found


## A started match (the lobby) of mode() that keeps its history for view_of().
static func started(seed_value: int = 7) -> Match:
	var game := Match.new(mode(), seed_value, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	return game


## The host (peer 1) changes the settings with `settings`.
static func change(game: Match, settings: Variant, seq: int = 0) -> void:
	FixtureModes.send(
		game, Intents.CHANGE_SETTINGS, FixtureBaseMode.HOST, {"settings": settings}, seq
	)


## The last SettingsChanged `peer` received.
static func last_change(game: Match, peer: int) -> SettingsChangedEvent:
	return game.view_of(peer).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
