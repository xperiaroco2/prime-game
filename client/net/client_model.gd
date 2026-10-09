class_name ClientModel
extends RefCounted
## What one client knows now (ARCHITECTURE §4.6), folded from the events and snapshots it decoded:
## its peer id and epoch, the phase, the roster, the settings, the items with every player's hand
## and belt and their flights (§7.1.16), the stations (a zone's progress too), the tasks and
## bodies, each player's life (E25), the avatars of the newest snapshot and its own SelfStatus.
## Built only from what the host sent this client, never from core/ state (invariant 2). The game
## mode is the client's own copy, read for where each phase plays.
##
## A match's facts (items, stations, bodies, role, tasks, avatars and the like) are cleared on
## LoadMatch and on entering the lobby: a new level holds none of the old ones. A snapshot sent
## before that change but arriving after it (the unreliable lane against the reliable one) is not
## folded (#251): see _snapshot_floor.

## A player's life as the public events tell it (E25): the client's own words for core/'s life
## states, so no client/ file names a core/ state class (client/CLAUDE.md).
enum Life { ALIVE, DOWNED, DEAD, LEFT }

## An item's holder when nobody holds it (no peer id is 0).
const NO_HOLDER := 0


## One player of the roster.
class Member:
	extends RefCounted
	var name := ""
	var ready := false


## One item as the events describe it.
class Item:
	extends RefCounted
	var kind: StringName
	var position := Vector3.ZERO
	## The peer carrying it; NO_HOLDER when it rests somewhere.
	var holder := NO_HOLDER
	## Carried on the holder's belt rather than in its hand (M4-5, E29).
	var belted := false
	## A package's circle and colour; -1 and white for any other item.
	var station := -1
	var colour := Color.WHITE
	var delivered := false
	## In flight (§7.1.16): from its ItemThrown until its ItemPlaced (cause `thrown`) or
	## PackageDelivered. The launch exactly as the event carries it, so a client draws the arc
	## from the same vectors the host's flight uses (37e): the thrower, the origin, velocity and
	## gravity, and the launch tick L (the point at host tick t is the arc's at t - L). While it
	## flies, `position` is the origin, a stand-in: the item rests nowhere (rests() is false).
	var flying := false
	var thrower := NO_HOLDER
	var flight_origin := Vector3.ZERO
	var flight_velocity := Vector3.ZERO
	var flight_gravity := Vector3.ZERO
	var flight_tick := 0

	## Lies in the world at `position`: nobody carries it and it is not in flight (a delivered
	## package rests in its circle).
	func rests() -> bool:
		return holder == NO_HOLDER and not flying


## One task as its TaskState tells it (E30): the task screen's row.
class Task:
	extends RefCounted
	## The task type's id: the client's own copy of the mode gives its name and description.
	var type: StringName
	var done := 0
	var total := 0


## One station: a delivery circle or a zone (#36).
class Station:
	extends RefCounted
	var kind: StringName
	var colour := Color.WHITE
	var position := Vector3.ZERO
	## Done: a package was delivered to it (§4.2 PackageDelivered), or, for a zone, its last
	## ZoneProgress has `ticks` at `needed` (ZE8 of the zone task ADR).
	var done := false
	## A zone's progress as its last ZoneProgress told it (ZE4, ZE8): its ticks so far, the ticks
	## it needs, whether it counts, and the host tick this held at (-1 before the first). The client
	## predicts nothing: ZoneViews extrapolates from these alone.
	var ticks := 0
	var needed := 0
	var counting := false
	var progress_tick := -1


