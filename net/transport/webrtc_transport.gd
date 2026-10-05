class_name WebRtcTransport
extends NetTransport
## NetTransport over WebRTC data channels (the M6 design §2.1 to §2.3 and §2.6; E48, E50, E54):
## a star, never a mesh. The host holds one WebRTCPeerConnection per client and reads it directly
## (no WebRTCMultiplayerPeer, E48); clients reach only the host. The host's own client is a
## LoopbackTransport, as on every backend.
##
## Signalling goes through a Signaller to the service at signal_url (the Worker, or a
## LanSignalling on the LAN and in every headless test). host() opens a room there (room_code()
## once room_opened fires); join(code, _) joins the room with that code. Per joiner the host
## assigns the next peer id (2 upward, never reused in a session), offers, and takes one answer
## per offer; the joiner applies one offer per attempt. Half-made connections count against the
## maximum, and a host refusing joins answers no joiner and tells the service the room is closed.
##
## Each connection has three negotiated data channels, one per lane (CHANNEL_IDS): RELIABLE
## (reliable, ordered), LATEST and VOICE (unordered, no resend). LATEST packets carry LaneOrder's
## header, so they keep ENet's order against RELIABLE (§2.2). Once the channels are open the host
## sends ADMIT on RELIABLE, a kind-0 frame whose payload is the client's peer id (u32); the client
## learns its id there and refuses one of HOST_ID or less.
##
## WebRTC's own keepalives never reach the main thread, so a hung game would stay "connected":
## poll() sends each peer KEEPALIVE on VOICE when nothing went to it for KEEPALIVE_MS, and a peer
## heard from for SILENCE_MS (backlog drained first) leaves, as does a connection that reaches
## FAILED or CLOSED, or a channel that closes under a live connection. DISCONNECTED is transient.
## Nothing is ever written to a channel that is not open: that prints an engine error (M6-1).

## Host: the service made the room; its code is what friends type.
signal room_opened(code: String)

## The data channel of each lane: negotiated with these ids on both sides (no
## data_channel_received race), LATEST and VOICE unordered with no resend.
const CHANNEL_IDS: Dictionary[NetKindTable.Lane, int] = {
	NetKindTable.Lane.RELIABLE: 1,
	NetKindTable.Lane.LATEST: 2,
	NetKindTable.Lane.VOICE: 3,
}
## Nothing went to a peer for this long: poll() sends it KEEPALIVE (a placeholder, §2.6).
const KEEPALIVE_MS := 1000
## The empty kind-0 frame, sent on VOICE and consumed before the inbox; any other kind-0 packet
## reaches the inbox and is rejected there (no kind table allows kind 0).
const KEEPALIVE: Array[int] = [0, 0, 0]
## Nothing heard from a peer for this long, keepalives included, is a leave (§2.6): past a 5.2 s
## freeze and WebRTC's own 12.8 s on loopback, and LaneOrder's stall rule uses it too.
const SILENCE_MS := 20000
## A join whose channels are not open this long after it started gives up (E54, a placeholder);
## the host closes a half-made connection after as long.
const JOIN_TIMEOUT_MS := 15000
## disconnect_peer: the connection closes once the client closed its side, or after this long.
const CLOSE_WAIT_MS := 5000
## take_upload's cost of one packet beyond its bytes (E56, M6-1): 57 B of SCTP and DTLS, 48 B of
## IPv6 and UDP, and at most 3 B of padding. Over IPv4 it errs high by at most 23 B.
const PACKET_OVERHEAD_BYTES := 108
## ADMIT: the 3-byte frame header of kind 0 with a 4-byte payload, the peer id.
const ADMIT_BYTES := NetFrame.HEADER_BYTES + 4

