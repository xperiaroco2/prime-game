class_name HostSession
extends RefCounted
## The host session (ARCHITECTURE §4.5; ADR 2026-09-30-wire-format-and-host-session, choice 6, E7,
## E11, E13, E17): it owns the Match, the hosting transport with the host's own client linked as
## peer 1, the levels' collision worlds and the bookkeeping per peer. Its owner calls step(now_usec)
## every physics frame with a clock in microseconds (HostNode: Time.get_ticks_usec(); tests and the
## bots runner: a clock of their own, where a host freeze is a jump of that clock).
##
## Host ticks come from the clock: tick = floor((now - start) * Ticks.RATE / 10^6). One step, in
## this order (§4.5's table): (1) catch up: commands left from an earlier step are applied at
## ticked_through() + 1 and that tick runs, then every tick up to the due one minus one runs with no
## command; (2) refill every peer's budgets; (3) poll: arrivals and departures become PeerConnected
## and PeerLeft, intents are queued by arrival, voice is relayed right after the poll; (4) when
## the due tick has not run: every queued command stamped with it, then Match.tick; (5) every
## Match call's outbox slice is delivered as soon as it is taken; (6) snapshots for the step's own
## tick; (7) the hello deadlines, in a step that ran (4) only.
##
## Delivery: an event is encoded once and sent to each of core/'s recipients in peer-id order,
## skipping peers this session disconnected and, from peer_left(p) until the call that applies
## PeerLeft(p), p (peer ids are reused). Directives are carried out where they stand:
## RefuseJoins/AllowJoins set the transport's refusal, DisconnectPeer disconnects after what came
## before it (its Rejected) was sent, and is dropped while the peer's leave is pending (it is about
## the connection that left).
##
## Peer 1, the host's own client, is exempt from the budgets, the malformed-message disconnect and
## the hello deadline: the transport cannot disconnect it, so a broken own client ends the session.
## So does a transition row that records an error (Match.row_error_count(), a failed deal), before
## that call's slice is delivered. A debug build writes the command log when the session ends
## (ReplayFiles) and hands each slice to `observer`.
##
## The host's own ClientSession runs on `own_client` like any other client and reads nothing here.

## The session is over: one of the reasons below; `errors` says more. The transport is closed, so
## every client sees host_lost.
signal ended(reason: StringName)

## The owner closed it (the host quits, or its own client's load failed).
const CLOSED := &"closed"
## A transition row recorded an error (a deal that could not complete, §4.5).
const ROW_ERROR := &"row_error"
## The host's own client kept sending malformed messages (a codec bug).
const OWN_CLIENT_MALFORMED := &"own_client_malformed"
## core/ asked to disconnect the host's own client (a core/ bug, §3.2).
const OWN_CLIENT_DISCONNECTED := &"own_client_disconnected"
## A peer with no Welcome this long after it connected is disconnected: 10 s, a placeholder, "not
## a decision". It outlasts a 5 s freeze of either side.
const HELLO_DEADLINE_USEC := 10 * 1000000
## A peer whose messages were rejected (by the transport or the codec) this many times within
## MALFORMED_WINDOW_USEC is disconnected: placeholders, "not a decision" (E7).
const MALFORMED_LIMIT := 50
const MALFORMED_WINDOW_SECONDS := 10
const USEC_PER_SECOND := 1000000
const MALFORMED_WINDOW_USEC := MALFORMED_WINDOW_SECONDS * USEC_PER_SECOND
const SNAPSHOT := &"Snapshot"
const WELCOME := &"Welcome"

