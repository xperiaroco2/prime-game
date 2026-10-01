class_name LeakCheck
extends RefCounted
## The information-leak test (ARCHITECTURE §5, §4.6): what each bot decoded against Match.view_of of
## its peer, and the §5 invariants read on view_of's MatchEvent objects, which do not trust the
## events' declared audiences.
## - Events: the decoded events are view_of's, in order, as (name, to_dict()); a prefix for a bot
##   that left (or whose view was taken while the match went on, over ENet).
## - Snapshots and voice, subsets (LATEST and VOICE may drop): each decoded snapshot's avatars are
##   view_of's of that tick; each frame's speaker is one view_of lets the bot hear under its tick,
##   and the frame is the speaker's own, unchanged (voice_frame()).
## - Invariants: every event for one peer that the bot decoded names it as its subject; a bot whose
##   role does not know its teammates decodes no Teammates, and a Teammates names only players of
##   the bot's own role; a living bot decodes no ghost's avatar or voice; no decoded message holds a
##   seed; the bots present for a whole match decode the same task events (check_tasks).
## - A connected peer that is not a player (check_watcher) decodes at most a Rejected, none unless
##   it sent a Hello, and never a Snapshot or a VoiceDown.

const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")

## The events for one peer, whose subject must be the bot that decoded them.
const FOR_ONE: Array[StringName] = [
	&"Welcome", &"RoleAssigned", &"Damaged", &"SelfStatus", &"Correction", &"Rejected"
]
const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced", &"ItemSpawned", &"PackageDelivered", &"TaskProgress"
]
## A synthetic voice frame: the speaker's peer id and a counter (u32 each), then counter % FILL_SPAN
## bytes of FILL, so frames vary in length.
const FRAME_HEAD := 8
const FILL_SPAN := 7
const FILL := 0xA5
## At most this many problems are listed per bot.
const MAX_LISTED := 5

var _game: Match
var _seeds: Array[int] = []
## Tick -> the present living players and the present ghosts after that tick.
var _alive_at: Dictionary[int, PackedInt32Array] = {}
var _ghosts_at: Dictionary[int, PackedInt32Array] = {}
## MatchEvent instance id -> every player's role when it was emitted (Teammates only).
var _roles_at: Dictionary[int, Dictionary] = {}


func _init(game: Match) -> void:
	_game = game


## The bytes of a synthetic voice frame of `peer`, its `counter`-th.
static func voice_frame(peer: int, counter: int) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(FRAME_HEAD + counter % FILL_SPAN)
	frame.fill(FILL)
	frame.encode_u32(0, peer)
	frame.encode_u32(4, counter)
	return frame


## Why `frame`, relayed as `speaker`'s, is not a frame that speaker sent unchanged; "" when it is.
static func frame_problem(speaker: int, frame: PackedByteArray) -> String:
	if frame.size() < FRAME_HEAD:
		return "a frame of %d bytes" % frame.size()
	var sender := frame.decode_u32(0)
	if sender != speaker:
		return "a frame of peer %d relayed as peer %d's" % [sender, speaker]
	var counter := frame.decode_u32(4)
	if frame != voice_frame(sender, counter):
		return "frame %d of peer %d was changed" % [counter, sender]
	return ""


## Called after every Match.tick call (HostSession's observer): who is alive and who a ghost.
func record_tick(at_tick: int) -> void:
	var alive := PackedInt32Array()
	var ghosts := PackedInt32Array()
	var state := _game.state
	for peer: int in state.present_peers():
		if state.players[peer].life == PlayerState.Life.GHOST:
			ghosts.append(peer)
		elif state.players[peer].life == PlayerState.Life.ALIVE:
			alive.append(peer)
	_alive_at[at_tick] = alive
	_ghosts_at[at_tick] = ghosts


## The seeds no message may hold (ScenarioInvariants.seeds()).
func set_seeds(seeds: Array[int]) -> void:
	_seeds = seeds