## The signalling service: ws://host:port for a LanSignalling, wss:// for the Worker.
var signal_url := ""
## Host: what `open` tells the service (advisory to joiners, the M6 design §2.5).
var room_protocol := 0
var room_content := 0
## Tests: only IPv4 host candidates are signalled, rewritten to 127.0.0.1, so every packet stays
## on the loopback (the container's own address works too, but tests keep off the network).
var local_candidates := false
## Joiner: the host's protocol and content hash from the service's `found` (advisory, §2.5), -1
## before it.
var found_protocol := -1
var found_content := 0

var _signaller: Signaller = null
var _order := LaneOrder.new()
var _faults: FaultShim = null
## Host: every connection by peer id, half-made and closing ones included. Client: its one
## connection under HOST_ID.
var _conns: Dictionary[int, Conn] = {}
## Host: the service's joiner number -> its peer id.
var _by_joiner: Dictionary[int, int] = {}
var _next_peer_id := HOST_ID + 1
var _max_clients := 0
var _room_code := ""
var _ice_servers: Array = []
## Client: when join() started, whether the service ever answered, the id ADMIT gave.
var _join_started_ms := 0
var _signal_opened := false
var _client_id := 0


## One connection and what the backend knows about it.
class Conn:
	extends RefCounted
	var peer_id := 0
	## Host: the service's number for the joiner. Client: 0.
	var joiner := 0
	var pc: WebRTCPeerConnection
	var channels: Dictionary[NetKindTable.Lane, WebRTCDataChannel] = {}
	var started_ms := 0
	## Host: an answer was applied. Client: the offer was.
	var described := false
	## Every channel opened: the host sent ADMIT, the client waits for it.
	var open := false
	## Client: ADMIT read.
	var admitted := false
	## Host: disconnect_peer was called at this time; -1 otherwise.
	var closing_since_ms := -1
	var reliable_closed := false
	var last_sent_ms := 0
	var last_heard_ms := 0
	## The fault shim's RELIABLE packets still on their way, oldest first, with their due times.
	var delayed: Array[PackedByteArray] = []
	var delayed_due: PackedInt64Array = PackedInt64Array()

	func all_channels_open() -> bool:
		for channel: WebRTCDataChannel in channels.values():
			if channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
				return false
		return true

	func state() -> WebRTCPeerConnection.ConnectionState:
		return pc.get_connection_state()

	func ended() -> bool:
		var now_state := state()
		return (
			now_state == WebRTCPeerConnection.STATE_FAILED
			or now_state == WebRTCPeerConnection.STATE_CLOSED
		)


## Test-only faults on what this side receives (the M6 design §5, M6-6), debug builds only and off
## by default: 127.0.0.1 almost never reorders across channels. RELIABLE packets arrive
## reliable_delay_ms late, in order (one of them delay_once_ms late instead, holding back the ones
## behind it, as SCTP would); LATEST packets are dropped and duplicated at the given rates.
class FaultShim:
	extends RefCounted
	var reliable_delay_ms := 0
	var latest_drop := 0.0
	var latest_duplicate := 0.0
	var rng := RandomNumberGenerator.new()
	var _delay_once_ms := 0

	func _init(seed_value: int) -> void:
		rng.seed = seed_value

	## The next RELIABLE packet received arrives this late.
	func delay_next_reliable(ms: int) -> void:
		_delay_once_ms = ms

	func reliable_delay() -> int:
		if _delay_once_ms > 0:
			var once := _delay_once_ms
			_delay_once_ms = 0
			return once
		return reliable_delay_ms

	## How many copies of a received LATEST packet arrive: 0, 1 or 2.
	func latest_copies() -> int:
		if latest_drop > 0.0 and rng.randf() < latest_drop:
			return 0
		return 2 if latest_duplicate > 0.0 and rng.randf() < latest_duplicate else 1


## Turns the fault shim on (null: off). ERR_UNAVAILABLE in a release build.
func use_faults(shim: FaultShim) -> Error:
	if not OS.is_debug_build():
		return ERR_UNAVAILABLE
	_faults = shim
	return OK


