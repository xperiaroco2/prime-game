class_name MatchState
extends RefCounted
## Everything of a match that outlives a phase (ARCHITECTURE §3.1, §9.1): the roster, the
## settings, the players, the items, the tasks with their task states, the stations, the bodies,
## the cooldown and counter tables, the per-part state, the match clock and the RNG streams.
## Parts keep their changing state here or in the phase object, never on themselves.
##
## A new part class that needs state of its own takes a per-part state object (part_state()), so
## a new mechanic adds state without a new field here.

## Peer id -> player; iterate with peers() for peer-id order.
var players: Dictionary[int, PlayerState] = {}
## The match settings' values (§9.1), from the mode's defaults.
var settings: Dictionary[StringName, int] = {}
## The set settings' values (SettingSpec.Kind.TASK_TYPES: the host's bans of task types, #79):
## setting id -> ids in the mode's order. A setting the host never changed is absent: the empty
## set, its default.
var id_sets: Dictionary[StringName, PackedStringArray] = {}
## The map this match plays on: one of the mode's maps.
var map: String
## Id -> item, in id order.
var items: Dictionary[int, ItemState] = {}
## Id -> task, in id order.
var tasks: Dictionary[int, MatchTask] = {}
## Id -> station, in id order.
var stations: Dictionary[int, StationState] = {}
## Peer -> body rest position: a dead player's, from its death until its respawn (M4-3) or its
## leave (§3.5).
var bodies: Dictionary[int, Vector3] = {}
## Match-clock ticks left while it runs or is paused; -1 before StartClock (2h).
var clock_ticks_left := -1
var clock_ended := false
## The winning side once EndMatch ran (2h), else empty.
var winner: StringName
var rng: RngStreams
## The mode's numbers for a player's body: a new or reset player starts from them.
var player_rules: PlayerRules
## Connected peers whose Hello was not accepted yet (2b), peer -> true: only they may join.
var newcomers: Dictionary[int, bool] = {}
## The joins accepted in the session (2b): a joiner without a usable name of its own (#550) is
## Player<n>, n its join's number, counted for every join whatever the name. Session state:
## reset_match() keeps it, and a leave never lowers it, so a number is never reused (§3.5).
var joins := 0
## The lobby's name the host set (#214, ChangeSettings's `lobby_name`), as LobbyName cleaned it;
## "" is the default, which each client shows as `lobby.default_name` with the host's name.
## Session state: reset_match() keeps it, so the lobby keeps its name from match to match (§3.5).
var lobby_name := ""
## Roles forced per peer (debug builds only, §8, §9.7: a debug command or a scenario), which
## DealRoles applies before its draws; a forced role counts toward its quota (the engineer's
## answer A on #30). Session state: reset_match() keeps it. core/ cannot tell a debug build, so
## only server/'s debug path or the scenario runner sets it, with the ForceRole command.
var forced_roles: Dictionary[int, StringName] = {}
## The match clock's length in seconds that StartClock uses instead of its minutes setting, or 0
## (the ForceClock command, debug builds only, like forced_roles). Session state: reset_match()
## keeps it.
var forced_clock_s := 0

var _next_item_id := 1
var _next_task_id := 1
var _next_station_id := 1
## Peer -> {key: tick}: the tick at which a player last paid a cooldown key.
var _cooldowns: Dictionary[int, Dictionary] = {}
## Peer -> {key: value}.
var _counters: Dictionary[int, Dictionary] = {}
var _part_state: Dictionary[StringName, RefCounted] = {}


func _init(session_seed: int) -> void:
	rng = RngStreams.new(session_seed)


## Adds a player to the roster (a join, 2b). Returns the existing one if the peer is a player.
func add_player(peer: int, player_name: String) -> PlayerState:
	if players.has(peer):
		return players[peer]
	var joined := PlayerState.new(peer, player_name)
	reset_player(joined, player_rules)
	players[peer] = joined
	return joined


## Counts an accepted join and returns its fallback name, Player<n> with n the join's number in
## the session (§3.5, the engineer's decision of 2026-09-30 on #58), which JoinRules gives a
## joiner without a usable name of its own (#550).
func name_next_joiner() -> String:
	joins += 1
	return "Player%d" % joins


