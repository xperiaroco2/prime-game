class_name NetTransport
extends RefCounted
## How game code hosts, joins and exchanges messages with peers, whatever carries the bytes
## (docs/decisions/2026-09-29-listen-server-and-message-layer.md). EnetTransport carries them over
## the network; LoopbackTransport inside one process: the host's own client, and whole matches in
## headless tests. Nothing outside net/ touches ENet.
##
## A message is a kind from the NetKindTable plus an opaque payload. Every backend hands received
## packets to receive_bytes(): one framing and one defensive decode for every peer, the host's own
## client included. The owner calls poll() every frame, and signals fire only from poll().
## The host is peer HOST_ID and plays: its own client is peer HOST_ID too. Clients reach only the
## host, never each other.
##
## The LATEST lane delivers at most one message per sender and kind per poll between two of that
## sender's reliable messages: its newest. After a peer's main thread froze (about 5 s in #21), its
## backlog arrives in one poll, 50 to 100 packets each about 5 s old; the inbox drops every valid
## LATEST message that a newer one of the same kind from the same peer follows in the same poll with
## no valid reliable message from that peer between them (counted in latest_superseded), so no
## consumer handles the backlog, and each reliable message still follows the state sent before it.
## RELIABLE and VOICE messages are all delivered.

signal connected(own_id: int)
## A join failed: no host, refused, full, or no answer within the join timeout.
signal connect_failed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## The one signal for "the host is gone": it closed, crashed or timed out. The match is over for
## this client (ADR); the transport is closed and can join again.
signal host_lost
signal packet_received(from_peer: int, kind: int, payload: PackedByteArray)

enum Role { IDLE, HOST, CLIENT }

const HOST_ID := 1
## At most one summary line of rejected packets per interval, so one peer cannot flood the log.
const REJECT_SUMMARY_INTERVAL_MS := 10000

var rejects := NetRejects.new()
## Valid LATEST messages dropped because a newer one of the same kind from the same peer came in
## the same poll, with no reliable message from that peer between. Not rejects: nothing was wrong
## with them.
var latest_superseded := 0

var _kinds: NetKindTable
var _role := Role.IDLE
var _own_id := 0
## Host: the connected clients, its own included. Client: HOST_ID once connected.
var _peers: Dictionary[int, bool] = {}
var _refusing := false
## Host: in-process clients by peer id (LoopbackTransport); they receive through their inbox.
var _links: Dictionary[int, NetTransport] = {}
## In-process client: its host. Weak, so a host and its clients form no reference cycle.
var _link_host: WeakRef = null
## What happened since the last poll(), in order: arrivals, packets, departures.
var _inbox: Array[Inbound] = []
var _first_pending_reject_ms := -1
## Counts closes, so a drain notices a handler that closed and hosted or joined again.
var _session := 0


class Inbound:
	enum Type { PACKET, JOINED, LEFT, DISCONNECTED, CONNECTED, CONNECT_FAILED, HOST_LOST }

	var type: Type
	var peer: int
	var bytes: PackedByteArray
	var channel: int
	var mode: MultiplayerPeer.TransferMode

	func _init(
		item_type: Type,
		peer_id: int,
		packet := PackedByteArray(),
		packet_channel := 0,
		packet_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE,
	) -> void:
		type = item_type
		peer = peer_id
		bytes = packet
		channel = packet_channel
		mode = packet_mode


func _init(kinds: NetKindTable) -> void:
	_kinds = kinds


func kind_table() -> NetKindTable:
	return _kinds


## Starts hosting; this side becomes peer HOST_ID. max_clients counts remote clients only.
func host(port: int, max_clients: int) -> Error:
	if _role != Role.IDLE:
		return ERR_ALREADY_IN_USE
	_inbox.clear()
	var err := _backend_host(port, max_clients)
	if err == OK:
		_role = Role.HOST
		_own_id = HOST_ID
	return err


## Starts joining. OK means the attempt started: connected or connect_failed follows from poll().
func join(address: String, port: int) -> Error:
	if _role != Role.IDLE:
		return ERR_ALREADY_IN_USE
	_inbox.clear()
	_role = Role.CLIENT
	var err := _backend_join(address, port)
	if err != OK:
		_reset()
	return err


func poll() -> void:
	if _role == Role.CLIENT and _link_host != null and _link_host.get_ref() == null:
		_link_host = null
		_push(Inbound.new(Inbound.Type.HOST_LOST, HOST_ID))
	if _role != Role.IDLE:
		_backend_poll()
	_drain_inbox()
	_log_rejects(false)