## Host: the room's code once room_opened fired, else "".
func room_code() -> String:
	return _room_code


## Host: also closes or reopens the room at the service, so a code typed while the match runs is
## answered "the match has started".
func set_refuse_new_connections(refuse: bool) -> void:
	var changed := refuse != is_refusing_new_connections()
	super(refuse)
	if changed and is_host() and _signaller != null:
		if refuse:
			_signaller.close_room()
		else:
			_signaller.reopen_room()


func _backend_host(_port: int, max_clients: int) -> Error:
	if signal_url.is_empty():
		return ERR_UNCONFIGURED
	if max_clients < 1 or max_clients > SignalCodec.MAX_JOINERS:
		return ERR_INVALID_PARAMETER
	var err := _open_signaller()
	if err != OK:
		return err
	_max_clients = max_clients
	_next_peer_id = HOST_ID + 1
	_signaller.open_room(room_protocol, room_content, max_clients)
	return OK


## `address` is the room's code; the port is unused (the service is at signal_url).
func _backend_join(address: String, _port: int) -> Error:
	if signal_url.is_empty():
		return ERR_UNCONFIGURED
	if not SignalCodec.is_code(address):
		return ERR_INVALID_PARAMETER
	var err := _open_signaller()
	if err != OK:
		return err
	_join_started_ms = Time.get_ticks_msec()
	_signaller.join_room(address)
	return OK


func _backend_poll() -> void:
	if _signaller != null:
		_signaller.poll()
	var now := Time.get_ticks_msec()
	for peer_id: int in _conns.keys():
		if _conns.has(peer_id):
			_step_connection(_conns[peer_id], now)
	for peer_id: int in _conns.keys():
		if _conns.has(peer_id):
			_read(_conns[peer_id], now)
	_judge(now)
	for conn: Conn in _conns.values():
		if _is_live(conn) and now - conn.last_sent_ms >= KEEPALIVE_MS:
			_put(conn, NetKindTable.Lane.VOICE, PackedByteArray(KEEPALIVE))


func _backend_send(to_peer: int, bytes: PackedByteArray, lane: NetKindTable.Lane) -> Error:
	var conn: Conn = _conns.get(to_peer if is_host() else HOST_ID)
	if conn == null or not _is_live(conn):
		return ERR_DOES_NOT_EXIST
	return _put(conn, lane, bytes)


func _backend_close() -> void:
	var signaller := _signaller
	_signaller = null  # its signals' handlers ignore anything from now on
	if signaller != null:
		signaller.close()
	for conn: Conn in _conns.values():
		conn.pc.close()
	_conns.clear()
	_by_joiner.clear()
	_order.clear()
	_room_code = ""
	_ice_servers = []
	_client_id = 0
	_signal_opened = false
	found_protocol = -1
	found_content = 0


## The reason was sent before this call; poll() closes the RELIABLE channel next, then the
## connection. Held LATEST packets are discarded at once, and nothing more goes to the peer.
func _backend_disconnect(peer_id: int) -> void:
	var conn: Conn = _conns.get(peer_id)
	if conn != null and conn.closing_since_ms < 0:
		conn.closing_since_ms = Time.get_ticks_msec()
		_order.forget(peer_id)


func _open_signaller() -> Error:
	var signaller := Signaller.new()
	var err := signaller.connect_to(signal_url)
	if err != OK:
		return err
	_signaller = signaller
	# Bound methods, not lambdas: a lambda capturing self, held by an object self owns, is a cycle.
	signaller.opened.connect(_on_signal_opened)
	signaller.closed.connect(_on_signal_closed)
	signaller.refused.connect(_on_refused)
	signaller.room_opened.connect(_on_room_opened)
	signaller.joiner_arrived.connect(_on_joiner_arrived)
	signaller.answer_received.connect(_on_answer)
	signaller.candidate_received.connect(_on_candidate)
	signaller.room_found.connect(_on_room_found)
	signaller.offer_received.connect(_on_offer)
	return OK