## The problems of bot `label` (peer `peer`) that decoded `decoded`; `prefix` when its events may be
## a prefix of view_of's (it left, or its view was taken while the match went on).
func check_bot(label: String, peer: int, decoded: DecodedView, prefix: bool) -> PackedStringArray:
	var found := PackedStringArray()
	var view := _game.view_of(peer)
	var matched := _check_events(view, decoded, prefix, found)
	_check_subjects(view, matched, peer, found)
	_check_teammates(view, matched, peer, found)
	_check_snapshots(view, decoded, peer, found)
	_check_voice(view, decoded, peer, found)
	_check_seeds(decoded, found)
	return _labelled(label, peer, found)


## The problems of a connected peer that is not a player (the lurker, the refused bot).
func check_watcher(watcher: BotWatcher) -> PackedStringArray:
	var found := PackedStringArray()
	var decoded := watcher.view
	if watcher.peer == 0:
		found.append("it never connected")
		return _labelled(watcher.label, 0, found)
	var view := _game.view_of(watcher.peer)
	_check_events(view, decoded, false, found)
	for event: WireMessage in decoded.events:
		if event.name != &"Rejected":
			found.append("decoded %s, a peer that is not a player" % event.name)
		elif not watcher.said_hello:
			found.append("decoded a Rejected without sending a Hello")
	if decoded.events.size() > 1:
		found.append("decoded %d events, at most one Rejected" % decoded.events.size())
	if not decoded.snapshots.is_empty():
		found.append("decoded %d snapshots" % decoded.snapshots.size())
	if not decoded.voice.is_empty():
		found.append("decoded voice of %d speaker-ticks" % decoded.voice.size())
	return _labelled(watcher.label, watcher.peer, found)


## The bots present for a whole match (its LoadMatch to its MatchEnded) decoded the same task
## events: `views` maps a label to a decoded view.
func check_tasks(views: Dictionary[String, DecodedView]) -> PackedStringArray:
	var found := PackedStringArray()
	var first: Dictionary[int, String] = {}
	var tasks_of: Dictionary[int, Array] = {}
	for label: String in views:
		var rounds := _whole_matches(views[label])
		for match_id: int in rounds:
			if not first.has(match_id):
				first[match_id] = label
				tasks_of[match_id] = rounds[match_id]
			elif rounds[match_id] != tasks_of[match_id]:
				found.append(
					(
						"leak: %s and %s decoded different task events in match %d"
						% [first[match_id], label, match_id]
					)
				)
	return found


func _check_events(
	view: PeerView, decoded: DecodedView, prefix: bool, found: PackedStringArray
) -> int:
	var expected := view.events.size()
	var got := decoded.events.size()
	if got > expected or (got < expected and not prefix):
		found.append("decoded %d events, view_of holds %d" % [got, expected])
	var matched := 0
	for i in mini(got, expected):
		var event := view.events[i]
		var mine := decoded.events[i]
		if mine.name != event.event_name() or not WireSamples.same(mine.fields, event.to_dict()):
			found.append(
				(
					"event %d: decoded %s %s, view_of %s %s"
					% [i, mine.name, mine.fields, event.event_name(), event.to_dict()]
				)
			)
			break
		matched = i + 1
	if got > expected:
		found.append("events beyond view_of: %s" % [_names(decoded.events.slice(expected))])
	return matched


func _check_subjects(view: PeerView, matched: int, peer: int, found: PackedStringArray) -> void:
	for i in matched:
		var event := view.events[i]
		if not FOR_ONE.has(event.event_name()):
			continue
		var subject: int = event.get("peer")
		if subject != peer:
			found.append("decoded %s of peer %d" % [event.event_name(), subject])


func _check_teammates(view: PeerView, matched: int, peer: int, found: PackedStringArray) -> void:
	for i in matched:
		var teammates := view.events[i] as TeammatesEvent
		if teammates == null:
			continue
		var roles := _roles_when(teammates)
		var own: StringName = roles.get(peer, &"")
		var own_role := _game.mode.find_role(own)
		if own_role == null or not own_role.knows_teammates:
			found.append("decoded Teammates as %s, a role that does not know its teammates" % own)
			continue
		if teammates.role != own:
			found.append("decoded the Teammates of %s as %s" % [teammates.role, own])
		for other: int in teammates.peers:
			if roles.get(other, &"") != own:
				found.append("decoded Teammates naming peer %d, not %s" % [other, own])