## Sends a message to one connected peer (a client sends only to HOST_ID). The kind's row decides
## the lane. ERR_DOES_NOT_EXIST: not a connected peer. ERR_INVALID_PARAMETER: this side may not
## send the kind, or the payload is over its cap.
func send(to_peer: int, kind: int, payload: PackedByteArray) -> Error:
	# Positive only: a MultiplayerPeer reads 0 as everyone and -n as everyone but n.
	if to_peer < HOST_ID or not _peers.has(to_peer):
		return ERR_DOES_NOT_EXIST
	var from_host := _role == Role.HOST
	if not _kinds.allows(kind, from_host) or payload.size() > _kinds.payload_cap(kind):
		return ERR_INVALID_PARAMETER
	var bytes := NetFrame.encode(kind, payload)
	var lane := _kinds.lane_of(kind)
	if from_host and _links.has(to_peer):
		_links[to_peer]._push_packet(HOST_ID, bytes, lane)
		return OK
	if not from_host and _link_host != null:
		var host_side := _link_host.get_ref() as NetTransport
		if host_side == null:
			return ERR_CONNECTION_ERROR
		host_side._push_packet(_own_id, bytes, lane)
		return OK
	return _backend_send(to_peer, bytes, lane)


## Stops hosting or leaves. Emits nothing on this side; the peers learn it from their poll().
func close() -> void:
	if _role == Role.HOST:
		for client: NetTransport in _links.values():
			client._push(Inbound.new(Inbound.Type.HOST_LOST, HOST_ID))
	elif _link_host != null:
		var host_side := _link_host.get_ref() as NetTransport
		if host_side != null:
			host_side._push(Inbound.new(Inbound.Type.LEFT, _own_id))
	if _role != Role.IDLE:
		_backend_close()
	_reset()
	_log_rejects(true)


func own_id() -> int:
	return _own_id


func role() -> Role:
	return _role


func is_host() -> bool:
	return _role == Role.HOST


## Host: the connected clients, its own included. Client: [HOST_ID] once connected.
func peers() -> PackedInt32Array:
	var ids := PackedInt32Array(_peers.keys())
	ids.sort()
	return ids


## Host: refuse new joins, for example during a match (ADR). The host's own client is exempt.
func set_refuse_new_connections(refuse: bool) -> void:
	_refusing = refuse


func is_refusing_new_connections() -> bool:
	return _refusing


## Host: disconnects a client, for example one that missed the loading deadline (ARCHITECTURE
## §3). It leaves peers() and send() at once; peer_left follows on the next poll(), like any
## leave, and the client sees host_lost. ERR_UNAVAILABLE when not hosting, ERR_INVALID_PARAMETER
## for the host's own client (the host ends the session instead), ERR_DOES_NOT_EXIST for a peer
## that is not connected.
func disconnect_peer(peer_id: int) -> Error:
	if _role != Role.HOST:
		return ERR_UNAVAILABLE
	if peer_id == HOST_ID:
		return ERR_INVALID_PARAMETER
	if not _peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	_peers.erase(peer_id)
	if _links.has(peer_id):
		_links[peer_id]._push(Inbound.new(Inbound.Type.HOST_LOST, HOST_ID))
		_links.erase(peer_id)
	else:
		_backend_disconnect(peer_id)
	_push(Inbound.new(Inbound.Type.DISCONNECTED, peer_id))
	return OK


## The one decode path: every backend hands each received packet here, the loopback included, so
## the host's own client decodes exactly what a remote client would. Only the inbox (from poll())
## and tests call it; game code never does, because signals fire only from poll(). Each call
## delivers its packet: the LATEST lane's newest-only rule belongs to the inbox, which sees a whole
## poll's packets.
func receive_bytes(
	from_peer: int, bytes: PackedByteArray, channel: int, mode: MultiplayerPeer.TransferMode
) -> void:
	var frame := _decoded(from_peer, bytes, channel, mode)
	if frame != null:
		packet_received.emit(from_peer, frame.kind, frame.payload)


# Backends override these. Each _backend_* runs only in the matching role.
func _backend_host(_port: int, _max_clients: int) -> Error:
	return ERR_UNAVAILABLE