## A new connection with the three channels, registered under `key`; null when WebRTC is missing
## (the extension did not load: create_data_channel gives null).
func _new_connection(key: int, joiner: int, ice_servers: Array) -> Conn:
	var conn := Conn.new()
	conn.peer_id = key
	conn.joiner = joiner
	conn.pc = WebRTCPeerConnection.new()
	if conn.pc.initialize({"iceServers": ice_servers}) != OK:
		return null
	for lane: NetKindTable.Lane in CHANNEL_IDS:
		var options := {"negotiated": true, "id": CHANNEL_IDS[lane]}
		if lane != NetKindTable.Lane.RELIABLE:
			options["ordered"] = false
			options["maxRetransmits"] = 0
		var channel := conn.pc.create_data_channel(str(NetKindTable.Lane.find_key(lane)), options)
		if channel == null:
			conn.pc.close()
			return null
		channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
		conn.channels[lane] = channel
	conn.started_ms = Time.get_ticks_msec()
	conn.last_sent_ms = conn.started_ms
	conn.last_heard_ms = conn.started_ms
	_conns[key] = conn
	conn.pc.session_description_created.connect(_on_description.bind(key))
	conn.pc.ice_candidate_created.connect(_on_local_candidate.bind(key))
	return conn


## Polls a connection and follows its state: the channels opening (the host admits), the join
## timeout, the end of the connection, and a host closing a peer.
func _step_connection(conn: Conn, now: int) -> void:
	conn.pc.poll()
	for channel: WebRTCDataChannel in conn.channels.values():
		channel.poll()
	if conn.closing_since_ms >= 0:
		_step_closing(conn, now)
		return
	if conn.ended():
		_lose(
			conn,
			JOIN_UNREACHABLE if conn.state() == WebRTCPeerConnection.STATE_FAILED else JOIN_FAILED
		)
	elif not conn.open:
		if conn.state() == WebRTCPeerConnection.STATE_CONNECTED and conn.all_channels_open():
			_opened(conn, now)
		elif now - conn.started_ms > JOIN_TIMEOUT_MS:
			_lose(conn, JOIN_UNREACHABLE)


func _opened(conn: Conn, now: int) -> void:
	conn.open = true
	conn.last_heard_ms = now
	if not is_host():
		_order.add_peer(HOST_ID)  # before ADMIT, which it counts
		return
	if is_refusing_new_connections():
		_drop(conn)
		return
	_order.add_peer(conn.peer_id)
	var admit := NetFrame.encode(0, PackedByteArray())
	admit.encode_u16(1, 4)
	admit.resize(ADMIT_BYTES)
	admit.encode_u32(NetFrame.HEADER_BYTES, conn.peer_id)
	if _put(conn, NetKindTable.Lane.RELIABLE, admit) != OK:
		_drop(conn)
		return
	_push(Inbound.new(Inbound.Type.JOINED, conn.peer_id))


## Host: a peer under disconnect_peer. Its channels are drained and discarded until CLOSED; the
## RELIABLE channel closes once what went before is out, then the connection once the client
## closed its side or CLOSE_WAIT_MS passed.
func _step_closing(conn: Conn, now: int) -> void:
	var reliable := conn.channels[NetKindTable.Lane.RELIABLE]
	if not conn.reliable_closed and reliable.get_buffered_amount() == 0:
		conn.reliable_closed = true
		reliable.close()
	var other_closed := false
	for lane: NetKindTable.Lane in [NetKindTable.Lane.LATEST, NetKindTable.Lane.VOICE]:
		if conn.channels[lane].get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			other_closed = true
	if conn.ended() or other_closed or now - conn.closing_since_ms > CLOSE_WAIT_MS:
		_drop(conn)