## The hello deadline, in microseconds of the session's clock (the bots runner raises it for its
## lurker, §4.6).
var hello_deadline_usec := HELLO_DEADLINE_USEC
## Where a debug build writes the session's command log when it ends (ReplayFiles); empty writes
## none. Never written in a release build.
var replay_dir := ReplayFiles.DIR
## The file the log was written to when the session ended; empty when none was.
var replay_path := ""
## Why the last start() refused, or why the session ended. A refused start may be retried on the
## same session (another port, say): each start begins with no errors.
var errors := PackedStringArray()
## Why the session ended; empty while it runs.
var end_reason: StringName = &""
## The match; null until a start succeeded. Its keep_history stays off unless the owner turns it
## on (the bots runner does, right after start()).
var game: Match
## The host's content hash (§4.3, E1): ContentFingerprint of the mode, its level files and every
## scene and resource a level reaches (#118), the same as every client computes from its own copy
## of the mode; Match.content_hash.
var content_hash := 0
## The host's own client, peer 1, linked to the hosting transport: its owner runs a ClientSession
## on it.
var own_client: NetTransport
## Debug builds only: called after every Match call (start, apply, tick, catch-up ticks included)
## with (at_tick: int, command: MatchCommand, slice: Array[EmittedEvent]), `command` null for a
## tick and for the start, before the slice is delivered and before anything else is applied. The
## bots runner (3h) sets it to run ScenarioInvariants per call (§4.5, §4.6). It must not call
## step() or apply anything.
var observer := Callable()
## Messages dropped over a budget (also in the transport's rejects, OVER_BUDGET).
var over_budget := 0
## Payloads the codec rejected, and debug kinds from a peer other than 1 (BAD_PAYLOAD).
var bad_payloads := 0
## Peers disconnected for malformed messages.
var malformed_disconnects := 0
## Of over_budget, the VoiceUp frames over a speaker's voice bucket.
var voice_over_budget := 0

var _transport: NetTransport
var _schema: WireSchema
var _debug := OS.is_debug_build()
var _started := false
var _ended := false
var _start_usec := 0
var _now_usec := 0
var _last_refill_usec := 0
## Commands by arrival, stamped when applied.
var _queue: Array[MatchCommand] = []
var _row_errors := 0
var _diagnostics_seen := 0
## Connected peers (the transport's), with their deadline, budget and malformed count.
var _peers: Dictionary[int, _Peer] = {}
## Peer -> how many of its PeerLeft commands are queued and not applied yet.
var _leaving: Dictionary[int, int] = {}
## Peers this session disconnected whose peer_left has not come yet.
var _disconnected: Dictionary[int, bool] = {}
var _relay := VoiceRelay.new()
var _voice_down: VoiceDownEncoder
## Debug builds only (E47 as amended): the relay's time and the upload, apart; null in a release
## build.
var _meter: RelayMeter = RelayMeter.new() if _debug else null
## An end asked for inside the poll, carried out right after it.
var _end_after_poll: StringName = &""


## One connected peer's bookkeeping.
class _Peer:
	extends RefCounted
	var joined_usec := 0
	var welcomed := false
	var budget := PeerBudget.new()
	## The times of its rejected messages within the window, oldest first, and their reasons.
	var malformed: Array[int] = []
	var reasons: Array[String] = []

	func _init(at_usec: int) -> void:
		joined_usec = at_usec


## A session on `transport` (not hosting yet), whose kind table must be `schema`'s; the schema
## defaults to this build's (a debug build's has the debug kinds, E17).
func _init(transport: NetTransport, schema: WireSchema = null) -> void:
	_transport = transport
	_schema = schema if schema != null else WireSchema.game(OS.is_debug_build())
	_voice_down = VoiceDownEncoder.new(_schema)
	# Bound methods, not lambdas: a lambda capturing self, held by the transport, is a cycle.
	_transport.peer_joined.connect(_on_peer_joined)
	_transport.peer_left.connect(_on_peer_left)
	_transport.packet_received.connect(_on_packet)
	_transport.packet_rejected.connect(_on_rejected)