func _backend_join(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


## Pushes what happened since the last poll into the inbox (_push).
func _backend_poll() -> void:
	pass


func _backend_send(_to_peer: int, _bytes: PackedByteArray, _lane: NetKindTable.Lane) -> Error:
	return ERR_UNAVAILABLE


func _backend_close() -> void:
	pass


func _backend_disconnect(_peer_id: int) -> void:
	pass


## Host side: links an in-process client as peer_id. Both sides learn it from their next poll().
func _link(client: NetTransport, peer_id: int) -> void:
	_links[peer_id] = client
	client._role = Role.CLIENT
	client._link_host = weakref(self)
	client._push(Inbound.new(Inbound.Type.CONNECTED, peer_id))
	_push(Inbound.new(Inbound.Type.JOINED, peer_id))


func _push(item: Inbound) -> void:
	if _role != Role.IDLE:
		_inbox.append(item)


func _push_packet(from_peer: int, bytes: PackedByteArray, lane: NetKindTable.Lane) -> void:
	_push(
		Inbound.new(
			Inbound.Type.PACKET,
			from_peer,
			bytes,
			NetKindTable.channel_of(lane),
			NetKindTable.mode_of(lane)
		)
	)


func _drain_inbox() -> void:
	# What a handler pushes meanwhile, even to this transport, waits for the next poll.
	var batch := _inbox
	_inbox = []
	var superseded := _superseded_in(batch)
	var session := _session
	for i in batch.size():
		# A handler closed this transport, and may have hosted or joined again: the rest of the
		# batch belongs to the old session.
		if _session != session:
			return
		var item := batch[i]
		match item.type:
			Inbound.Type.PACKET:
				if not superseded.has(i):
					receive_bytes(item.peer, item.bytes, item.channel, item.mode)
				elif _decoded(item.peer, item.bytes, item.channel, item.mode) != null:
					# Still checked like any packet, so what is rejected stays counted.
					latest_superseded += 1
			Inbound.Type.JOINED:
				if _role == Role.HOST and not _peers.has(item.peer):
					_peers[item.peer] = true
					peer_joined.emit(item.peer)
			Inbound.Type.LEFT:
				_links.erase(item.peer)
				if _role == Role.HOST and _peers.erase(item.peer):
					peer_left.emit(item.peer)
			Inbound.Type.DISCONNECTED:
				# The host disconnected it: already gone from _peers, so its own LEFT is ignored.
				if _role == Role.HOST:
					peer_left.emit(item.peer)
			Inbound.Type.CONNECTED:
				if _role == Role.CLIENT and not _peers.has(HOST_ID):
					_own_id = item.peer
					_peers[HOST_ID] = true
					connected.emit(_own_id)
			Inbound.Type.CONNECT_FAILED:
				if _role == Role.CLIENT and not _peers.has(HOST_ID):
					_end_client(connect_failed)
			Inbound.Type.HOST_LOST:
				if _role == Role.CLIENT:
					_end_client(host_lost if _peers.has(HOST_ID) else connect_failed)


## The batch indices of the LATEST packets a newer one supersedes: each valid LATEST message that a
## later valid one of the same kind from the same peer follows. Between them, a valid RELIABLE
## message from that peer separates the two, so each of its intents or events is still handled
## after the LATEST state it sent just before it (a Use is checked against the claim sent before
## it, not against the one from before a freeze); so does a join or leave of that peer (two
## connections, maybe with the same id), and so does any change of this client's own connection.
## Voice has its own unordered channel and separates nothing. Invalid packets separate and
## supersede nothing; the drain rejects them.
func _superseded_in(batch: Array[Inbound]) -> Dictionary[int, bool]:
	var superseded: Dictionary[int, bool] = {}
	# (peer, kind) of the LATEST messages later in the batch, walking it backwards.
	var newer: Dictionary[Vector2i, bool] = {}
	for i in range(batch.size() - 1, -1, -1):
		var item := batch[i]
		match item.type:
			Inbound.Type.PACKET:
				var lane_kind := _peeked(item)
				if lane_kind.x == NetKindTable.Lane.RELIABLE:
					_forget_newer_of(newer, item.peer)
				elif lane_kind.x == NetKindTable.Lane.LATEST:
					var key := Vector2i(item.peer, lane_kind.y)
					if newer.has(key):
						superseded[i] = true
					else:
						newer[key] = true
			Inbound.Type.JOINED, Inbound.Type.LEFT, Inbound.Type.DISCONNECTED:
				_forget_newer_of(newer, item.peer)
			_:
				newer.clear()
	return superseded


static func _forget_newer_of(newer: Dictionary[Vector2i, bool], peer_id: int) -> void:
	for key: Vector2i in newer.keys():
		if key.x == peer_id:
			newer.erase(key)


## (lane, kind) of a packet that decodes as a valid message, else (-1, 0). Counts nothing: the
## drain decodes every packet again and counts its rejects.
func _peeked(item: Inbound) -> Vector2i:
	var frame := NetFrame.decode(item.bytes, _kinds, _role == Role.CLIENT, item.channel, item.mode)
	if frame.reject != NetRejects.Reason.NONE:
		return Vector2i(-1, 0)
	return Vector2i(_kinds.lane_of(frame.kind), frame.kind)


## The frame of a packet from a connected peer, or null after counting why it is rejected.
func _decoded(
	from_peer: int, bytes: PackedByteArray, channel: int, mode: MultiplayerPeer.TransferMode
) -> NetFrame:
	if not _peers.has(from_peer):
		_count_reject(from_peer, NetRejects.Reason.UNKNOWN_PEER)
		return null
	var frame := NetFrame.decode(bytes, _kinds, _role == Role.CLIENT, channel, mode)
	if frame.reject != NetRejects.Reason.NONE:
		_count_reject(from_peer, frame.reject)
		return null
	return frame


func _end_client(outcome: Signal) -> void:
	_backend_close()
	_reset()
	_log_rejects(true)
	outcome.emit()


func _reset() -> void:
	_session += 1
	_role = Role.IDLE
	_own_id = 0
	_peers.clear()
	_links.clear()
	_link_host = null
	_inbox.clear()
	_refusing = false


func _count_reject(peer_id: int, reason: NetRejects.Reason) -> void:
	rejects.count(peer_id, reason)
	if _first_pending_reject_ms < 0:
		_first_pending_reject_ms = Time.get_ticks_msec()


func _log_rejects(now: bool) -> void:
	if rejects.pending() == 0:
		return
	if not now and Time.get_ticks_msec() - _first_pending_reject_ms < REJECT_SUMMARY_INTERVAL_MS:
		return
	push_warning(rejects.take_summary())
	_first_pending_reject_ms = -1