## Its own peer id once welcomed; 0 before.
var own_peer := 0
## Its movement epoch: Welcome's, then each Correction's.
var epoch := 0
var phase: StringName = &""
## The countdown's or the match clock's end as a host tick; -1 when none runs.
var end_tick := -1
var roster: Dictionary[int, Member] = {}
## Where each player was last placed: Welcome's spot and positions, PlayerJoined, PlayersPlaced.
var spots: Dictionary[int, Vector3] = {}
var settings: Dictionary[StringName, int] = {}
var id_sets: Dictionary[StringName, PackedStringArray] = {}
var map := ""
## What holds all_ready back, as the last SettingsChanged listed it.
var shortfalls := PackedStringArray()
## The last LoadMatch's id; -1 before the first.
var match_id := -1
## Peers whose load the host confirmed for this match.
var loaded: Dictionary[int, bool] = {}
var start_tick := -1
var role: StringName = &""
## Role -> its players, for a role whose players know each other.
var teammates: Dictionary[StringName, PackedInt32Array] = {}
var items: Dictionary[int, Item] = {}
var stations: Dictionary[int, Station] = {}
## Peer -> where its body lies: the dead of this match (Died); a respawn or a leave removes it
## (E26).
var bodies: Dictionary[int, Vector3] = {}
## Peer -> its life state, for the players who are not living (E25): KnockedDown makes one
## downed, Died dead, PlayerLeft left; Respawned and Revived make it living again. Absent means
## living.
var lives: Dictionary[int, Life] = {}
## Downed peer -> the peer raising it, while a raise runs (M4-4): RaiseStarted adds one;
## RaiseStopped, Revived, the leave of either and a new match remove it. The client times the
## raise's progress itself, from RaiseStarted and the mode's raise time.
var raises: Dictionary[int, int] = {}
## Task id -> its public state (TaskState, E30), for the task screen.
var tasks: Dictionary[int, Task] = {}
var tasks_done := 0
var tasks_total := 0
## The winning side once the match ended; empty before.
var winner: StringName = &""
## The newest snapshot's tick and avatars (peer -> {position, velocity, facing, downed,
## invulnerable, held_item, belt_item}).
var snapshot_tick := -1
var avatars: Dictionary = {}
## Its own SelfStatus (and Damaged's health); -1 until the first arrives.
var health := -1
var stamina := -1
var sprint_available := false
## Goes up at every fold after which the own player may not have been heard for a while: the
## phase changed, or its own life left living. VoiceSender compares it between its steps, so a
## knockdown and a revive (or Round, End, Lobby) folded between two of them still mark what waits
## in the microphone as recorded unheard (#241).
var silencings := 0
## The estimated host tick now, for _snapshot_floor: AvatarViews sets its host_tick(). A client that
## draws nothing (a bot) has none and floors at the newest snapshot held.
var host_tick_now := Callable()

var _mode: GameMode
## Snapshots of this host tick or older are not folded: clear_match() sets it to the host tick
## estimated at the change, or to the newest snapshot held if that is higher. The newest held
## alone is not enough: the late snapshot is usually newer than every one held (tick T-1 delayed
## past the PhaseChanged of tick T, #251). The host's tick runs on across matches, so a floor never
## holds back a later match's snapshots. -1 before the first clear.
var _snapshot_floor := -1


func _init(mode: GameMode) -> void:
	_mode = mode


## Whether `peer` is living as far as this client knows: never knocked down or dead in this match.
func is_alive(peer: int) -> bool:
	return life_of(peer) == Life.ALIVE


## The life state of `peer` as this client knows it from the public events (E25): ALIVE unless a
## KnockedDown, a Died or a PlayerLeft of this match said otherwise and no Respawned undid it.
func life_of(peer: int) -> Life:
	return lives.get(peer, Life.ALIVE)


## The peer raising `peer` (a downed player) as far as this client knows, or 0 when nobody is.
func raiser_of(peer: int) -> int:
	return raises.get(peer, 0)


## The downed player `raiser` is raising, or 0 when it raises nobody.
func raised_by(raiser: int) -> int:
	for target: int in raises:
		if raises[target] == raiser:
			return target
	return 0


## The item `peer` holds in its hand as the events tell it (ItemPickedUp, Swapped, ItemPlaced), or
## -1. The own player's slots come only from these: its avatar is never sent to it.
func hand_item(peer: int) -> int:
	return _carried(peer, false)


## The item `peer` carries on its belt as the events tell it, or -1.
func belt_item(peer: int) -> int:
	return _carried(peer, true)


## Whether the newest snapshot shows `peer` invulnerable (the avatar's flag, M4-3): strikes skip
## it after a respawn or a revive. The own player's never arrives (its avatar is not sent).
func is_invulnerable(peer: int) -> bool:
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("invulnerable", false)


## The client's own copy of the current phase, or null.
func phase_spec() -> PhaseSpec:
	return _mode.find_phase(phase)


## Folds one decoded event into the model.
func fold(event_name: StringName, fields: Dictionary) -> void:
	var phase_before := phase
	var living_before := life_of(own_peer) == Life.ALIVE
	_fold_event(event_name, fields)
	if phase != phase_before or (living_before and life_of(own_peer) != Life.ALIVE):
		silencings += 1