func _check_snapshots(
	view: PeerView, decoded: DecodedView, peer: int, found: PackedStringArray
) -> void:
	for at_tick: int in decoded.snapshots:
		if not view.snapshots.has(at_tick):
			found.append("a snapshot of tick %d that view_of lacks" % at_tick)
			continue
		var avatars: Dictionary = decoded.snapshots[at_tick]["avatars"]
		if not WireSamples.same(avatars, view.snapshots[at_tick]["avatars"]):
			found.append("the snapshot of tick %d differs from view_of's" % at_tick)
		var alive: PackedInt32Array = _alive_at.get(at_tick, PackedInt32Array())
		var ghosts: PackedInt32Array = _ghosts_at.get(at_tick, PackedInt32Array())
		if alive.has(peer):
			for other: int in avatars:
				if ghosts.has(other):
					found.append("living, it decoded ghost %d at tick %d" % [other, at_tick])


func _check_voice(
	view: PeerView, decoded: DecodedView, peer: int, found: PackedStringArray
) -> void:
	for key: Vector2i in decoded.voice:
		var speaker := key.x
		var at_tick := key.y
		var allowed: PackedInt32Array = view.speakers.get(at_tick, PackedInt32Array())
		if not allowed.has(speaker):
			found.append(
				"voice of %d under tick %d, which view_of does not allow" % [speaker, at_tick]
			)
		var alive: PackedInt32Array = _alive_at.get(at_tick, PackedInt32Array())
		var ghosts: PackedInt32Array = _ghosts_at.get(at_tick, PackedInt32Array())
		if alive.has(peer) and ghosts.has(speaker):
			found.append("living, it heard ghost %d at tick %d" % [speaker, at_tick])
		for frame: PackedByteArray in decoded.frames(speaker, at_tick):
			var problem := frame_problem(speaker, frame)
			if not problem.is_empty():
				found.append(problem)


func _check_seeds(decoded: DecodedView, found: PackedStringArray) -> void:
	for seed_value: int in _seeds:
		for event: WireMessage in decoded.events:
			if ScenarioInvariants.holds_int(event.fields, seed_value):
				found.append("decoded %s holding a seed" % event.name)
		for at_tick: int in decoded.snapshots:
			if ScenarioInvariants.holds_int(decoded.snapshots[at_tick], seed_value):
				found.append("the snapshot of tick %d holds a seed" % at_tick)


## Every player's role (from the RoleAssigned events emitted before it) when `event` was emitted.
func _roles_when(event: MatchEvent) -> Dictionary:
	var id := event.get_instance_id()
	if _roles_at.is_empty():
		var roles := {}
		for emitted: EmittedEvent in _game.emitted():
			var assigned := emitted.event as RoleAssignedEvent
			if assigned != null:
				roles[assigned.peer] = assigned.role
			elif emitted.event is TeammatesEvent:
				_roles_at[emitted.event.get_instance_id()] = roles.duplicate()
	return _roles_at.get(id, {})


## Match id -> the task events (name and fields, as text) decoded from its LoadMatch to its
## MatchEnded, for the matches the view holds whole.
static func _whole_matches(decoded: DecodedView) -> Dictionary[int, Array]:
	var whole: Dictionary[int, Array] = {}
	var current := -1
	var tasks: Array[String] = []
	for event: WireMessage in decoded.events:
		if event.name == &"LoadMatch":
			current = event.fields["match_id"] as int
			tasks = []
		elif event.name == &"MatchEnded" and current >= 0:
			whole[current] = tasks
			current = -1
		elif current >= 0 and TASK_EVENTS.has(event.name):
			tasks.append("%s %s" % [event.name, event.fields])
	return whole


static func _names(events: Array[WireMessage]) -> Array[StringName]:
	var names: Array[StringName] = []
	for event: WireMessage in events:
		names.append(event.name)
	return names


static func _labelled(label: String, peer: int, found: PackedStringArray) -> PackedStringArray:
	var listed := PackedStringArray()
	for i in mini(found.size(), MAX_LISTED):
		listed.append("leak: %s (peer %d): %s" % [label, peer, found[i]])
	if found.size() > MAX_LISTED:
		listed.append("leak: %s (peer %d): and %d more" % [label, peer, found.size() - MAX_LISTED])
	return listed
