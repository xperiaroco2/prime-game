class_name LeakCheck
extends RefCounted
## The information-leak test (ARCHITECTURE §5, §4.6): what each bot decoded against Match.view_of of
## its peer, and the §5 invariants read on view_of's MatchEvent objects, which do not trust the
## events' declared audiences.
## - Events: the decoded events are view_of's, in order, as (name, to_dict()); a prefix for a bot
##   that left (or whose view was taken while the match went on, over ENet, where the prefix must
##   still reach view_of's last MatchEnded).
## - Snapshots and voice, subsets (LATEST and VOICE may drop): each decoded snapshot's avatars are
##   view_of's of that tick, and no tick has a second snapshot (DecodedView.repeated_snapshots);
##   each frame's speaker is one view_of lets the bot hear under its tick, and the frame is the
##   speaker's own, unchanged (voice_frame()); each frame of a VoiceBatch (M5-4b) is checked as
##   the VoiceDown it stands for (DecodedView.voice_downs), and no batch is empty, which would
##   tell a listener that someone spoke without a frame to check. In one process
##   (check_voice_streams, check_counters with `latest`) every speaker's seqs run without a gap and
##   no LATEST message was superseded, so a snapshot sent before the bot's own in the same step
##   cannot hide.
## - Invariants: every event for one peer (listed in FOR_ONE, which does not trust the declarations,
##   or declaring AUDIENCE_KIND ONLY or SENDER) that the bot decoded names it as its subject; a bot
##   whose role does not know its teammates decodes no Teammates, and a Teammates names only players
##   of the bot's own role; no decoded snapshot holds a dead player's avatar; the voice invariant
##   (§6): no bot decodes a downed or dead speaker's frame, a downed bot decodes only living
##   speakers' frames and a dead bot none; every event a bot decodes while dead is either for it
##   alone (the subject check) or also reached every living peer present then (view_of's
##   recipients, which each bot's decoded events are checked against), so nothing reaches only the
##   dead; no decoded message holds a seed; the bots present for a whole match decode the same
##   task events (check_tasks).
## - The distance invariant (§5, E45), apart from the voice rule's hears and speakers_of: no bot
##   decodes a frame of a speaker farther away than the hearing radius of the phase at the frame's
##   tick (VoiceRule.radius_of), between the two players' last accepted positions after that tick
##   (record_tick), in 3D, compared as VoiceRule.within compares them
##   (ScenarioInvariants.distance_problem); under a radius of 0 it decodes none. The relay routes
##   the frames it stamps with tick t by the routing refreshed right after tick t (§4.5), from the
##   same state, so a bot at the edge gives no false failure.
## - A connected peer that is not a player (check_watcher) decodes at most a Rejected, none unless
##   it sent a Hello, and never a Snapshot or a VoiceBatch, even an empty one. The lurker is still
##   connected unless core/ disconnected it on entering Loading (its DisconnectPeer at the tick of
##   a LoadMatch: the entry disconnects every waiting newcomer, E14), so a hello deadline, a
##   transport that dropped it, or core/ cutting it off before any match fails; the refused bot
##   decoded exactly one Rejected (wrong_version) and core/'s DisconnectPeer disconnected it. A
##   watcher core/ disconnected that is still connected fails (server/ did not carry out the
##   directive).
## - Nothing was lost on the way (check_counters): no packet rejected by the transport, no message
##   that did not decode.

const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")