func _fold_event(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"Welcome":
			_welcome(fields)
		&"PlayerJoined":
			var member := Member.new()
			member.name = fields["name"]
			roster[fields["peer"] as int] = member
			spots[fields["peer"] as int] = fields["spot"]
		&"PlayerLeft":
			var peer: int = fields["peer"]
			roster.erase(peer)
			spots.erase(peer)
			avatars.erase(peer)
			_fold_leave(peer)
		&"ReadyChanged":
			var member: Member = roster.get(fields["peer"] as int)
			if member != null:
				member.ready = fields["ready"]
		&"SettingsChanged":
			settings = fields["settings"]
			id_sets = fields["id_sets"]
			map = fields["map"]
			shortfalls = fields["shortfalls"]
		&"PhaseChanged":
			_enter(fields["phase"] as StringName)
			end_tick = fields["end_tick"]
		&"PlayersPlaced":
			var placed: Dictionary[int, Vector3] = fields["spots"]
			spots.merge(placed, true)
		&"LoadMatch":
			clear_match()
			match_id = fields["match_id"]
			map = fields["map"]
			settings = fields["settings"]
		&"PlayerLoaded":
			loaded[fields["peer"] as int] = true
		&"RoundStarted":
			start_tick = fields["start_tick"]
		&"RoleAssigned":
			role = fields["role"]
		&"Teammates":
			teammates[fields["role"] as StringName] = fields["peers"]
		_:
			_fold_match_event(event_name, fields)


## Folds one decoded snapshot: its avatars replace the older ones. The model keeps a copy: the
## DecodedView records the same Dictionary, and a PlayerLeft must not change what was decoded. One
## at or below _snapshot_floor is of a match the model forgot and is not folded.
func fold_snapshot(fields: Dictionary) -> void:
	var tick: int = fields["tick"]
	if tick > snapshot_tick and tick > _snapshot_floor:
		snapshot_tick = tick
		avatars = (fields["avatars"] as Dictionary).duplicate(true)


## Forgets a match's facts: on LoadMatch and on entering the lobby. Raises _snapshot_floor.
func clear_match() -> void:
	_snapshot_floor = maxi(_snapshot_floor, snapshot_tick)
	if host_tick_now.is_valid():
		_snapshot_floor = maxi(_snapshot_floor, host_tick_now.call() as int)
	loaded.clear()
	start_tick = -1
	role = &""
	teammates.clear()
	items.clear()
	tasks.clear()
	stations.clear()
	bodies.clear()
	lives.clear()
	raises.clear()
	tasks_done = 0
	tasks_total = 0
	winner = &""
	snapshot_tick = -1
	avatars = {}


func _welcome(fields: Dictionary) -> void:
	own_peer = fields["peer"]
	epoch = fields["epoch"]
	roster.clear()
	for entry: Dictionary in fields["roster"]:
		var member := Member.new()
		member.name = entry["name"]
		member.ready = entry["ready"]
		roster[entry["peer"] as int] = member
	settings = fields["settings"]
	map = fields["map"]
	phase = fields["phase"]
	var positions: Dictionary[int, Vector3] = fields["positions"]
	spots = positions.duplicate()
	spots[own_peer] = fields["spot"]


func _fold_match_event(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"StationPlaced":
			var station := Station.new()
			station.kind = fields["kind"]
			station.colour = fields["colour"]
			station.position = fields["position"]
			stations[fields["station"] as int] = station
		&"ItemSpawned":
			var item := Item.new()
			item.kind = fields["kind"]
			item.position = fields["position"]
			item.station = fields.get("station", -1)
			item.colour = fields.get("colour", Color.WHITE)
			items[fields["item"] as int] = item
		&"ItemPickedUp", &"Swapped":
			_fold_slots(event_name, fields)
		&"ItemPlaced":
			var item: Item = items.get(fields["item"] as int)
			if item != null:
				item.holder = NO_HOLDER
				item.belted = false
				item.flying = false
				item.position = fields["position"]
		&"ItemThrown":
			_fold_throw(fields)
		&"PackageDelivered":
			var item: Item = items.get(fields["item"] as int)
			if item != null:
				item.holder = NO_HOLDER
				item.belted = false
				item.flying = false
				item.delivered = true
			var station: Station = stations.get(fields["station"] as int)
			if station != null:
				station.done = true
		&"ZoneProgress":
			var zone: Station = stations.get(fields["station"] as int)
			if zone != null:
				zone.ticks = fields["ticks"]
				zone.needed = fields["needed"]
				zone.counting = fields["counting"]
				zone.progress_tick = fields["tick"]
				zone.done = zone.needed > 0 and zone.ticks >= zone.needed
		&"TaskProgress":
			tasks_done = fields["done"]
			tasks_total = fields["total"]
		&"TaskState":
			var task := Task.new()
			task.type = fields["type"]
			task.done = fields["done"]
			task.total = fields["total"]
			tasks[fields["task"] as int] = task
		&"Damaged":
			health = fields["health"]
		&"SelfStatus":
			health = fields["health"]
			stamina = fields["stamina"]
			sprint_available = fields["sprint_available"]
		&"KnockedDown", &"Died", &"Respawned":
			_fold_life(event_name, fields)
		&"RaiseStarted", &"RaiseStopped", &"Revived":
			_fold_raise(event_name, fields)
		&"Correction":
			epoch = fields["epoch"]
		&"MatchEnded":
			winner = fields["side"]


## A pickup puts the item in the picker's hand and moves `belted`, when it names one, to its belt
## (E29); a hand item that did not fit the belt follows as ItemPlaced. A swap exchanges the
## swapper's hand and belt items, either of which may be empty.
func _fold_slots(event_name: StringName, fields: Dictionary) -> void:
	var peer: int = fields["peer"]
	if event_name == &"Swapped":
		for item: Item in items.values():
			if item.holder == peer:
				item.belted = not item.belted
		return
	var picked: Item = items.get(fields["item"] as int)
	if picked != null:
		picked.holder = peer
		picked.belted = false
	var belted: Item = items.get(fields.get("belted", -1) as int)
	if belted != null:
		belted.holder = peer
		belted.belted = true


## A throw (§7.1.16): the item leaves its thrower's hand and flies, its launch kept exactly as
## sent, until its ItemPlaced or PackageDelivered ends the flight. A phase change ends no flight
## here: the host pauses one in a phase without FlightTicks, and hiding it then is the view's (37e).
func _fold_throw(fields: Dictionary) -> void:
	var item: Item = items.get(fields["item"] as int)
	if item == null:
		return
	item.holder = NO_HOLDER
	item.belted = false
	item.flying = true
	item.thrower = fields["peer"]
	item.flight_origin = fields["origin"]
	item.flight_velocity = fields["velocity"]
	item.flight_gravity = fields["gravity"]
	item.flight_tick = fields["tick"]
	item.position = item.flight_origin


## The item `peer` carries in the hand (`on_belt` false) or on the belt, or -1.
func _carried(peer: int, on_belt: bool) -> int:
	for id: int in items:
		var item := items[id]
		if item.holder == peer and item.belted == on_belt:
			return id
	return -1


## A knockdown makes its player downed; a death makes it dead, with its body; a respawn makes it
## living again and removes its body (E25, E26).
func _fold_life(event_name: StringName, fields: Dictionary) -> void:
	var peer: int = fields["peer"]
	if event_name == &"KnockedDown":
		lives[peer] = Life.DOWNED
	elif event_name == &"Respawned":
		lives.erase(peer)
		bodies.erase(peer)
	else:
		lives[peer] = Life.DEAD
		bodies[peer] = fields["position"]


## A raise starting records its raiser; one stopping forgets it; a revive also makes the raised
## player living again (M4-4).
func _fold_raise(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"RaiseStarted":
		raises[fields["target"] as int] = fields["raiser"] as int
	elif event_name == &"RaiseStopped":
		raises.erase(fields["target"] as int)
	else:
		var peer: int = fields["peer"]
		raises.erase(peer)
		lives.erase(peer)


## A player who left mid-match leaves no body (E26, the engineer's answer 1 on PR #133).
func _fold_leave(peer: int) -> void:
	bodies.erase(peer)
	lives[peer] = Life.LEFT
	# The host stops a raise of or by a leaver first (RaiseStopped); a lost order changes nothing.
	raises.erase(peer)
	var raised := raised_by(peer)
	if raised != 0:
		raises.erase(raised)


## Enters `next`: a match's facts are cleared when it plays in the lobby and the phase before did
## not (End -> Lobby), so a lobby holds no items or bodies of the match before.
func _enter(next: StringName) -> void:
	var before := phase_spec()
	phase = next
	var after := phase_spec()
	var in_lobby := after != null and after.level == PhaseSpec.Level.LOBBY
	if in_lobby and (before == null or before.level != PhaseSpec.Level.LOBBY):
		clear_match()