## Starts hosting `mode` on `port` (§4.5 Starting): every level's collision world (refused on
## its errors), the markers read through them, then start_with() with a seed from the operating
## system's entropy. False, with `errors`, when refused. `now_usec` is host tick 0 on the clock
## that later steps use: with HostNode, HostNode.now_usec().
func start(mode: GameMode, port: int, max_clients: int, now_usec: int) -> bool:
	if not _started and not _ended:
		errors.clear()
	var world := HostWorldQuery.for_mode(mode)
	if not world.errors.is_empty():
		errors.append_array(world.errors)
		return false
	var levels := MarkerReader.read_levels(mode, world)
	if not levels.errors.is_empty():
		errors.append_array(levels.errors)
		return false
	return start_with(mode, world, levels.layouts, port, max_clients, now_usec, random_seed())


## Starts hosting with the worlds and layouts given (tests, and runners on flat levels): the mode
## must fit the wire (WireBudget) and pass Match's checks; then Match.new with the content hash,
## hosting, the own client linked, and Match.start(0) at `now_usec`, host tick 0.
func start_with(
	mode: GameMode,
	world: WorldQuery,
	layouts: Dictionary[String, LevelLayout],
	port: int,
	max_clients: int,
	now_usec: int,
	session_seed: int
) -> bool:
	if _started or _ended:
		errors.append("the session has started already")
		return false
	errors.clear()
	errors.append_array(WireBudget.check(mode))
	if not errors.is_empty():
		return false
	var fingerprint := ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)
	var made := Match.new(mode, session_seed, world, layouts, fingerprint)
	if not made.refusals.is_empty():
		errors.append_array(made.refusals)
		return false
	var hosted := _transport.host(port, max_clients)
	if hosted != OK:
		errors.append("cannot host on port %d: %s" % [port, error_string(hosted)])
		return false
	content_hash = fingerprint
	game = made
	own_client = LoopbackTransport.own_client_of(_transport)
	_started = true
	_start_usec = now_usec
	_now_usec = now_usec
	_last_refill_usec = now_usec
	game.start(0)
	_after_call(0, null)
	return not _ended


## 8 bytes of the operating system's entropy, never the time (§3.3).
static func random_seed() -> int:
	return Crypto.new().generate_random_bytes(8).decode_s64(0)


## The host tick due at `now_usec`.
func tick_of(now_usec: int) -> int:
	@warning_ignore("integer_division")
	return (now_usec - _start_usec) * Ticks.RATE / USEC_PER_SECOND


func is_running() -> bool:
	return _started and not _ended


## The frames the voice relay dropped as the old part of a backlog.
func voice_dropped() -> int:
	return _relay.dropped


## Of over_budget, the messages that are no voice frames: the part the F3 overlay may show at any
## time (HostNode.counters()). The voice frames over budget are among the relay's counters, which it
## never shows live during a Round (the M5 ADR §3 item 11, E47).
func over_budget_but_voice() -> int:
	return over_budget - voice_over_budget


## Debug builds only (E47 as amended; ARCHITECTURE §4.5 "The host's counters"): the voice relay's
## counters and the upload since the session started (RelayMeter.to_dict); empty in a release
## build. Never for a live display during a Round (the M5 ADR §3 item 11).
func relay_counters() -> Dictionary[StringName, int]:
	if _meter == null or not _started:
		var none: Dictionary[StringName, int] = {}
		return none
	return _meter.to_dict(_relay, voice_over_budget, _now_usec - _start_usec)