## The events for one peer, written by hand (§5: the invariants do not trust the declarations), so a
## listed event whose class is declared for everyone is still checked. for_one() adds any event
## whose class declares ONLY or SENDER; bots_runner_test fails when such a class is missing here.
const FOR_ONE: Array[StringName] = [
	&"Welcome",
	&"RoleAssigned",
	&"Damaged",
	&"SelfStatus",
	&"Correction",
	&"Rejected",
	&"Disconnecting",
]
## The events every player present for a whole match decodes alike (check_tasks). TaskState
## (M4-5) is public to the living, the downed and the dead alike: the task screen is everyone's.
const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced", &"ItemSpawned", &"PackageDelivered", &"TaskState", &"TaskProgress"
]
## A synthetic voice frame: the speaker's peer id and a counter (u32 each), then FILL bytes up to
## a length of MIN_FRAME_BYTES + counter % (MAX_FRAME_BYTES - MIN_FRAME_BYTES + 1), so frames vary
## in length like Opus speech at 24 kbit/s (the M5 ADR §4: a mean near 45 B).
const FRAME_HEAD := 8
const MIN_FRAME_BYTES := 30
const MAX_FRAME_BYTES := 60
const FILL := 0xA5
## At most this many problems are listed per bot.
const MAX_LISTED := 5
## VoiceDown's seq is a u16 (§4.3).
const SEQ_MODULO := 0x10000

var _game: Match
var _seeds: Array[int] = []
## Tick -> the present living, downed and dead players after that tick.
var _alive_at: Dictionary[int, PackedInt32Array] = {}
var _downed_at: Dictionary[int, PackedInt32Array] = {}
var _dead_at: Dictionary[int, PackedInt32Array] = {}
## Tick -> each present player's last accepted position after that tick (peer -> Vector3), and the
## hearing radius of the phase then.
var _positions_at: Dictionary[int, Dictionary] = {}
var _radius_at: Dictionary[int, float] = {}
## MatchEvent instance id -> every player's role when it was emitted (Teammates only).
var _roles_at: Dictionary[int, Dictionary] = {}


func _init(game: Match) -> void:
	_game = game


## The bytes of a synthetic voice frame of `peer`, its `counter`-th.
static func voice_frame(peer: int, counter: int) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(MIN_FRAME_BYTES + counter % (MAX_FRAME_BYTES - MIN_FRAME_BYTES + 1))
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


## Called after every Match.tick call (HostSession's observer): who is alive, downed and dead,
## where each present player's last accepted position is, and the phase's hearing radius.
func record_tick(at_tick: int) -> void:
	var alive := PackedInt32Array()
	var downed := PackedInt32Array()
	var dead := PackedInt32Array()
	var positions: Dictionary[int, Vector3] = {}
	var state := _game.state
	for peer: int in state.present_peers():
		positions[peer] = state.players[peer].position
		match state.players[peer].life:
			PlayerState.Life.ALIVE:
				alive.append(peer)
			PlayerState.Life.DOWNED:
				downed.append(peer)
			PlayerState.Life.DEAD:
				dead.append(peer)
	_alive_at[at_tick] = alive
	_downed_at[at_tick] = downed
	_dead_at[at_tick] = dead
	_positions_at[at_tick] = positions
	_radius_at[at_tick] = ScenarioInvariants.phase_radius(_game)


## Each present player's last accepted position after `at_tick`, as record_tick saw it; empty for
## a tick it did not record.
func positions_at(at_tick: int) -> Dictionary[int, Vector3]:
	var found: Dictionary[int, Vector3] = {}
	found.assign(_positions_at.get(at_tick, {}) as Dictionary)
	return found


## The seeds no message may hold (ScenarioInvariants.seeds()).
func set_seeds(seeds: Array[int]) -> void:
	_seeds = seeds


## Whether `event` is for one peer, its `peer` the subject: listed in FOR_ONE, or its class declares
## a one-peer audience (ONLY or SENDER).
static func for_one(event: MatchEvent) -> bool:
	return FOR_ONE.has(event.event_name()) or declares_one(event.get_script() as Script)


## Whether the event class `script` declares AUDIENCE_KIND ONLY or SENDER.
static func declares_one(script: Script) -> bool:
	if script == null:
		return false
	var kind: Variant = script.get_script_constant_map().get("AUDIENCE_KIND")
	return kind is int and (kind == Audience.Kind.ONLY or kind == Audience.Kind.SENDER)


