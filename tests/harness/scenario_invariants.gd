class_name ScenarioInvariants
extends RefCounted
## The §5 invariants over every bot's stream (ARCHITECTURE §5, §9.7), written independently of the
## events' declared audiences: each check reads the match state's truth (roles, life states, who
## is present), never an event's audience(), so a wrong declaration (Teammates declared to
## everyone, say) fails here even though view_of agrees with it.
## - A crew member learns one role, its own, and a player of a role that knows its teammates
##   learns only that role's players; every role it learns is the truth when it learns it.
## - Nobody gets another player's health, stamina or damage (Damaged, SelfStatus), and no avatar in
##   a snapshot holds a field outside the public ones (AVATAR_FIELDS).
## - A Rejected reaches exactly the peer whose command was just applied.
## - Every present player receives the same task events (StationPlaced, ItemSpawned,
##   PackageDelivered, TaskProgress).
## - No event and no snapshot holds the session seed or a match seed.
## - Per tick, a living peer's snapshot holds no downed player (true until M4-2 makes the downed
##   public). The voice invariant (§6): no peer's speakers include a downed speaker; a downed
##   peer hears only living speakers; a dead peer's speakers are empty.
## - The scenario's `never` events reach nobody they name.

const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced", &"ItemSpawned", &"PackageDelivered", &"TaskProgress"
]
const PRIVATE_NUMBERS: Array[StringName] = [&"Damaged", &"SelfStatus"]
## What anyone may see of another player (§4.2); health and stamina are never avatar fields.
const AVATAR_FIELDS: Array[String] = ["position", "velocity", "facing", "ghost", "held_item"]

## The peer whose command the runner applies now, or 0 outside a command (a tick, the start).
var sender := 0

var _game: Match
var _scenario: BotScenario
var _peers: ScenarioPeers
var _seeds: Array[int] = []


## `peers` is the runner's map from bot number to peer id (the `never` check); the core runner's by
## default.
func _init(game: Match, scenario: BotScenario, peers: ScenarioPeers = null) -> void:
	_game = game
	_scenario = scenario
	_peers = peers if peers != null else ScenarioPeers.core(scenario.bots)
	_seeds.append(scenario.session_seed)


## The broken invariants of one Match call (HostSession's observer, §4.5): its command's sender,
## each event of its slice, and, after a tick (no command), the tick's snapshots and voice routing.
func check_call(command: MatchCommand, slice: Array[EmittedEvent]) -> PackedStringArray:
	var found := PackedStringArray()
	sender = command.peer if command != null else 0
	for emitted: EmittedEvent in slice:
		found.append_array(check_event(emitted))
	if command == null:
		found.append_array(check_tick())
	sender = 0
	return found


## The session seed and every match seed seen so far: no message may hold one.
func seeds() -> Array[int]:
	return _seeds.duplicate()


## The broken invariants of one emitted event, checked right after the step that emitted it.
func check_event(emitted: EmittedEvent) -> PackedStringArray:
	var found := PackedStringArray()
	var event := emitted.event
	var name := event.event_name()
	var state := _game.state
	if event is LoadMatchEvent:
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
	if event is RejectedEvent and emitted.recipients != PackedInt32Array([sender]):
		found.append("Rejected reached %s, not the sender %d" % [emitted.recipients, sender])
	if TASK_EVENTS.has(name):
		var present := PackedInt32Array(state.present_peers())
		if emitted.recipients != present:
			found.append(
				"%s reached %s, not every present player %s" % [name, emitted.recipients, present]
			)
	for seed_value: int in _seeds:
		if holds_int(event.to_dict(), seed_value):
			found.append("%s holds a seed" % name)
	for never: NeverEvent in _scenario.never:
		if not ScenarioPlay.event_matches(event, never.event, never.fields, _peers):
			continue
		for peer: int in emitted.recipients:
			if never.bot == 0 or _peers.peer_of(never.bot) == peer:
				found.append("peer %d received %s, which the scenario says never" % [peer, name])
	return found


## The broken invariants of one tick's snapshots and voice routing.
func check_tick() -> PackedStringArray:
	var found := PackedStringArray()
	var state := _game.state
	for peer: int in state.present_peers():
		var snapshot := _game.snapshot_for(peer)
		var avatars: Dictionary = snapshot.get("avatars", {})
		for seed_value: int in _seeds:
			if holds_int(snapshot, seed_value):
				found.append("peer %d's snapshot holds a seed" % peer)
		for other: int in avatars:
			var avatar: Dictionary = avatars[other]
			for field: Variant in avatar:
				if not AVATAR_FIELDS.has(str(field)):
					found.append("peer %d's snapshot shows %s of peer %d" % [peer, field, other])
		found.append_array(_check_voice(peer))
		if state.players[peer].life != PlayerState.Life.ALIVE:
			continue
		for other: int in avatars:
			if _life_of(other) == PlayerState.Life.DOWNED:
				found.append("living peer %d sees downed %d in its snapshot" % [peer, other])
	return found


## The voice invariant's broken parts for `peer`'s speakers this tick (§6), from the life states
## alone, never the voice rule.
func _check_voice(peer: int) -> PackedStringArray:
	var found := PackedStringArray()
	var speakers := _game.speakers_for(peer)
	var life := _life_of(peer)
	if life == PlayerState.Life.DEAD and not speakers.is_empty():
		found.append("dead peer %d hears %s" % [peer, speakers])
	for speaker: int in speakers:
		var mouth := _life_of(speaker)
		if mouth == PlayerState.Life.DOWNED:
			found.append("peer %d hears downed %d" % [peer, speaker])
		if life == PlayerState.Life.DOWNED and mouth != PlayerState.Life.ALIVE:
			found.append("downed peer %d hears %d, who is not living" % [peer, speaker])
	return found


## The life state of `peer`, LEFT for a peer that is not a player.
func _life_of(peer: int) -> PlayerState.Life:
	var player := _game.state.player(peer)
	return player.life if player != null else PlayerState.Life.LEFT


func _learn_role(peer: int, about: int, role: StringName, found: PackedStringArray) -> void:
	var state := _game.state
	var truth: StringName = state.players[about].role if state.players.has(about) else &""
	if role != truth:
		found.append("peer %d learned that %d is %s, but it is %s" % [peer, about, role, truth])
	if about == peer:
		return
	var own: StringName = state.players[peer].role if state.players.has(peer) else &""
	var own_role := _game.mode.find_role(own)
	if own_role == null or not own_role.knows_teammates or truth != own:
		found.append("peer %d (%s) learned the role of peer %d (%s)" % [peer, own, about, truth])


## Whether `value` holds the whole number `number`, at any depth.
static func holds_int(value: Variant, number: int) -> bool:
	if value is int:
		return value == number
	if value is Dictionary:
		var fields: Dictionary = value
		for key: Variant in fields:
			if holds_int(key, number) or holds_int(fields[key], number):
				return true
	elif value is Array:
		for element: Variant in value as Array:
			if holds_int(element, number):
				return true
	elif value is PackedInt32Array or value is PackedInt64Array:
		for element: int in value:
			if element == number:
				return true
	return false
