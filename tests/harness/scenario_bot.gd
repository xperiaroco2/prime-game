class_name ScenarioBot
extends RefCounted
## One bot of the core scenario runner (ARCHITECTURE §9.7): its script's progress and everything
## its client knows, built only from the events and snapshots its peer received (`view_of`). A
## target the bot cannot know from them fails the scenario, so a scenario also proves that its
## mechanic is playable with what a player is told.

enum Where { GROUND, HAND, LOCKED }

var number: int
var peer: int
var steps: Array[ScenarioStep] = []
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
## Every event it received, in order.
var events: Array[MatchEvent] = []

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
## The LoadMatch that the bot's LoadAck step is to answer, or null.
var unanswered_load: LoadMatchEvent
## Item id -> {kind, position, where, station}, from ItemSpawned, ItemPickedUp, ItemPlaced and
## PackageDelivered.
var items: Dictionary[int, Dictionary] = {}
## Station id -> position, from StationPlaced.
var stations: Dictionary[int, Vector3] = {}
## Peer -> where the bot last saw that player: PlayerJoined, Welcome, PlayersPlaced, snapshots.
var seen: Dictionary[int, Vector3] = {}

var _next_seq := 1
var _client_tick := 0
## This batch placed the bot (PlayersPlaced naming it, or its own Died): a Correction is expected.
var _placed_now := false


func _init(bot_number: int, peer_id: int, script_steps: Array[ScenarioStep]) -> void:
	number = bot_number
	peer = peer_id
	steps = script_steps


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


## A new batch of events (one step of the match) begins.
func begin_batch() -> void:
	_placed_now = false


## Takes one event its peer received and learns from it. Returns a failure, or "".
func receive(event: MatchEvent) -> String:
	events.append(event)
	if event is WelcomeEvent:
		var welcome := event as WelcomeEvent
		joined = true
		epoch = welcome.epoch
		jumps = 0
		position = welcome.spot
		phase = welcome.phase
		for other: int in welcome.positions:
			seen[other] = welcome.positions[other]
	elif event is PlayerJoinedEvent:
		var joiner := event as PlayerJoinedEvent
		seen[joiner.peer] = joiner.spot
	elif event is PlayersPlacedEvent:
		var placed := event as PlayersPlacedEvent
		for other: int in placed.spots:
			seen[other] = placed.spots[other]
		if placed.spots.has(peer):
			_placed_now = true
	elif event is CorrectionEvent:
		var correction := event as CorrectionEvent
		if not _placed_now:
			return (
				"a Correction outside a placement (epoch %d, at %s): an honest bot is never corrected"
				% [correction.epoch, correction.position]
			)
		epoch = correction.epoch
		jumps = 0
		position = correction.position
	elif event is DiedEvent:
		var died := event as DiedEvent
		seen[died.peer] = died.position
		if died.peer == peer:
			ghost = true
			_placed_now = true
	else:
		_learn(event)
	return ""


## Takes its snapshot of a tick: where it sees the other players.
func see(snapshot: Dictionary) -> void:
	var avatars: Dictionary = snapshot.get("avatars", {})
	for other: int in avatars:
		var avatar: Dictionary = avatars[other]
		seen[other] = avatar["position"]


## The reason of the Rejected answering `seq` since the current step started, or "".
func rejection_of(seq: int) -> StringName:
	for i in range(step_cursor, events.size()):
		var rejected := events[i] as RejectedEvent
		if rejected != null and rejected.seq == seq:
			return rejected.reason
	return &""


## The first event since `from` that `matches` (a Callable taking a MatchEvent) accepts, or null.
func find_since(from: int, matches: Callable) -> MatchEvent:
	for i in range(from, events.size()):
		if matches.call(events[i]):
			return events[i]
	return null


## Where `target` is, as the bot knows it, or Vector3.INF when it cannot know.
func where_is(target: ScenarioTarget) -> Vector3:
	var found := Vector3.INF
	match target.kind:
		ScenarioTarget.Kind.POINT:
			found = target.point
		ScenarioTarget.Kind.BOT:
			var other := ScenarioRunner.peer_of(target.bot)
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
		names.append(events[i].event_name())
	return names


func _learn(event: MatchEvent) -> void:
	if event is RoleAssignedEvent:
		role = (event as RoleAssignedEvent).role
	elif event is LoadMatchEvent:
		match_id = (event as LoadMatchEvent).match_id
		items.clear()
		stations.clear()
		held = -1
		ghost = false
		if current_step() is StepLoadAck:
			unanswered_load = event as LoadMatchEvent
		else:
			load_ack_due = true
	elif event is PhaseChangedEvent:
		phase = (event as PhaseChangedEvent).phase
	elif event is StationPlacedEvent:
		var station := event as StationPlacedEvent
		stations[station.station] = station.position
	elif event is ItemSpawnedEvent:
		var spawned := event as ItemSpawnedEvent
		items[spawned.item] = {
			"kind": spawned.kind,
			"position": spawned.position,
			"where": Where.GROUND,
			"station": spawned.station,
		}
	elif event is ItemPickedUpEvent:
		var picked := event as ItemPickedUpEvent
		if items.has(picked.item):
			items[picked.item]["where"] = Where.HAND
		if picked.peer == peer:
			held = picked.item
	elif event is ItemPlacedEvent:
		var placed := event as ItemPlacedEvent
		if items.has(placed.item):
			items[placed.item]["where"] = Where.GROUND
			items[placed.item]["position"] = placed.position
		if held == placed.item:
			held = -1
	elif event is PackageDeliveredEvent:
		var delivered := event as PackageDeliveredEvent
		if items.has(delivered.item):
			items[delivered.item]["where"] = Where.LOCKED
	elif event is SelfStatusEvent:
		sprint_available = (event as SelfStatusEvent).sprint_available


func _ids_of_kind(kind: StringName) -> Array[int]:
	var ids: Array[int] = []
	for id: int in items:
		if items[id]["kind"] == kind:
			ids.append(id)
	ids.sort()
	return ids


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