## The problems of bot `label` (peer `peer`) that decoded `decoded`; `prefix` when its events may be
## a prefix of view_of's (it left, or its view was taken while the match went on), and with
## `to_last_end` that prefix must still reach view_of's last MatchEnded.
func check_bot(
	label: String, peer: int, decoded: DecodedView, prefix: bool, to_last_end := false
) -> PackedStringArray:
	var found := PackedStringArray()
	if peer == 0:
		var held := (
			decoded.events.size()
			+ decoded.snapshots.size()
			+ decoded.repeated_snapshots.size()
			+ decoded.voice.size()
			+ decoded.voice_seqs.size()
			+ decoded.voice_batches
		)
		if held != 0:
			(
				found
				. append(
					(
						(
							"a view with no peer id that decoded something (%d events, %d snapshots,"
							+ " %d voice, %d voice batches)"
						)
						% [
							decoded.events.size(),
							decoded.snapshots.size(),
							decoded.voice.size(),
							decoded.voice_batches,
						]
					)
				)
			)
		return _labelled(label, peer, found)
	var view := _game.view_of(peer)
	var matched := _check_events(view, decoded, prefix, found)
	if prefix and to_last_end:
		_check_reaches_end(view, decoded, found)
	_check_subjects(view, matched, peer, found)
	_check_dead_events(matched, peer, found)
	_check_teammates(view, matched, peer, found)
	_check_snapshots(view, decoded, found)
	_check_voice(view, decoded, peer, found)
	_check_seeds(decoded, found)
	return _labelled(label, peer, found)


## The problems of a connected peer that is not a player (the lurker, the refused bot), taken while
## the run is still connected.
func check_watcher(watcher: BotWatcher) -> PackedStringArray:
	var found := PackedStringArray()
	var decoded := watcher.view
	if watcher.peer == 0:
		found.append("it never connected")
		return _labelled(watcher.label, 0, found)
	if watcher.sends_hello():
		if not watcher.said_hello:
			found.append("it never sent its Hello")
		var rejected := decoded.events_named(&"Rejected")
		if rejected.size() != 1 or str(rejected[0].fields.get("reason", "")) != "wrong_version":
			found.append("decoded %d Rejected, not exactly one (wrong_version)" % rejected.size())
		if _disconnected_at(watcher.peer) < 0:
			found.append("core/ never emitted DisconnectPeer for it")
	else:
		var at_tick := _disconnected_at(watcher.peer)
		if watcher.lost and at_tick < 0:
			found.append("it lost its connection, and core/ never disconnected it")
		elif at_tick >= 0 and not _loading_entered_at(at_tick):
			found.append("core/ disconnected it at tick %d, not on entering Loading" % at_tick)
	if not watcher.lost and _disconnected_at(watcher.peer) >= 0:
		found.append(
			"core/ disconnected it, but it is still connected (server/ did not carry it out)"
		)
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
	if decoded.voice_batches > 0:
		found.append("decoded %d VoiceBatches" % decoded.voice_batches)
	return _labelled(watcher.label, watcher.peer, found)


## The seqs of each speaker's frames that `decoded` holds, by tick then arrival, run 0, 1, 2, ...
## without a gap (wrapping at 65536): the relay renumbers per speaker and listener (§4.5) and the
## loopback loses nothing, so another seq (such as the speaker's own, which tells how much it said
## to others) is a leak. One process only: over ENet the VOICE lane may drop.
func check_voice_streams(label: String, peer: int, decoded: DecodedView) -> PackedStringArray:
	var found := PackedStringArray()
	var keys: Array[Vector2i] = []
	keys.assign(decoded.voice_seqs.keys())
	keys.sort()
	var next: Dictionary[int, int] = {}
	for key: Vector2i in keys:
		for seq: int in decoded.voice_seqs[key]:
			var due: int = next.get(key.x, 0)
			if seq != due:
				found.append(
					(
						"voice of %d under tick %d has seq %d, its stream's next is %d"
						% [key.x, key.y, seq, due]
					)
				)
			next[key.x] = (seq + 1) % SEQ_MODULO
	return _labelled(label, peer, found)


