class_name ScenarioInvariants
extends RefCounted
## The §5 invariants over every bot's stream (ARCHITECTURE §5, §9.7), written independently of the
## events' declared audiences: each check reads the match state's truth (roles, life states, who
## is present), never an event's audience(), so a wrong declaration (Teammates declared to
## everyone, say) fails here even though view_of agrees with it.
## - For each match, a crew member knows one role, its own, and a player of a role that knows its
##   teammates knows only that role's players; every role it learns is the truth.
## - Nobody gets another player's health, stamina or damage (Damaged, SelfStatus).
## - Every present player receives the same task events (StationPlaced, ItemSpawned,
##   PackageDelivered, TaskProgress).
## - No event holds the session seed or a match seed.
## - Per tick, a living peer's snapshot holds no ghost, and it hears no ghost.
## - The scenario's `never` events reach nobody they name.

const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced", &"ItemSpawned", &"PackageDelivered", &"TaskProgress"
]
const PRIVATE_NUMBERS: Array[StringName] = [&"Damaged", &"SelfStatus"]

var _game: Match
var _scenario: BotScenario
## Peer -> {peer: role} learned in the current match.
var _known_roles: Dictionary[int, Dictionary] = {}
var _seeds: Array[int] = []


func _init(game: Match, scenario: BotScenario) -> void:
	_game = game
	_scenario = scenario
	_seeds.append(scenario.session_seed)


## The broken invariants of one emitted event, checked right after the step that emitted it.
func check_event(emitted: EmittedEvent) -> PackedStringArray:
	var found := PackedStringArray()
	var event := emitted.event
	var name := event.event_name()
	var state := _game.state
	if event is LoadMatchEvent:
		_known_roles.clear()
		var seed_now := state.rng.match_seed()
		if not _seeds.has(seed_now):
			_seeds.append(seed_now)
	if event is RoleAssignedEvent:
		var assigned := event as RoleAssignedEvent
		for peer: int in emitted.recipients:
			_learn_role(peer, assigned.peer, assigned.role, found)
	elif event is TeammatesEvent:
		var teammates := event as TeammatesEvent
		for peer: int in emitted.recipients:
			for other: int in teammates.peers:
				_learn_role(peer, other, teammates.role, found)
	if PRIVATE_NUMBERS.has(name):
		var owner: int = event.get("peer")
		for peer: int in emitted.recipients:
			if peer != owner:
				found.append("peer %d received %s of peer %d" % [peer, name, owner])
	if TASK_EVENTS.has(name):
		var present := PackedInt32Array(state.present_peers())
		if emitted.recipients != present:
			found.append(
				"%s reached %s, not every present player %s" % [name, emitted.recipients, present]
			)
	for seed_value: int in _seeds:
		if _holds_int(event.to_dict(), seed_value):
			found.append("%s holds a seed" % name)
	for never: NeverEvent in _scenario.never:
		if not ScenarioRunner.matches(event, never.event, never.fields):
			continue
		for peer: int in emitted.recipients:
			if never.bot == 0 or ScenarioRunner.peer_of(never.bot) == peer:
				found.append("peer %d received %s, which the scenario says never" % [peer, name])
	return found


## The broken invariants of one tick's snapshots and voice routing.
func check_tick() -> PackedStringArray:
	var found := PackedStringArray()
	var state := _game.state
	for peer: int in state.present_peers():
		if state.players[peer].life != PlayerState.Life.ALIVE:
			continue
		var avatars: Dictionary = _game.snapshot_for(peer).get("avatars", {})
		for other: int in avatars:
			if state.is_present(other) and state.players[other].life == PlayerState.Life.GHOST:
				found.append("living peer %d sees ghost %d in its snapshot" % [peer, other])
		for speaker: int in _game.speakers_for(peer):
			if state.is_present(speaker) and state.players[speaker].life == PlayerState.Life.GHOST:
				found.append("living peer %d hears ghost %d" % [peer, speaker])
	return found


func _learn_role(peer: int, about: int, role: StringName, found: PackedStringArray) -> void:
	var state := _game.state
	if not _known_roles.has(peer):
		_known_roles[peer] = {}
	_known_roles[peer][about] = role
	var truth: StringName = state.players[about].role if state.players.has(about) else &""
	if role != truth:
		found.append("peer %d learned that %d is %s, but it is %s" % [peer, about, role, truth])
	if about == peer:
		return
	var own: StringName = state.players[peer].role if state.players.has(peer) else &""
	var own_role := _game.mode.find_role(own)
	if own_role == null or not own_role.knows_teammates or truth != own:
		found.append("peer %d (%s) learned the role of peer %d (%s)" % [peer, own, about, truth])


static func _holds_int(value: Variant, number: int) -> bool:
	if value is int:
		return value == number
	if value is Dictionary:
		var fields: Dictionary = value
		for key: Variant in fields:
			if _holds_int(key, number) or _holds_int(fields[key], number):
				return true
	elif value is Array:
		for element: Variant in value as Array:
			if _holds_int(element, number):
				return true
	elif value is PackedInt32Array or value is PackedInt64Array:
		for element: int in value:
			if element == number:
				return true
	return false