## Reads every channel of a connection: LATEST before RELIABLE, so a LATEST packet sent before a
## reliable one comes first, as ENet delivers it (§2.2).
func _read(conn: Conn, now: int) -> void:
	if not conn.open:
		return
	var closing := conn.closing_since_ms >= 0
	for lane: NetKindTable.Lane in [
		NetKindTable.Lane.LATEST, NetKindTable.Lane.RELIABLE, NetKindTable.Lane.VOICE
	]:
		var channel := conn.channels[lane]
		while channel.get_available_packet_count() > 0:
			var bytes := channel.get_packet()
			conn.last_heard_ms = now
			if closing:
				continue
			match lane:
				NetKindTable.Lane.LATEST:
					var copies := 1 if _faults == null else _faults.latest_copies()
					for _i in copies:
						_take_latest(conn, bytes, now)
				NetKindTable.Lane.RELIABLE:
					if _faults == null:
						_take_reliable(conn, bytes, now)
					else:
						_delay_reliable(conn, bytes, now)
				NetKindTable.Lane.VOICE:
					if bytes != PackedByteArray(KEEPALIVE):
						_push_packet(conn.peer_id, bytes, lane)
			if not _conns.has(conn.peer_id):
				return  # a bad ADMIT ended the join
	_release_delayed(conn, now)


func _take_latest(conn: Conn, bytes: PackedByteArray, now: int) -> void:
	var read := _order.read_latest(conn.peer_id, bytes, now)
	if read.verdict == LaneOrder.Verdict.REJECTED:
		var rejected := Inbound.new(Inbound.Type.REJECTED, conn.peer_id)
		rejected.reject = read.reject
		_push(rejected)
		return
	for frame: PackedByteArray in read.superseded:
		_push_packet(conn.peer_id, frame, NetKindTable.Lane.LATEST, Inbound.Type.SUPERSEDED)
	if read.verdict == LaneOrder.Verdict.DELIVERED:
		_push_packet(conn.peer_id, read.frame, NetKindTable.Lane.LATEST)


## A RELIABLE packet, counted by LaneOrder before any decoding; the held LATEST frames it releases
## go to the inbox right after it. A client's first one must be ADMIT.
func _take_reliable(conn: Conn, bytes: PackedByteArray, now: int) -> void:
	var released := _order.read_reliable(conn.peer_id, now)
	if not is_host() and not conn.admitted:
		var id := _admitted_id(bytes)
		if id <= HOST_ID:
			_lose(conn, JOIN_FAILED)
			return
		conn.admitted = true
		_client_id = id
		_push(Inbound.new(Inbound.Type.CONNECTED, id))
		# The service is done with this join: leaving frees the joiner's place in the room.
		if _signaller != null:
			_signaller.close()
	else:
		_push_packet(conn.peer_id, bytes, NetKindTable.Lane.RELIABLE)
	for frame: PackedByteArray in released:
		_push_packet(conn.peer_id, frame, NetKindTable.Lane.LATEST)


## The peer id an ADMIT carries, or 0 for anything else.
static func _admitted_id(bytes: PackedByteArray) -> int:
	if bytes.size() != ADMIT_BYTES or bytes[0] != 0 or bytes.decode_u16(1) != 4:
		return 0
	return bytes.decode_u32(NetFrame.HEADER_BYTES)


func _delay_reliable(conn: Conn, bytes: PackedByteArray, now: int) -> void:
	var due := now + _faults.reliable_delay()
	if not conn.delayed_due.is_empty():
		due = maxi(due, conn.delayed_due[conn.delayed_due.size() - 1])
	conn.delayed.append(bytes)
	conn.delayed_due.append(due)


func _release_delayed(conn: Conn, now: int) -> void:
	while not conn.delayed.is_empty() and conn.delayed_due[0] <= now and _conns.has(conn.peer_id):
		var bytes: PackedByteArray = conn.delayed.pop_front()
		conn.delayed_due.remove_at(0)
		_take_reliable(conn, bytes, now)