## What `label` (peer `peer`) lost on the way: packets its `transport` rejected, `undecodable`
## messages, and with `latest` any LATEST message the transport superseded in a poll (in one process
## the host sends one snapshot per peer per step and the client polls once per step, so a
## superseded one is a second snapshot that would stay unseen).
static func check_counters(
	label: String, peer: int, transport: NetTransport, undecodable: int, latest: bool
) -> PackedStringArray:
	var found := PackedStringArray()
	if transport.rejects.total() != 0:
		found.append("its transport rejected %d packets" % transport.rejects.total())
	if undecodable != 0:
		found.append("%d messages did not decode" % undecodable)
	if latest and transport.latest_superseded != 0:
		found.append(
			(
				"%d LATEST messages were superseded in a poll (a second snapshot of a step)"
				% transport.latest_superseded
			)
		)
	return _labelled(label, peer, found)


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


func _check_reaches_end(view: PeerView, decoded: DecodedView, found: PackedStringArray) -> void:
	for i in range(view.events.size() - 1, -1, -1):
		if view.events[i].event_name() != &"MatchEnded":
			continue
		if decoded.events.size() <= i:
			found.append(
				(
					"decoded %d events, short of view_of's last MatchEnded (event %d)"
					% [decoded.events.size(), i]
				)
			)
		return


func _check_subjects(view: PeerView, matched: int, peer: int, found: PackedStringArray) -> void:
	for i in matched:
		var event := view.events[i]
		if not for_one(event):
			continue
		var subject: Variant = event.get("peer")
		if not subject is int:
			found.append(
				"decoded %s, an event for one peer with no int `peer`" % event.event_name()
			)
		elif subject != peer:
			found.append("decoded %s of peer %d" % [event.event_name(), subject])


## The first `matched` events of `peer` (the ones it decoded): each one emitted at a tick after
## which `peer` was dead is for it alone, or also reached every peer living after that tick.
func _check_dead_events(matched: int, peer: int, found: PackedStringArray) -> void:
	var seen := 0
	for emitted: EmittedEvent in _game.emitted():
		if seen >= matched:
			return
		if not emitted.recipients.has(peer):
			continue
		seen += 1
		var dead: PackedInt32Array = _dead_at.get(emitted.tick, PackedInt32Array())
		if not dead.has(peer):
			continue
		var event := emitted.event
		if for_one(event) and event.get("peer") is int and event.get("peer") == peer:
			continue
		var alive: PackedInt32Array = _alive_at.get(emitted.tick, PackedInt32Array())
		for other: int in alive:
			if not emitted.recipients.has(other):
				found.append(
					(
						"dead, it decoded %s at tick %d, which living %d did not"
						% [event.event_name(), emitted.tick, other]
					)
				)


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


func _check_snapshots(view: PeerView, decoded: DecodedView, found: PackedStringArray) -> void:
	for at_tick: int in decoded.snapshots:
		if not view.snapshots.has(at_tick):
			found.append("a snapshot of tick %d that view_of lacks" % at_tick)
			continue
		var avatars: Dictionary = decoded.snapshots[at_tick]["avatars"]
		if not WireSamples.same(avatars, view.snapshots[at_tick]["avatars"]):
			found.append("the snapshot of tick %d differs from view_of's" % at_tick)
		var dead: PackedInt32Array = _dead_at.get(at_tick, PackedInt32Array())
		for other: int in avatars:
			if dead.has(other):
				found.append("it decoded the avatar of dead %d at tick %d" % [other, at_tick])
	for repeated: Dictionary in decoded.repeated_snapshots:
		found.append("a second snapshot of tick %d" % (repeated["tick"] as int))