## The index of the current match in the session, 0 for the first (LoadMatch, LoadAck; 2b).
func match_id() -> int:
	return rng.match_index


## Removes a player from the roster (a leave outside Round, or a missed load; 2b).
func remove_player(peer: int) -> void:
	players.erase(peer)


func player(peer: int) -> PlayerState:
	return players.get(peer)


## Every player's peer id, sorted: the stable order of §3.3.
func peers() -> Array[int]:
	var found: Array[int] = []
	found.assign(players.keys())
	found.sort()
	return found


## The players who have not left, sorted.
func present_peers() -> Array[int]:
	var found: Array[int] = []
	for peer: int in peers():
		if players[peer].is_present():
			found.append(peer)
	return found


func is_present(peer: int) -> bool:
	return players.has(peer) and players[peer].is_present()


func add_item(kind: ItemKind, at: Vector3) -> ItemState:
	var item := ItemState.new(_next_item_id, kind, at)
	items[item.id] = item
	_next_item_id += 1
	return item


func add_task(type: TaskType) -> MatchTask:
	var task := MatchTask.new(_next_task_id, type, type.new_state())
	tasks[task.id] = task
	_next_task_id += 1
	return task


func add_station(kind: StationKind, at: Vector3, colour: Color) -> StationState:
	var station := StationState.new(_next_station_id, kind, at, colour)
	stations[station.id] = station
	_next_station_id += 1
	return station


## The tick at which `peer` last paid cooldown `key`, or -1 if never.
func cooldown_paid_at(peer: int, key: StringName) -> int:
	var table: Dictionary = _cooldowns.get(peer, {})
	return table.get(key, -1)


func set_cooldown_paid(peer: int, key: StringName, tick: int) -> void:
	if not _cooldowns.has(peer):
		_cooldowns[peer] = {}
	_cooldowns[peer][key] = tick


## A counter of `peer` (uses left, #34), 0 until set.
func counter(peer: int, key: StringName) -> int:
	var table: Dictionary = _counters.get(peer, {})
	return table.get(key, 0)


func set_counter(peer: int, key: StringName, value: int) -> void:
	if not _counters.has(peer):
		_counters[peer] = {}
	_counters[peer][key] = value


func add_to_counter(peer: int, key: StringName, amount: int) -> int:
	var value := counter(peer, key) + amount
	set_counter(peer, key, value)
	return value


## The state object of the part class that declares `key`, made by `create` (a Callable
## returning a RefCounted) on first use.
func part_state(key: StringName, create: Callable) -> RefCounted:
	if not _part_state.has(key):
		var made: RefCounted = create.call()
		_part_state[key] = made
	return _part_state[key]


## Clears everything a match changed and keeps the roster (ResetMatch, 2b): items, stations,
## tasks and their states, bodies, cooldowns, counters, per-part state, the clock and the winner;
## the players who left during the match (§3.5) leave the roster; each other player's role,
## life, hand, health and stamina start again from player_rules; everyone un-ready. The RNG moves
## to the next match of the session (§3.3); the join count stays (§3.5).
func reset_match() -> void:
	for peer: int in peers():
		if not players[peer].is_present():
			remove_player(peer)
	items.clear()
	tasks.clear()
	stations.clear()
	bodies.clear()
	_cooldowns.clear()
	_counters.clear()
	_part_state.clear()
	_next_item_id = 1
	_next_task_id = 1
	_next_station_id = 1
	clock_ticks_left = -1
	clock_ended = false
	winner = &""
	for peer: int in peers():
		reset_player(players[peer], player_rules)
	rng.next_match()


## A player as at the start of a match: no role, alive, empty hand and belt, full health and
## stamina.
static func reset_player(someone: PlayerState, rules: PlayerRules) -> void:
	someone.ready = false
	someone.role = &""
	someone.life = PlayerState.Life.ALIVE
	someone.life_deadline = -1
	someone.knockdown_left = -1
	someone.invulnerable_until = -1
	someone.held_item = -1
	someone.belt_item = -1
	someone.velocity = Vector3.ZERO
	someone.sprinting = false
	someone.sprint_held = false
	someone.moving = false
	someone.stamina_settled_tick = -1
	if rules != null:
		someone.health = Ticks.thousandths(rules.health)
		someone.stamina = Ticks.thousandths(rules.stamina)