## After every connection was read: the silence rule, a channel closed under a live connection,
## and LaneOrder's stalled peers.
func _judge(now: int) -> void:
	for conn: Conn in _conns.values():
		if not _is_live(conn):
			continue
		if now - conn.last_heard_ms > SILENCE_MS:
			_lose(conn, JOIN_UNREACHABLE)
		elif not conn.all_channels_open():
			# The host closing a client's RELIABLE channel is how it ends that client: no fault.
			if is_host():
				_note_reject(conn.peer_id, NetRejects.Reason.CHANNEL_CLOSED)
			_lose(conn, JOIN_FAILED)
	for peer_id in _order.stalled_peers(now):
		_note_reject(peer_id, NetRejects.Reason.ORDER_STALLED)
		var conn: Conn = _conns.get(peer_id)
		if conn != null:
			_lose(conn, JOIN_FAILED)


## A connection ended without disconnect_peer: on the host a leave of an admitted peer (a
## half-made one is dropped quietly, its id not reused); on a client host_lost, or connect_failed
## for `reason` before ADMIT.
func _lose(conn: Conn, reason: StringName) -> void:
	_drop(conn)
	if is_host():
		if conn.open:
			_push(Inbound.new(Inbound.Type.LEFT, conn.peer_id))
	elif conn.admitted:
		_push(Inbound.new(Inbound.Type.HOST_LOST, HOST_ID))
	else:
		_fail_join(reason)


## Closes a connection at once and forgets it.
func _drop(conn: Conn) -> void:
	conn.pc.close()
	_conns.erase(conn.peer_id)
	_by_joiner.erase(conn.joiner)
	_order.forget(conn.peer_id)


func _fail_join(reason: StringName) -> void:
	var failed := Inbound.new(Inbound.Type.CONNECT_FAILED, HOST_ID)
	failed.reason = reason
	_push(failed)


## Writes to a connection's channel, only while it is open (§2.6); LATEST gets LaneOrder's header
## and RELIABLE is counted for it. Counts the upload (E56).
func _put(conn: Conn, lane: NetKindTable.Lane, bytes: PackedByteArray) -> Error:
	var channel := conn.channels[lane]
	if channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return ERR_CONNECTION_ERROR
	var packet := bytes
	if lane == NetKindTable.Lane.LATEST:
		packet = _order.stamp_latest(conn.peer_id, bytes)
		if packet.is_empty():
			return ERR_DOES_NOT_EXIST
	var err := channel.put_packet(packet)
	if err != OK:
		return err
	if lane == NetKindTable.Lane.RELIABLE:
		_order.count_reliable_sent(conn.peer_id)
	conn.last_sent_ms = Time.get_ticks_msec()
	_upload_bytes += packet.size() + PACKET_OVERHEAD_BYTES
	_upload_frames += 1
	return OK


## Open, admitted where it matters, and not being closed by the host.
func _is_live(conn: Conn) -> bool:
	return conn.open and conn.closing_since_ms < 0 and (is_host() or conn.admitted)


func _on_signal_opened() -> void:
	_signal_opened = true


## The service went away. The host keeps its peers and takes no new ones; a joiner still waiting
## for an offer fails (a join with a connection under way goes on without the service).
func _on_signal_closed() -> void:
	if _signaller == null:
		return
	_signaller = null
	if role() == Role.CLIENT and _conns.is_empty() and _client_id == 0:
		_fail_join(JOIN_SERVICE_UNREACHABLE if not _signal_opened else JOIN_FAILED)


func _on_refused(why: String) -> void:
	if _signaller == null or role() != Role.CLIENT or _client_id != 0:
		return
	match why:
		SignalCodec.WHY_NO_ROOM:
			_fail_join(JOIN_NO_ROOM)
		SignalCodec.WHY_STARTED:
			_fail_join(JOIN_STARTED)
		SignalCodec.WHY_FULL:
			_fail_join(JOIN_FULL)
		SignalCodec.WHY_HOST_LEFT:
			_fail_join(JOIN_FAILED)
		_:
			_fail_join(JOIN_SERVICE_REFUSED)