func _check_voice(
	view: PeerView, decoded: DecodedView, peer: int, found: PackedStringArray
) -> void:
	if decoded.empty_batches > 0:
		found.append("%d empty VoiceBatches" % decoded.empty_batches)
	for key: Vector2i in decoded.voice:
		var speaker := key.x
		var at_tick := key.y
		var allowed: PackedInt32Array = view.speakers.get(at_tick, PackedInt32Array())
		if not allowed.has(speaker):
			found.append(
				"voice of %d under tick %d, which view_of does not allow" % [speaker, at_tick]
			)
		found.append_array(_voice_invariant(peer, speaker, at_tick))
		var far := _distance_problem(peer, speaker, at_tick)
		if not far.is_empty():
			found.append(far)
		for frame: PackedByteArray in decoded.frames(speaker, at_tick):
			var problem := frame_problem(speaker, frame)
			if not problem.is_empty():
				found.append(problem)


## The voice invariant's broken parts (§6) for `peer` decoding `speaker`'s frame under `at_tick`,
## from the life states the observer recorded, never view_of.
func _voice_invariant(peer: int, speaker: int, at_tick: int) -> PackedStringArray:
	var found := PackedStringArray()
	var alive: PackedInt32Array = _alive_at.get(at_tick, PackedInt32Array())
	var downed: PackedInt32Array = _downed_at.get(at_tick, PackedInt32Array())
	var dead: PackedInt32Array = _dead_at.get(at_tick, PackedInt32Array())
	if downed.has(speaker):
		found.append("it heard downed %d at tick %d" % [speaker, at_tick])
	if dead.has(speaker):
		found.append("it heard dead %d at tick %d" % [speaker, at_tick])
	if downed.has(peer) and not alive.has(speaker):
		found.append("downed, it heard %d, who was not living, at tick %d" % [speaker, at_tick])
	if dead.has(peer):
		found.append("dead, it heard %d at tick %d" % [speaker, at_tick])
	return found


## Why `peer` decoding `speaker`'s frame under `at_tick` breaks the distance invariant, or "":
## from the positions and the radius record_tick saw after that tick, never the voice rule or
## view_of.
func _distance_problem(peer: int, speaker: int, at_tick: int) -> String:
	if not _positions_at.has(at_tick):
		return "it heard %d under tick %d, whose positions were never recorded" % [speaker, at_tick]
	var positions: Dictionary = _positions_at[at_tick]
	for player: int in [peer, speaker]:
		if not positions.has(player):
			return (
				"it heard %d under tick %d, when %d was not a present player"
				% [speaker, at_tick, player]
			)
	var problem := ScenarioInvariants.distance_problem(
		positions[peer] as Vector3, positions[speaker] as Vector3, _radius_at[at_tick]
	)
	if problem.is_empty():
		return ""
	return "it heard %d at tick %d %s" % [speaker, at_tick, problem]


func _check_seeds(decoded: DecodedView, found: PackedStringArray) -> void:
	for seed_value: int in _seeds:
		for event: WireMessage in decoded.events:
			if ScenarioInvariants.holds_int(event.fields, seed_value):
				found.append("decoded %s holding a seed" % event.name)
		for at_tick: int in decoded.snapshots:
			if ScenarioInvariants.holds_int(decoded.snapshots[at_tick], seed_value):
				found.append("the snapshot of tick %d holds a seed" % at_tick)


## The tick of core/'s first DisconnectPeer of `peer`, or -1 (loopback ids are never reused in one
## run).
func _disconnected_at(peer: int) -> int:
	for emitted: EmittedEvent in _game.emitted():
		var directive := emitted.event as DisconnectPeerEvent
		if directive != null and directive.peer == peer:
			return emitted.tick
	return -1


## Whether core/ entered Loading at `at_tick` (it emitted a LoadMatch then).
func _loading_entered_at(at_tick: int) -> bool:
	for emitted: EmittedEvent in _game.emitted():
		if emitted.tick == at_tick and emitted.event is LoadMatchEvent:
			return true
	return false


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
