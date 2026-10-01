class_name ClientModel
extends RefCounted
## What one client knows now (ARCHITECTURE §4.6), folded from the events and snapshots it decoded:
## its peer id and epoch, the phase, the roster, the settings, the items, stations and bodies, the
## avatars of the newest snapshot and its own SelfStatus. Built only from what the host sent this
## client, never from core/ state (invariant 2). The game mode is the client's own copy, read for
## where each phase plays.
##
## A match's facts (items, stations, bodies, role, tasks, avatars and the like) are cleared on
## LoadMatch and on entering the lobby: a new level holds none of the old ones.

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
	## The peer holding it; NO_HOLDER when it rests somewhere.
	var holder := NO_HOLDER
	## A package's circle and colour; -1 and white for any other item.
	var station := -1
	var colour := Color.WHITE
	var delivered := false


## One station (in the MVP a delivery circle).
class Station:
	extends RefCounted
	var kind: StringName
	var colour := Color.WHITE
	var position := Vector3.ZERO
	## A package was delivered to it (§4.2 PackageDelivered: now shown as done).
	var done := false


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
## Peer -> where its body lies: the dead of this match.
var bodies: Dictionary[int, Vector3] = {}
var tasks_done := 0
var tasks_total := 0
## The winning side once the match ended; empty before.
var winner: StringName = &""
## The newest snapshot's tick and avatars (peer -> {position, velocity, facing, ghost, held_item}).
var snapshot_tick := -1
var avatars: Dictionary = {}
## Its own SelfStatus (and Damaged's health); -1 until the first arrives.
var health := -1
var stamina := -1
var sprint_available := false

var _mode: GameMode


func _init(mode: GameMode) -> void:
	_mode = mode


## Whether `peer` is alive as far as this client knows: it has no body.
func is_alive(peer: int) -> bool:
	return not bodies.has(peer)


## The client's own copy of the current phase, or null.
func phase_spec() -> PhaseSpec:
	return _mode.find_phase(phase)


## Folds one decoded event into the model.
func fold(event_name: StringName, fields: Dictionary) -> void:
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
## DecodedView records the same Dictionary, and a PlayerLeft must not change what was decoded.
func fold_snapshot(fields: Dictionary) -> void:
	var tick: int = fields["tick"]
	if tick > snapshot_tick:
		snapshot_tick = tick
		avatars = (fields["avatars"] as Dictionary).duplicate(true)


## Forgets a match's facts: on LoadMatch and on entering the lobby.
func clear_match() -> void:
	loaded.clear()
	start_tick = -1
	role = &""
	teammates.clear()
	items.clear()
	stations.clear()
	bodies.clear()
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
		&"ItemPickedUp":
			var item: Item = items.get(fields["item"] as int)
			if item != null:
				item.holder = fields["peer"]
		&"ItemPlaced":
			var item: Item = items.get(fields["item"] as int)
			if item != null:
				item.holder = NO_HOLDER
				item.position = fields["position"]
		&"PackageDelivered":
			var item: Item = items.get(fields["item"] as int)
			if item != null:
				item.holder = NO_HOLDER
				item.delivered = true
			var station: Station = stations.get(fields["station"] as int)
			if station != null:
				station.done = true
		&"TaskProgress":
			tasks_done = fields["done"]
			tasks_total = fields["total"]
		&"Damaged":
			health = fields["health"]
		&"SelfStatus":
			health = fields["health"]
			stamina = fields["stamina"]
			sprint_available = fields["sprint_available"]
		&"Died":
			bodies[fields["peer"] as int] = fields["position"]
		&"Correction":
			epoch = fields["epoch"]
		&"MatchEnded":
			winner = fields["side"]


## Enters `next`: a match's facts are cleared when it plays in the lobby and the phase before did
## not (End -> Lobby), so a lobby holds no items or bodies of the match before.
func _enter(next: StringName) -> void:
	var before := phase_spec()
	phase = next
	var after := phase_spec()
	var in_lobby := after != null and after.level == PhaseSpec.Level.LOBBY
	if in_lobby and (before == null or before.level != PhaseSpec.Level.LOBBY):
		clear_match()