func _on_room_opened(code: String, ice_servers: Array) -> void:
	if _signaller == null or not is_host():
		return
	_room_code = code
	_ice_servers = ice_servers
	if is_refusing_new_connections():
		_signaller.close_room()
	room_opened.emit(code)


## Host: a joiner wants in. A refusing or full host answers nothing (the join times out).
func _on_joiner_arrived(joiner: int) -> void:
	if _signaller == null or not is_host() or is_refusing_new_connections():
		return
	if _by_joiner.has(joiner) or _conns.size() >= _max_clients:
		return
	var peer_id := _next_peer_id
	_next_peer_id += 1
	var conn := _new_connection(peer_id, joiner, _ice_servers)
	if conn == null:
		return
	_by_joiner[joiner] = peer_id
	if conn.pc.create_offer() != OK:
		_drop(conn)


## Host: one answer per offer. A second one, or one the connection cannot take, ends it.
func _on_answer(joiner: int, sdp: String) -> void:
	var conn := _joiners_conn(joiner)
	if conn == null:
		return
	if conn.described or conn.pc.set_remote_description("answer", sdp) != OK:
		_drop(conn)
		return
	conn.described = true


func _on_candidate(joiner: int, mid: String, index: int, cand: String) -> void:
	var conn: Conn = _joiners_conn(joiner) if is_host() else _conns.get(HOST_ID)
	if conn == null or not conn.described or conn.open or cand.is_empty():
		return
	if conn.pc.add_ice_candidate(mid, index, cand) != OK:
		_lose(conn, JOIN_UNREACHABLE)


func _on_room_found(protocol: int, content: int) -> void:
	found_protocol = protocol
	found_content = content


## Joiner: one offer per attempt; the connection answers it (session_description_created).
func _on_offer(_id: int, sdp: String, ice_servers: Array) -> void:
	if _signaller == null or role() != Role.CLIENT or not _conns.is_empty() or _client_id != 0:
		return
	var conn := _new_connection(HOST_ID, 0, ice_servers)
	if conn == null:
		_fail_join(JOIN_FAILED)
		return
	if conn.pc.set_remote_description("offer", sdp) != OK:
		_lose(conn, JOIN_UNREACHABLE)
		return
	conn.described = true


func _on_description(type: String, sdp: String, key: int) -> void:
	var conn: Conn = _conns.get(key)
	if conn == null or _signaller == null or conn.pc.set_local_description(type, sdp) != OK:
		if conn != null:
			_lose(conn, JOIN_FAILED)
		return
	if is_host() and type == "offer":
		_signaller.send_offer(conn.joiner, conn.peer_id, sdp)
	elif not is_host() and type == "answer":
		_signaller.send_answer(sdp)


func _on_local_candidate(media: String, index: int, cand: String, key: int) -> void:
	var conn: Conn = _conns.get(key)
	if conn == null or _signaller == null:
		return
	var sent := _local(cand) if local_candidates else cand
	if sent.is_empty():
		return
	if is_host():
		_signaller.send_candidate_to(conn.joiner, media, index, sent)
	else:
		_signaller.send_candidate(media, index, sent)


func _joiners_conn(joiner: int) -> Conn:
	if _signaller == null or not is_host() or not _by_joiner.has(joiner):
		return null
	return _conns.get(_by_joiner[joiner])


## An IPv4 host candidate rewritten to 127.0.0.1, or "" for any other.
static func _local(cand: String) -> String:
	var parts := cand.split(" ")
	var at := parts.find("typ")
	if at < 2 or at + 1 >= parts.size() or parts[at + 1] != "host":
		return ""
	if not parts[at - 2].is_valid_ip_address() or not parts[at - 2].contains("."):
		return ""
	parts[at - 2] = "127.0.0.1"
	return " ".join(parts)
