class_name MatchState
extends RefCounted
## Everything of a match that outlives a phase (ARCHITECTURE §3.1, §9.1): the roster, the
## settings, the players, the items, the tasks with their task states, the stations, the bodies,
## the cooldown and counter tables, the per-part state, the match clock and the RNG streams.
## Parts keep their changing state here or in the phase object, never on themselves.
##
## A new part class that needs state of its own takes a per-part state object (part_state()), so
## a new mechanic adds state without a new field here.

## The highest item id: the wire's `item` type is a u16 whose all-ones value means none (§4.3.1,
## a test pins the two), so ids run from 1 to 0xFFFE.
const MAX_ITEM_ID := 0xFFFE
## The host's own player's peer id (§4: the host is always peer 1): the transport's
## NetTransport.HOST_ID, which core/ cannot name, so a test pins the two.
const HOST_PEER := 1

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
## Id -> item, in the order they were added: id order until an id is reused (past MAX_ITEM_ID,
## add_item), so a part that needs §3.3's stable order sorts the ids (FlightTicks, VanishTicks).
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
## The ticks StartClock set the clock to; -1 before it ran (#548: EndMatch gives the round's
## length as the ticks counted down since).
var clock_ticks_total := -1
var clock_ended := false
## The winning side once EndMatch ran (2h), else empty.
var winner: StringName
var rng: RngStreams
## The mode's numbers for a player's body: a new or reset player starts from them.
var player_rules: PlayerRules
## Connected peers whose Hello was not accepted yet (2b), peer -> true: only they may join.
var newcomers: Dictionary[int, bool] = {}
## The highest number a join was given in the session (2b, §3.5): a joiner that is no return gets
## the next one (give_number), with a name of its own or not, and its fallback name is
## Player<number>; a return gets its old number back and does not step it. Session state:
## reset_match() keeps it, and a leave never lowers it, so a number is never given twice.
var joins := 0
## The return keys the session bound, key -> number (§3.5; the returning-players ADR, Decision 2):
## a key binds to the number of the first join that carried it. Session state like joins:
## reset_match() keeps it, and a leave never removes an entry. The only place core/ keeps a key:
## never a PlayerState field, never an event's (§5).
var numbers: Dictionary[String, int] = {}
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
## The ids remove_item freed, the one freed longest ago first (the cooking ADR, CE3): add_item
## takes from it only once the counter is past MAX_ITEM_ID.
var _freed_item_ids: Array[int] = []
var _next_task_id := 1
var _next_station_id := 1
## Peer -> {key: tick}: the tick at which a player last paid a cooldown key.
var _cooldowns: Dictionary[int, Dictionary] = {}
## Peer -> {key: value}.
var _counters: Dictionary[int, Dictionary] = {}
var _part_state: Dictionary[StringName, RefCounted] = {}
var _session_part_state: Dictionary[StringName, RefCounted] = {}


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


## The number of an accepted join that carried `key` (§3.5; the engineer's decision of 2026-09-30
## on #58; the returning-players ADR, Decision 2, P2, P7). A usable key (ReturnKey.is_valid) bound
## to a number no present player holds: that number again, and joins stays. Otherwise the next
## number (joins + 1, counted), and a usable key not bound yet is bound to it; a key whose number a
## present player holds stays with that player (a second window, or a return faster than the host
## noticed the leave). An unusable key or none: the next number, no binding.
func give_number(key: Variant) -> int:
	var usable := ReturnKey.is_valid(key)
	if usable and numbers.has(key) and not holds_number(numbers[key]):
		return numbers[key]
	joins += 1
	if usable and not numbers.has(key):
		numbers[key] = joins
	return joins


## Whether a present player holds `number`.
func holds_number(number: int) -> bool:
	for peer: int in present_peers():
		if players[peer].number == number:
			return true
	return false


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


## A new item of `kind` at `at`, on the ground. Its id is the counter's next while the counter has
## not passed MAX_ITEM_ID, else the id remove_item freed longest ago (CE3: so the gap between a free
## and its reuse is as long as it can be, and no normal match ever reuses one); null when every id
## is in use. Its rest tick is not set: a part that leaves it lying spawns it with Items.spawn.
func add_item(kind: ItemKind, at: Vector3) -> ItemState:
	var id := -1
	if _next_item_id <= MAX_ITEM_ID:
		id = _next_item_id
		_next_item_id += 1
	elif not _freed_item_ids.is_empty():
		id = _freed_item_ids.pop_front()
	else:
		return null
	var item := ItemState.new(id, kind, at)
	items[id] = item
	return item


## Moves the item counter on to `next` (never back, never past MAX_ITEM_ID + 1), as if the ids
## before it had been handed out: the unit tests of id reuse (the cooking ADR §7, CE3) start a
## short match near the limit through a fixture action. No rule calls it.
func skip_item_ids_to(next: int) -> void:
	_next_item_id = clampi(next, _next_item_id, MAX_ITEM_ID + 1)


## Removes item `id` from the match (Items.vanish) and queues its id for reuse; nothing for an id
## that is not an item. The caller has emptied any hand or belt slot that held it.
func remove_item(id: int) -> void:
	if not items.has(id):
		return
	items.erase(id)
	_freed_item_ids.append(id)


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


## Removes every station and numbers the next one 1 again (ClearStations, #1390): the lobby's tap
## goes before the deal, so a match's dealt stations number from 1 whether a lobby station stood or
## not. Only while no task is dealt: a task's state may name its stations' ids.
func clear_stations() -> void:
	stations.clear()
	_next_station_id = 1


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


## The session state object of the part class that declares `key`, made by `create` on first use:
## as part_state(), but session state (§3.5) like lobby_name: reset_match() keeps it, so it stays
## from match to match while the lobby stays (the pinball's best score, #1398); nothing writes it
## to disk.
func session_part_state(key: StringName, create: Callable) -> RefCounted:
	if not _session_part_state.has(key):
		var made: RefCounted = create.call()
		_session_part_state[key] = made
	return _session_part_state[key]


## Clears everything a match changed and keeps the roster (ResetMatch, 2b): items, stations,
## tasks and their states, bodies, cooldowns, counters, per-part state, the clock and the winner;
## the players who left during the match (§3.5) leave the roster; each other player's role,
## life, hand, health and stamina start again from player_rules; everyone un-ready. The RNG moves
## to the next match of the session (§3.3); the join count, the return keys' numbers and the
## session part state (session_part_state()) stay (§3.5).
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
	_freed_item_ids.clear()
	_next_task_id = 1
	_next_station_id = 1
	clock_ticks_left = -1
	clock_ticks_total = -1
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
	someone.clear_places()
	someone.velocity = Vector3.ZERO
	someone.sprinting = false
	someone.crouched = false
	someone.sneaking = false
	someone.stand_up()
	someone.sober()
	someone.sprint_held = false
	someone.moving = false
	someone.motion = null
	someone.limp = null
	someone.stamina_settled_tick = -1
	if rules != null:
		someone.health = Ticks.thousandths(rules.health)
		someone.stamina = Ticks.thousandths(rules.stamina)