## One physics frame of the session at `now_usec` (the order in the class comment).
func step(now_usec: int) -> void:
	if not is_running():
		return
	_now_usec = now_usec
	var due := tick_of(now_usec)
	# 1. Catch up: what an earlier step queued goes on the next tick, then the skipped ticks run.
	if not _queue.is_empty() and game.ticked_through() + 1 < due:
		if not _apply_queue(game.ticked_through() + 1):
			return
		if not _run_tick(game.ticked_through() + 1):
			return
	while game.ticked_through() < due - 1:
		if not _run_tick(game.ticked_through() + 1):
			return
	# 2. Refill, before any packet of this step is read.
	for info: _Peer in _peers.values():
		info.budget.refill(now_usec - _last_refill_usec)
	_last_refill_usec = now_usec
	# 3. Poll; voice goes out at once, stamped with the last tick run.
	_transport.poll()
	if not _end_after_poll.is_empty():
		_end(_end_after_poll)
		return
	_send_voice()
	# 4. Apply, when the due tick has not run yet; else the queue waits for the next one.
	if game.ticked_through() < due:
		if not _apply_queue(due) or not _run_tick(due):
			return
		# 6. Snapshots for this step's own tick only, after its events.
		_send_snapshots(due)
		# 7. Deadlines, only after an apply: a queued Hello (one that waited out a host freeze, or
		# read in a step with no tick due) is applied first.
		_check_deadlines()


## Ends the session: the owner's choice (the host quits, or its own client's load failed).
func close() -> void:
	_end(CLOSED)


func _apply_queue(at_tick: int) -> bool:
	var batch := _queue
	_queue = []
	for command: MatchCommand in batch:
		command.tick = at_tick
		if command.kind == Intents.PEER_LEFT:
			# The call that applies PeerLeft(p) and those after it address whoever has p now.
			var left: int = _leaving.get(command.peer, 0) - 1
			if left > 0:
				_leaving[command.peer] = left
			else:
				_leaving.erase(command.peer)
		game.apply(command)
		if not _after_call(at_tick, command):
			return false
	return true


func _run_tick(at_tick: int) -> bool:
	game.tick(at_tick)
	if not _after_call(at_tick, null):
		return false
	_refresh_routes()
	return true


## The slice of the Match call just made: the observer, the fatal row error, then delivery.
func _after_call(at_tick: int, command: MatchCommand) -> bool:
	var slice := game.take_outbox()
	if _debug and observer.is_valid():
		observer.call(at_tick, command, slice)
	if game.row_error_count() > _row_errors:
		_row_errors = game.row_error_count()
		for diagnostic: String in game.diagnostics.slice(_diagnostics_seen):
			errors.append(diagnostic)
		_end(ROW_ERROR)
		return false
	_diagnostics_seen = game.diagnostics.size()
	_deliver(slice)
	return not _ended


func _deliver(slice: Array[EmittedEvent]) -> void:
	for emitted: EmittedEvent in slice:
		if emitted.is_directive:
			_carry_out(emitted.event)
			if _ended:
				return
			continue
		var event_name := emitted.event.event_name()
		var payload := _schema.encode(WireMessage.new(event_name, emitted.event.to_dict()))
		if payload.is_empty():
			continue  # the codec logged why
		var kind := _schema.kind_of(event_name)
		var recipients := emitted.recipients.duplicate()
		recipients.sort()
		for peer: int in recipients:
			if not _reachable(peer):
				continue
			_send(peer, kind, payload)
			if event_name == WELCOME and _peers.has(peer):
				_peers[peer].welcomed = true


func _carry_out(directive: MatchEvent) -> void:
	if directive is RefuseJoinsEvent:
		_transport.set_refuse_new_connections(true)
	elif directive is AllowJoinsEvent:
		_transport.set_refuse_new_connections(false)
	elif directive is DisconnectPeerEvent:
		var peer := (directive as DisconnectPeerEvent).peer
		if peer == NetTransport.HOST_ID:
			errors.append("core/ asked to disconnect the host's own client")
			_end(OWN_CLIENT_DISCONNECTED)
			return
		if _leaving.has(peer):
			# It answers a command of the connection that left; a new one may hold the id now.
			return
		_disconnect(peer)
	else:
		push_error("host: unknown directive %s" % directive.event_name())


