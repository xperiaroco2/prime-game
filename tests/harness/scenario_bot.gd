class_name ScenarioBot
extends RefCounted
## One bot of a scenario runner (ARCHITECTURE §9.7, §4.6): its script's progress and everything its
## client knows, learned only from the events and snapshots it received, as (name, fields): the
## core runner gives each event's to_dict(), a network bot its ClientSession's decoded messages. A
## target the bot cannot know from them fails the scenario, so a scenario also proves that its
## mechanic is playable with what a player is told.

enum Where { GROUND, HAND, LOCKED }

## The events for one peer whose fields name no peer (§4.6): whoever receives one is its subject,
## so a step's `peer` field matches the receiving bot.
const OWN_EVENTS: Array[StringName] = [
	&"RoleAssigned", &"Damaged", &"SelfStatus", &"Correction", &"Rejected"
]

var number: int
## Its peer id; 0 until it is known (a network bot learns it when it connects).
var peer: int
var steps: Array[ScenarioStep] = []
## The runner's map from bot number to peer id, for `bot(i)` targets.
var peers: ScenarioPeers
var step_index := 0
## The tick the current step started, or -1 before it starts.
var step_started := -1
## The index in `events` where the current step started, and where the previous one did.
var step_cursor := 0
var previous_cursor := 0
## The sequence number of the intent the current step sent, or -1.
var sent_seq := -1
## The item the current step names (PickUp) or held when it sent (PutDown), or -1.
var sent_item := -1
var connected := false
## Its Welcome arrived.
var joined := false
## It left, or the host disconnected it: it acts and receives no more.
var gone := false
## Every event it received, in order: name and fields (the event's to_dict()).
var events: Array[WireMessage] = []

## What its client knows of itself.
var epoch := 0
## Its jumps since it adopted `epoch` (MoveClaim's `jumps`, §4.3): 0 again on every new epoch.
var jumps := 0
var position := Vector3.ZERO
var ghost := false
var role: StringName
var held := -1
var sprint_available := true
var phase: StringName
var match_id := 0
## A LoadMatch arrived that no LoadAck step answers: the default is to acknowledge at once.
var load_ack_due := false
## The match id of the last LoadMatch acknowledged at once (no LoadAck step was current), or -1.
var auto_acked_match := -1
## The match id of the LoadMatch that the bot's LoadAck step is to answer, or -1.
var unanswered_load := -1
## Item id -> {kind, position, where, station}, from ItemSpawned, ItemPickedUp, ItemPlaced and
## PackageDelivered.
var items: Dictionary[int, Dictionary] = {}
## Station id -> position, from StationPlaced.
var stations: Dictionary[int, Vector3] = {}
## Peer -> where the bot last saw that player: PlayerJoined, Welcome, PlayersPlaced, snapshots.
var seen: Dictionary[int, Vector3] = {}

var _next_seq := 1
var _client_tick := 0
## A placement of the bot (PlayersPlaced naming it, or its own Died) awaits its Correction: core/
## emits exactly one after each, so a network poll that splits the two still expects it, and any
## other Correction fails.
var _correction_due := false


func _init(
	bot_number: int,
	peer_id: int,
	script_steps: Array[ScenarioStep],
	bot_peers: ScenarioPeers = null
) -> void:
	number = bot_number
	peer = peer_id
	steps = script_steps
	peers = bot_peers if bot_peers != null else ScenarioPeers.new()


## The step it is on, or null when its script is done.
func current_step() -> ScenarioStep:
	return steps[step_index] if step_index < steps.size() else null


func finished() -> bool:
	return gone or current_step() == null


## Whether its script joins it later (a Join step) instead of at the start.
func joins_late() -> bool:
	for step: ScenarioStep in steps:
		if step is StepJoin:
			return true
	return false


func start_step(at_tick: int) -> void:
	step_started = at_tick
	previous_cursor = step_cursor
	step_cursor = events.size()
	sent_seq = -1
	sent_item = -1


func finish_step() -> void:
	step_index += 1
	step_started = -1


func next_seq() -> int:
	_next_seq += 1
	return _next_seq - 1


func next_client_tick() -> int:
	_client_tick += 1
	return _client_tick


## Takes one event its peer received, as (name, fields), and learns from it. Returns a failure, or
## "".
func receive(event_name: StringName, fields: Dictionary) -> String:
	events.append(WireMessage.new(event_name, fields))
	match event_name:
		&"Welcome":
			joined = true
			peer = fields["peer"] as int
			epoch = fields["epoch"] as int
			jumps = 0
			position = fields["spot"] as Vector3
			phase = StringName(str(fields["phase"]))
			var positions: Dictionary = fields["positions"]
			for other: int in positions:
				seen[other] = positions[other]
		&"PlayerJoined":
			seen[fields["peer"] as int] = fields["spot"] as Vector3
		&"PlayersPlaced":
			var spots: Dictionary = fields["spots"]
			for other: int in spots:
				seen[other] = spots[other]
			if spots.has(peer):
				_correction_due = true
		&"Correction":
			if not _correction_due:
				return (
					"a Correction outside a placement (epoch %d, at %s): an honest bot is never corrected"
					% [fields["epoch"], fields["position"]]
				)
			_correction_due = false
			epoch = fields["epoch"] as int
			jumps = 0
			position = fields["position"] as Vector3
		&"Died":
			var died := fields["peer"] as int
			seen[died] = fields["position"] as Vector3
			if died == peer:
				ghost = true
				_correction_due = true
		_:
			_learn(event_name, fields)
	return ""


