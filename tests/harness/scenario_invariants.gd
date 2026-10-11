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
##   PackageDelivered, TaskState, TaskProgress, ZoneProgress).
## - No event and no snapshot holds the session seed or a match seed.
## - Per tick, no peer's snapshot holds a dead player's avatar (the dead have none). The voice
##   invariant (§6): no peer's speakers include a downed or dead speaker; a downed peer hears only
##   living speakers; a dead peer's speakers are empty.
## - The distance invariant (§5, E45): per tick, every speaker a peer hears stands within the
##   phase's hearing radius (VoiceRule.radius_of the mode's rule for the phase), between the two
##   last accepted positions in 3D, compared as VoiceRule.within compares them, so a pair at the
##   edge passes; a phase whose radius is 0 hears nobody. Written apart from the rule's hears and
##   speakers_of: a rule that routes past its own radius fails here though view_of agrees with it.
## - Nothing reaches only the dead: every event a dead peer receives is either for it alone (an
##   event for one peer, FOR_ONE or a one-peer declaration, naming it) or also reaches every living
##   peer present then.
## - No Damaged reaches a player whose invulnerability runs (PlayerState.invulnerable_until, after a
##   respawn or a revive: strikes skip it, M4-3).
## - The scenario's `never` events reach nobody they name.

const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced",
	&"ItemSpawned",
	&"PackageDelivered",
	&"TaskState",
	&"TaskProgress",
	&"ZoneProgress",
]
const PRIVATE_NUMBERS: Array[StringName] = [&"Damaged", &"SelfStatus"]
## What anyone may see of another player (§4.2); health and stamina are never avatar fields.
const AVATAR_FIELDS: Array[String] = [
	"position", "velocity", "facing", "downed", "invulnerable", "held_item", "belt_item"
]

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
	found.append_array(_check_dead_recipients(emitted))
	if event is DamagedEvent:
		for peer: int in emitted.recipients:
			var victim := state.player(peer)
			if victim != null and victim.is_invulnerable(emitted.tick):
				found.append(
					(
						"peer %d received Damaged at tick %d while invulnerable until tick %d"
						% [peer, emitted.tick, victim.invulnerable_until]
					)
				)
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
	var radius := phase_radius(_game)
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
		var speakers := _game.speakers_for(peer)
		found.append_array(_check_voice(peer, speakers))
		found.append_array(_check_distance(peer, speakers, radius))
		for other: int in avatars:
			if _life_of(other) == PlayerState.Life.DEAD:
				found.append("peer %d sees dead %d in its snapshot" % [peer, other])
	return found


## The recipients of `emitted` who are dead now and got it although some living peer present did
## not, unless it is an event for one peer naming that recipient (LeakCheck.for_one).
func _check_dead_recipients(emitted: EmittedEvent) -> PackedStringArray:
	var found := PackedStringArray()
	var event := emitted.event
	var living := PackedInt32Array()
	for peer: int in _game.state.present_peers():
		if _life_of(peer) == PlayerState.Life.ALIVE:
			living.append(peer)
	for peer: int in emitted.recipients:
		if _life_of(peer) != PlayerState.Life.DEAD:
			continue
		if LeakCheck.for_one(event) and event.get("peer") is int and event.get("peer") == peer:
			continue
		for other: int in living:
			if not emitted.recipients.has(other):
				found.append(
					(
						"dead peer %d received %s, which living peer %d did not"
						% [peer, event.event_name(), other]
					)
				)
	return found


## The voice invariant's broken parts for `peer`'s `speakers` this tick (§6), from the life
## states alone, never the voice rule.
func _check_voice(peer: int, speakers: PackedInt32Array) -> PackedStringArray:
	var found := PackedStringArray()
	var life := _life_of(peer)
	if life == PlayerState.Life.DEAD and not speakers.is_empty():
		found.append("dead peer %d hears %s" % [peer, speakers])
	for speaker: int in speakers:
		var mouth := _life_of(speaker)
		if mouth == PlayerState.Life.DOWNED:
			found.append("peer %d hears downed %d" % [peer, speaker])
		if mouth == PlayerState.Life.DEAD:
			found.append("peer %d hears dead %d" % [peer, speaker])
		if life == PlayerState.Life.DOWNED and mouth != PlayerState.Life.ALIVE:
			found.append("downed peer %d hears %d, who is not living" % [peer, speaker])
	return found


## The distance invariant's broken parts for `peer`'s `speakers` this tick, against the phase's
## hearing radius `radius`, from the last accepted positions alone, never the voice rule.
func _check_distance(peer: int, speakers: PackedInt32Array, radius: float) -> PackedStringArray:
	var found := PackedStringArray()
	var state := _game.state
	for speaker: int in speakers:
		var ear := state.player(peer)
		var mouth := state.player(speaker)
		if ear == null or mouth == null:
			found.append("peer %d hears %d, and one of them is not a player" % [peer, speaker])
			continue
		var problem := distance_problem(ear.position, mouth.position, radius)
		if not problem.is_empty():
			found.append("peer %d hears %d %s" % [peer, speaker, problem])
	return found


## The hearing radius of `game`'s current phase: VoiceRule.radius_of the voice rule the mode's data
## names for it (0 with none), the number the client fades to silence at (E41).
static func phase_radius(game: Match) -> float:
	var spec := game.mode.find_phase(game.phase_id())
	return VoiceRule.radius_of(spec.voice_rule if spec != null else null)


## Why a voice between a listener at `ear` and a speaker at `mouth` breaks the distance invariant
## under the hearing radius `radius_m`, or "" when it does not. The comparison is
## VoiceRule.within's, written again here (`distance_squared_to(...) <= r * r` from the listener),
## so a pair exactly at the edge passes and a change to within does not change this check; a
## radius of 0 hears nobody.
static func distance_problem(ear: Vector3, mouth: Vector3, radius_m: float) -> String:
	if radius_m <= 0.0:
		return "in a phase whose hearing radius is 0"
	var squared := ear.distance_squared_to(mouth)
	if squared <= radius_m * radius_m:
		return ""
	return "from %.3f m, beyond the phase's hearing radius of %.3f m" % [sqrt(squared), radius_m]


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