func _send_snapshots(at_tick: int) -> void:
	if _meter != null:
		_meter.add_other_upload(_transport.take_upload())
	var kind := _schema.kind_of(SNAPSHOT)
	var present := game.state.present_peers()
	present.sort()
	for peer: int in present:
		if not _reachable(peer):
			continue
		var snapshot := game.snapshot_for(peer)
		if snapshot.is_empty():
			continue
		var fields := {"tick": at_tick, "avatars": snapshot["avatars"]}
		var payload := _schema.encode(WireMessage.new(SNAPSHOT, fields))
		if not payload.is_empty() and _send(peer, kind, payload) == OK and _meter != null:
			_meter.snapshots += 1
	if _meter != null:
		_meter.add_snapshot_upload(_transport.take_upload())


func _send_voice() -> void:
	if not _relay.has_held():
		return
	var began := 0
	if _meter != null:
		_meter.add_other_upload(_transport.take_upload())
		began = Time.get_ticks_usec()
	var kind := _voice_down.kind
	for out: VoiceRelay.Outgoing in _relay.flush(game.ticked_through()):
		# Encoded once per frame, for its first reachable listener; each gets a copy with its seq.
		var encoded := PackedByteArray()
		for i in out.listeners.size():
			var listener := out.listeners[i]
			if not _reachable(listener):
				continue
			if encoded.is_empty():
				encoded = _voice_down.encode(out.message)
				if encoded.is_empty():
					break  # the codec logged why
			var payload := _voice_down.with_seq(encoded, out.message, out.seqs[i])
			if _meter == null:
				_send(listener, kind, payload)
				continue
			var send_began := Time.get_ticks_usec()
			var sent := _send(listener, kind, payload)
			_meter.send_usec += Time.get_ticks_usec() - send_began
			if sent == OK:
				_meter.sent += 1
	if _meter != null:
		_meter.relay_usec += Time.get_ticks_usec() - began
		_meter.add_voice_upload(_transport.take_upload())


## The routing table after a Match.tick call (§4.5 Voice relay): speakers_for every present player.
func _refresh_routes() -> void:
	var table: Dictionary[int, PackedInt32Array] = {}
	for peer: int in game.state.present_peers():
		table[peer] = game.speakers_for(peer)
	var still_out := {}
	for peer: int in _leaving:
		still_out[peer] = true
	for peer: int in _disconnected:
		still_out[peer] = true
	_relay.refresh(table, still_out)


func _check_deadlines() -> void:
	var late: Array[int] = []
	for peer: int in _peers:
		var info := _peers[peer]
		if peer == NetTransport.HOST_ID or info.welcomed:
			continue
		if _now_usec - info.joined_usec > hello_deadline_usec:
			late.append(peer)
	for peer: int in late:
		_disconnect(peer)


## Whether a message may go to `peer` now: not disconnected by this session, no leave pending.
func _reachable(peer: int) -> bool:
	return not _disconnected.has(peer) and not _leaving.has(peer)


func _send(peer: int, kind: int, payload: PackedByteArray) -> Error:
	var sent := _transport.send(peer, kind, payload)
	# A peer that is gone between the transport's word and core/'s is expected, not an error.
	if sent != OK and sent != ERR_DOES_NOT_EXIST:
		push_error("host: cannot send kind %d to peer %d: %s" % [kind, peer, error_string(sent)])
	return sent


func _disconnect(peer: int) -> void:
	if peer == NetTransport.HOST_ID or _disconnected.has(peer):
		return
	_peers.erase(peer)
	_relay.leave(peer)
	# Only a disconnect the transport accepted brings a peer_left that clears the mark.
	if _transport.disconnect_peer(peer) == OK:
		_disconnected[peer] = true


func _end(reason: StringName) -> void:
	if _ended:
		return
	_ended = true
	end_reason = reason
	if reason != CLOSED:
		push_error("host: the session ended (%s): %s" % [reason, "; ".join(errors)])
	if _debug and _started and not replay_dir.is_empty():
		replay_path = ReplayFiles.write(game.command_log, replay_dir)
	_transport.close()
	ended.emit(reason)