## Takes the avatars of a snapshot: where it sees the other players.
func see(avatars: Dictionary) -> void:
	for other: int in avatars:
		var avatar: Dictionary = avatars[other]
		seen[other] = avatar["position"]


## The reason of the Rejected answering `seq` since the current step started, or "".
func rejection_of(seq: int) -> StringName:
	for i in range(step_cursor, events.size()):
		var event := events[i]
		if event.name == &"Rejected" and event.fields["seq"] == seq:
			return StringName(str(event.fields["reason"]))
	return &""


## The first event since `from` that `matches` (a Callable taking a WireMessage) accepts, or null.
func find_since(from: int, matches: Callable) -> WireMessage:
	for i in range(from, events.size()):
		if matches.call(events[i]):
			return events[i]
	return null


## The value of `field` in an event this bot received: the payload's, else, for `peer` of an event
## for one peer that names none (OWN_EVENTS), the bot's own peer id; null when it has none.
func field_of(event: WireMessage, field: String) -> Variant:
	if event.fields.has(field):
		return event.fields[field]
	if field == "peer" and OWN_EVENTS.has(event.name):
		return peer
	return null


## Where `target` is, as the bot knows it, or Vector3.INF when it cannot know.
func where_is(target: ScenarioTarget) -> Vector3:
	var found := Vector3.INF
	match target.kind:
		ScenarioTarget.Kind.POINT:
			found = target.point
		ScenarioTarget.Kind.BOT:
			var other := peers.peer_of(target.bot)
			if other == 0:
				found = Vector3.INF
			else:
				found = position if other == peer else seen.get(other, Vector3.INF)
		ScenarioTarget.Kind.CIRCLE_OF_HELD:
			if held >= 0 and items.has(held):
				var station: int = items[held]["station"]
				found = stations.get(station, Vector3.INF)
		_:
			var item := item_of(target)
			if item >= 0:
				found = items[item]["position"]
	return found


## The item `target` names, as the bot knows it, or -1.
func item_of(target: ScenarioTarget) -> int:
	if target.kind == ScenarioTarget.Kind.PACKAGE:
		var ids := _ids_of_kind(&"package")
		return ids[target.index - 1] if target.index <= ids.size() else -1
	if target.kind == ScenarioTarget.Kind.NEAREST:
		var best := -1
		var best_distance := INF
		for id: int in _ids_of_kind(target.item_kind):
			if items[id]["where"] != Where.GROUND:
				continue
			var at: Vector3 = items[id]["position"]
			var distance := _flat(at - position).length()
			if distance < best_distance:
				best = id
				best_distance = distance
		return best
	return -1


## The last events it received, by name, for a failure's report.
func last_events(count: int = 12) -> Array[StringName]:
	var names: Array[StringName] = []
	for i in range(maxi(0, events.size() - count), events.size()):
		names.append(events[i].name)
	return names


func _learn(event_name: StringName, fields: Dictionary) -> void:
	match event_name:
		&"RoleAssigned":
			role = StringName(str(fields["role"]))
		&"LoadMatch":
			match_id = fields["match_id"] as int
			items.clear()
			stations.clear()
			held = -1
			ghost = false
			if current_step() is StepLoadAck:
				unanswered_load = match_id
			else:
				load_ack_due = true
		&"PhaseChanged":
			phase = StringName(str(fields["phase"]))
		&"StationPlaced":
			stations[fields["station"] as int] = fields["position"] as Vector3
		&"ItemSpawned":
			items[fields["item"] as int] = {
				"kind": StringName(str(fields["kind"])),
				"position": fields["position"] as Vector3,
				"where": Where.GROUND,
				"station": fields.get("station", -1) as int,
			}
		&"ItemPickedUp":
			var item := fields["item"] as int
			if items.has(item):
				items[item]["where"] = Where.HAND
			if fields["peer"] as int == peer:
				held = item
		&"ItemPlaced":
			var item := fields["item"] as int
			if items.has(item):
				items[item]["where"] = Where.GROUND
				items[item]["position"] = fields["position"] as Vector3
			if held == item:
				held = -1
		&"PackageDelivered":
			var item := fields["item"] as int
			if items.has(item):
				items[item]["where"] = Where.LOCKED
		&"SelfStatus":
			sprint_available = fields["sprint_available"] as bool


func _ids_of_kind(kind: StringName) -> Array[int]:
	var ids: Array[int] = []
	for id: int in items:
		if items[id]["kind"] == kind:
			ids.append(id)
	ids.sort()
	return ids


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