func _on_peer_joined(peer: int) -> void:
	_queue.append(MatchCommand.new(Intents.PEER_CONNECTED, peer, 0))
	_peers[peer] = _Peer.new(_now_usec)


func _on_peer_left(peer: int) -> void:
	_queue.append(MatchCommand.new(Intents.PEER_LEFT, peer, 0))
	_leaving[peer] = _leaving.get(peer, 0) + 1
	_disconnected.erase(peer)
	_peers.erase(peer)
	_relay.leave(peer)


func _on_packet(peer: int, kind: int, payload: PackedByteArray) -> void:
	var info: _Peer = _peers.get(peer)
	var row := _schema.row(kind)
	if info == null or row == null:
		return
	if peer != NetTransport.HOST_ID and not _within_budget(info, row, payload.size()):
		over_budget += 1
		if row.lane == NetKindTable.Lane.VOICE:
			voice_over_budget += 1
		_transport.count_rejected(peer, NetRejects.Reason.OVER_BUDGET)
		return
	# A debug kind from anyone but peer 1 in a debug build is malformed and never decoded (E17).
	var debug_kind := kind >= WireSchema.FIRST_DEBUG and kind < WireSchema.FIRST_EVENT
	var message: WireMessage = null
	if not debug_kind or (peer == NetTransport.HOST_ID and _debug):
		message = _schema.decode(kind, payload)
	if message == null:
		bad_payloads += 1
		_transport.count_rejected(peer, NetRejects.Reason.BAD_PAYLOAD)
		_malformed(peer, "debug_kind" if debug_kind else "bad_payload")
		return
	if row.lane == NetKindTable.Lane.VOICE:
		_relay.hold(peer, message.fields["seq"] as int, message.fields["opus"] as PackedByteArray)
		return
	# A debug kind names its player in `peer` (E17); every other command is its sender's.
	var sender := message.peer if debug_kind else peer
	_queue.append(MatchCommand.new(message.name, sender, 0, message.fields, message.seq))


func _on_rejected(peer: int, reason: NetRejects.Reason) -> void:
	var reason_name: String = NetRejects.Reason.find_key(reason)
	_malformed(peer, reason_name.to_lower())


func _within_budget(info: _Peer, row: WireRow, size: int) -> bool:
	match row.lane:
		NetKindTable.Lane.VOICE:
			return info.budget.take_voice()
		NetKindTable.Lane.RELIABLE:
			return info.budget.take_intent(size)
	return info.budget.take_bytes(size)


## Counts one rejected message of `peer`; at MALFORMED_LIMIT within the window it is disconnected
## with one log line, or, for the host's own client, the session ends after the poll.
func _malformed(peer: int, reason: String) -> void:
	var info: _Peer = _peers.get(peer)
	if info == null:
		return  # not connected, or disconnected already
	while not info.malformed.is_empty() and info.malformed[0] <= _now_usec - MALFORMED_WINDOW_USEC:
		info.malformed.pop_front()
		info.reasons.pop_front()
	info.malformed.append(_now_usec)
	info.reasons.append(reason)
	if info.malformed.size() < MALFORMED_LIMIT:
		return
	var counts: Dictionary[String, int] = {}
	for each: String in info.reasons:
		counts[each] = counts.get(each, 0) + 1
	var why := PackedStringArray()
	for each: String in counts:
		why.append("%s x%d" % [each, counts[each]])
	var line := (
		"peer %d sent %d malformed messages within %d s (%s)"
		% [
			peer,
			info.malformed.size(),
			MALFORMED_WINDOW_SECONDS,
			", ".join(why),
		]
	)
	if peer == NetTransport.HOST_ID:
		errors.append("the host's own client is broken: %s" % line)
		_end_after_poll = OWN_CLIENT_MALFORMED
		info.malformed.clear()
		info.reasons.clear()
		return
	push_warning("host: disconnected %s" % line)
	malformed_disconnects += 1
	_disconnect(peer)
