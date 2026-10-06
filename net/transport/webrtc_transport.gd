class_name WebRtcTransport
extends NetTransport
## NetTransport over WebRTC data channels (the M6 ADR §2.1 to §2.3 and §2.6; E48, E50, E54):
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
## header, so they keep ENet's order against RELIABLE (the M6 ADR §2.2). Once the channels are
## open the host sends ADMIT on RELIABLE, a kind-0 frame whose payload is the client's peer id
## (u32); the client learns its id there and refuses one of HOST_ID or less.
##
## WebRTC's own keepalives never reach the main thread, so a hung game would stay "connected":
## poll() sends each peer KEEPALIVE on VOICE when nothing went to it for KEEPALIVE_MS, and a peer
## heard from for SILENCE_MS (backlog drained first) leaves, as does a connection that reaches
## FAILED or CLOSED, or a channel that closes under a live connection. DISCONNECTED is transient.
## Nothing is ever written to a channel that is not open: that prints an engine error (M6-1).
##
## The own connection for the debug overlay (the M6 design §3 item 4, #431): webrtc-native reports
## neither the selected candidate pair nor a round trip (webrtc_native_addon_test). So own_route()
## tells the kind from the ICE servers the offer brought (route_of: with no TURN server nothing can
## be relayed), and a client with measure_round_trip set pings the host on VOICE every
## PING_INTERVAL_MS; the host answers the pings of one poll once, echoing the client's clock, and
## the client smooths the round trips into own_round_trip_ms(). Both are consumed before the inbox,
## as KEEPALIVE: a probe the wrong way, or malformed, is a kind-0 packet the inbox rejects.

## Host: the service made the room; its code is what friends type.
signal room_opened(code: String)

## The data channel of each lane: negotiated with these ids on both sides (no
## data_channel_received race), LATEST and VOICE unordered with no resend.
const CHANNEL_IDS: Dictionary[NetKindTable.Lane, int] = {
	NetKindTable.Lane.RELIABLE: 1,
	NetKindTable.Lane.LATEST: 2,
	NetKindTable.Lane.VOICE: 3,
}
## Nothing went to a peer for this long: poll() sends it KEEPALIVE (a placeholder, the M6 ADR §2.6).
const KEEPALIVE_MS := 1000
## The empty kind-0 frame, sent on VOICE and consumed before the inbox; any other kind-0 packet
## reaches the inbox and is rejected there (no kind table allows kind 0).
const KEEPALIVE: Array[int] = [0, 0, 0]
## Nothing heard from a peer for this long, keepalives included, is a leave (the M6 ADR §2.6):
## past a 5.2 s freeze and WebRTC's own 12.8 s on loopback, and LaneOrder's stall rule uses it too.
const SILENCE_MS := 20000
## A join not admitted this long after join() gives up (E54, a placeholder): no offer came (a
## full or refusing host answers none), or the channels never opened. The host closes a half-made
## connection after as long from the joiner's arrival.
const JOIN_TIMEOUT_MS := 15000
## A channel closed under a live connection becomes a leave after this long (placeholder): a client
## closing resets its channels just before its connection ends, and the host may read the first in
## a poll before the second.
const CHANNEL_GRACE_MS := 1000
## disconnect_peer: the connection closes once the client closed its side, or after this long.
const CLOSE_WAIT_MS := 5000
## take_upload's cost of one packet beyond its bytes (E56, M6-1): 57 B of SCTP and DTLS, 48 B of
## IPv6 and UDP, and at most 3 B of padding. Over IPv4 it errs high by at most 23 B.
const PACKET_OVERHEAD_BYTES := 108
## ADMIT: the 3-byte frame header of kind 0 with a 4-byte payload, the peer id.
const ADMIT_BYTES := NetFrame.HEADER_BYTES + 4
## The round trip's probes on VOICE: the header of kind 0 with a 5-byte payload, the type (PING from
## the client, PONG from the host) and the client's clock in ms (u32) when it pinged.
const PING_BYTES := NetFrame.HEADER_BYTES + 5
const PING := 1
const PONG := 2
## A measuring client pings this often (a placeholder, not a decision): a ping also counts as a
## keepalive.
const PING_INTERVAL_MS := 1000
## Each round trip measured moves own_round_trip_ms() this part of the way (as TCP's smoothed RTT).
const ROUND_TRIP_GAIN := 0.125

## The signalling service: ws://host:port for a LanSignalling, wss:// for the Worker.
var signal_url := ""
## Host: what `open` tells the service (advisory to joiners, the M6 ADR §2.5).
var room_protocol := 0
var room_content := 0
## Tests: only IPv4 host candidates are signalled, rewritten to 127.0.0.1, so every packet stays
## on the loopback (the container's own address works too, but tests keep off the network).
var local_candidates := false
## Joiner: the protocol and content hash this game runs, for the version check against `found`
## (the M6 ADR §2.5, M6-7): set, a `found` naming another ends the join before any offer is
## applied, as JOIN_WRONG_VERSION or JOIN_WRONG_CONTENT. -1: no check (Hello still decides).
var expect_protocol := -1
var expect_content := 0
## Joiner: the host's protocol and content hash from the service's `found` (advisory, the M6 ADR
## §2.5), -1 before it.
var found_protocol := -1
var found_content := 0
## JOIN_TIMEOUT_MS; tests shorten it.
var join_timeout_ms := JOIN_TIMEOUT_MS
## The signalling socket's Signaller.CONNECT_TIMEOUT_MS; tests shorten it below join_timeout_ms.
var signal_connect_timeout_ms := Signaller.CONNECT_TIMEOUT_MS

var _signaller: Signaller = null
var _keepalive := PackedByteArray(KEEPALIVE)
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
## Client: `found` named another version; the join is failing and applies no offer.
var _found_refused := false
## When poll() last ran; -1 before the first.
var _last_poll_ms := -1
## Client: when it last pinged the host, -1 before; the smoothed round trip, -1 before the first.
var _last_ping_ms := -1
var _round_trip_ms := -1.0


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
	## This poll, before the reads: the connection had ended; every channel was open.
	var ended_seen := false
	var channels_seen_open := true
	## Host: when a channel was first seen closed under the live connection; -1 otherwise.
	var channel_closed_ms := -1
	var last_sent_ms := 0
	var last_heard_ms := 0
	## The fault shim's RELIABLE packets still on their way, oldest first, with their due times.
	var delayed: Array[PackedByteArray] = []
	var delayed_due: PackedInt64Array = PackedInt64Array()
	## The fault shim's late LATEST packets, in the order they were read, with their due times (never
	## decreasing: a late packet holds back the ones behind it).
	var late_latest: Array[PackedByteArray] = []
	var late_latest_due: PackedInt64Array = PackedInt64Array()
	## The ICE servers it was made with include a TURN server (route_of).
	var may_relay := false
	## Host: the stamp of the last ping read this poll, answered after the reads; -1 for none.
	var ping_stamp := -1

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
## behind it, as SCTP would); LATEST packets are dropped and duplicated at the given rates, and
## at the rate latest_late a copy arrives latest_delay_ms late, holding back the LATEST packets
## behind it (LATEST stays in order among itself): later than a RELIABLE packet sent after it when
## that exceeds reliable_delay_ms, the case only LaneOrder's "behind" rule handles (M6-6).
class FaultShim:
	extends RefCounted
	var reliable_delay_ms := 0
	var latest_drop := 0.0
	var latest_duplicate := 0.0
	var latest_late := 0.0
	var latest_delay_ms := 0
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

	## How late one copy of a LATEST packet arrives: latest_delay_ms at the rate latest_late, else 0.
	func latest_delay() -> int:
		if latest_late > 0.0 and rng.randf() < latest_late:
			return latest_delay_ms
		return 0


## Turns the fault shim on (null: off). ERR_UNAVAILABLE in a release build.
func use_faults(shim: FaultShim) -> Error:
	if not OS.is_debug_build():
		return ERR_UNAVAILABLE
	_faults = shim
	return OK


## Host: its connections, half-made and closing ones included (they count against the maximum).
## Client: 1 from the offer on, else 0.
func connection_count() -> int:
	return _conns.size()


## Host: the room's code once room_opened fired, else "".
func room_code() -> String:
	return _room_code


## Client: the own connection once admitted (route_of its ICE servers); NONE otherwise.
func own_route() -> Route:
	var conn: Conn = _conns.get(HOST_ID)
	if role() != Role.CLIENT or conn == null or not _is_live(conn):
		return Route.NONE
	return Route.DIRECT_OR_RELAYED if conn.may_relay else Route.DIRECT


## Client: the smoothed round trip of its pings (measure_round_trip), -1 before the first answer or
## without a connection.
func own_round_trip_ms() -> int:
	if own_route() == Route.NONE or _round_trip_ms < 0.0:
		return -1
	return roundi(_round_trip_ms)


## The kind of a connection made with `ice_servers` (the service's list, as SignalCodec rebuilds
## it): DIRECT_OR_RELAYED when one of them is a TURN server ("turn:" or "turns:", any case), else
## DIRECT: without TURN no relay candidate exists, and host and server-reflexive pairs are direct.
static func route_of(ice_servers: Array) -> Route:
	for server: Variant in ice_servers:
		if not server is Dictionary:
			continue
		var urls: Variant = (server as Dictionary).get("urls")
		var listed: Array = urls if urls is Array else [urls]
		for url: Variant in listed:
			if url is String and (url as String).to_lower().begins_with("turn"):
				return Route.DIRECT_OR_RELAYED
	return Route.DIRECT


## Whether the socket to the signalling service is open (or opening): false once it closed or
## failed, so a host's lobby can say that no code is coming (M6-7).
func signalling_open() -> bool:
	return _signaller != null


## Host: also closes or reopens the room at the service, so a code typed while the match runs is
## answered "the match has started".
func set_refuse_new_connections(refuse: bool) -> void:
	var changed := refuse != is_refusing_new_connections()
	super(refuse)
	if changed and is_host() and refuse:
		# Joiners still connecting get no more answers either (the M6 ADR §2.3).
		for conn: Conn in _conns.values():
			if not conn.open:
				_drop(conn)
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
	found_protocol = -1
	found_content = 0
	_signaller.join_room(address)
	return OK


func _backend_poll() -> void:
	var signaller := _signaller  # its handlers may drop it during its own poll()
	if signaller != null:
		signaller.poll()
	var now := Time.get_ticks_msec()
	var since := _last_poll_ms if _last_poll_ms >= 0 else now
	_last_poll_ms = now
	for peer_id: int in _conns.keys():
		if _conns.has(peer_id):
			_step_connection(_conns[peer_id], now)
	for peer_id: int in _conns.keys():
		if _conns.has(peer_id):
			_read(_conns[peer_id], now, since)
	_judge(now)
	if role() == Role.CLIENT and _client_id == 0 and now - _join_started_ms > join_timeout_ms:
		_fail_join(JOIN_UNREACHABLE)
	_ping(now)
	for conn: Conn in _conns.values():
		if _is_live(conn) and now - conn.last_sent_ms >= KEEPALIVE_MS:
			_put(conn, NetKindTable.Lane.VOICE, _keepalive)


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
	_last_poll_ms = -1
	_last_ping_ms = -1
	_round_trip_ms = -1.0
	_found_refused = false
	# found_protocol and found_content stay: the menu names them after a join ends on them.


## The reason was sent before this call; poll() closes the RELIABLE channel next, then the
## connection. Held LATEST packets are discarded at once, and nothing more goes to the peer.
func _backend_disconnect(peer_id: int) -> void:
	var conn: Conn = _conns.get(peer_id)
	if conn != null and conn.closing_since_ms < 0:
		conn.closing_since_ms = Time.get_ticks_msec()
		_order.forget(peer_id)
		conn.delayed.clear()
		conn.delayed_due.clear()
		conn.late_latest.clear()
		conn.late_latest_due.clear()


func _open_signaller() -> Error:
	var signaller := Signaller.new()
	signaller.connect_timeout_ms = signal_connect_timeout_ms
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
	conn.may_relay = route_of(ice_servers) == Route.DIRECT_OR_RELAYED
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
	# Seen before the reads: what arrived with the end is read first, and _judge decides after.
	conn.ended_seen = conn.ended()
	conn.channels_seen_open = conn.all_channels_open()
	if conn.ended_seen and not conn.open:
		_lose(
			conn,
			JOIN_UNREACHABLE if conn.state() == WebRTCPeerConnection.STATE_FAILED else JOIN_FAILED
		)
	elif not conn.open:
		if conn.state() == WebRTCPeerConnection.STATE_CONNECTED and conn.all_channels_open():
			_opened(conn, now)
		elif now - conn.started_ms > join_timeout_ms:
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
	var id := PackedByteArray()
	id.resize(4)
	id.encode_u32(0, conn.peer_id)
	var admit := NetFrame.encode(0, id)
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
## reliable one comes first, as ENet delivers it (the M6 ADR §2.2).
## `since`: the previous poll, when what is read now had arrived at the latest (the fault shim
## delays from there, so a backlog read after a freeze is not held back again).
func _read(conn: Conn, now: int, since: int) -> void:
	if not conn.open:
		return
	var closing := conn.closing_since_ms >= 0
	_release_late_latest(conn, now)
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
					if _faults == null:
						_take_latest(conn, bytes, now)
					else:
						for _i in _faults.latest_copies():
							_shim_latest(conn, bytes, now, since)
				NetKindTable.Lane.RELIABLE:
					if _faults == null:
						_take_reliable(conn, bytes, now)
					else:
						_delay_reliable(conn, bytes, since)
				NetKindTable.Lane.VOICE:
					if bytes != _keepalive and not _took_probe(conn, bytes, now):
						_push_packet(conn.peer_id, bytes, lane)
			if not _conns.has(conn.peer_id):
				return  # a bad ADMIT ended the join
	if conn.ping_stamp >= 0:
		_put(conn, NetKindTable.Lane.VOICE, _probe(PONG, conn.ping_stamp))
		conn.ping_stamp = -1
	_release_delayed(conn, now)


## A round-trip probe the right way, consumed: the host notes a ping to answer, the client takes
## an answer's round trip (one stamped later than now, or older than SILENCE_MS, is dropped). False
## for anything else, which goes on to the inbox.
func _took_probe(conn: Conn, bytes: PackedByteArray, now: int) -> bool:
	if bytes.size() != PING_BYTES or bytes[0] != 0 or bytes.decode_u16(1) != PING_BYTES - 3:
		return false
	var type := bytes[NetFrame.HEADER_BYTES]
	var stamp := bytes.decode_u32(NetFrame.HEADER_BYTES + 1)
	if is_host() and type == PING:
		if _is_live(conn):
			conn.ping_stamp = stamp
		return true
	if not is_host() and type == PONG:
		if not measure_round_trip:
			return true
		var sample := (now - stamp) & 0xFFFFFFFF
		if sample <= SILENCE_MS:
			if _round_trip_ms < 0.0:
				_round_trip_ms = float(sample)
			else:
				_round_trip_ms += (sample - _round_trip_ms) * ROUND_TRIP_GAIN
		return true
	return false


## Client: pings the host when measure_round_trip is set, once admitted and every PING_INTERVAL_MS.
func _ping(now: int) -> void:
	if role() != Role.CLIENT:
		return
	if not measure_round_trip:
		# Not measuring (the overlay is hidden): forget the old figure, or reopening it would show
		# a round trip of minutes ago as the current one.
		_last_ping_ms = -1
		_round_trip_ms = -1.0
		return
	var conn: Conn = _conns.get(HOST_ID)
	if conn == null or not _is_live(conn):
		return
	if _last_ping_ms >= 0 and now - _last_ping_ms < PING_INTERVAL_MS:
		return
	if _put(conn, NetKindTable.Lane.VOICE, _probe(PING, now)) == OK:
		_last_ping_ms = now


## A probe of `type` stamped with the client's clock `stamp_ms` (its low 32 bits).
static func _probe(type: int, stamp_ms: int) -> PackedByteArray:
	var bytes := PackedByteArray([0, PING_BYTES - NetFrame.HEADER_BYTES, 0, type, 0, 0, 0, 0])
	bytes.encode_u32(NetFrame.HEADER_BYTES + 1, stamp_ms & 0xFFFFFFFF)
	return bytes


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
			conn.delayed.clear()  # the join is over: nothing behind it is read
			conn.delayed_due.clear()
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


func _delay_reliable(conn: Conn, bytes: PackedByteArray, arrived: int) -> void:
	var due := arrived + _faults.reliable_delay()
	if not conn.delayed_due.is_empty():
		due = maxi(due, conn.delayed_due[conn.delayed_due.size() - 1])
	conn.delayed.append(bytes)
	conn.delayed_due.append(due)


## One copy of a LATEST packet read at `now` under the fault shim: late by its delay from `since`,
## or behind a late one still held, in order; else at once.
func _shim_latest(conn: Conn, bytes: PackedByteArray, now: int, since: int) -> void:
	var late := _faults.latest_delay()
	if late == 0 and conn.late_latest.is_empty():
		_take_latest(conn, bytes, now)
		return
	var due := since + late
	if not conn.late_latest_due.is_empty():
		due = maxi(due, conn.late_latest_due[conn.late_latest_due.size() - 1])
	conn.late_latest.append(bytes)
	conn.late_latest_due.append(due)


## The fault shim's late LATEST packets due by `now`, in the order they were read.
func _release_late_latest(conn: Conn, now: int) -> void:
	while not conn.late_latest.is_empty() and conn.late_latest_due[0] <= now:
		var bytes: PackedByteArray = conn.late_latest.pop_front()
		conn.late_latest_due.remove_at(0)
		_take_latest(conn, bytes, now)


func _release_delayed(conn: Conn, now: int) -> void:
	while not conn.delayed.is_empty() and conn.delayed_due[0] <= now and _conns.has(conn.peer_id):
		var bytes: PackedByteArray = conn.delayed.pop_front()
		conn.delayed_due.remove_at(0)
		_take_reliable(conn, bytes, now)


## After every connection was read: the silence rule, a channel closed under a live connection,
## and LaneOrder's stalled peers.
func _judge(now: int) -> void:
	for conn: Conn in _conns.values():
		if not conn.open or conn.closing_since_ms >= 0:
			continue
		if conn.ended_seen:
			_lose(conn, JOIN_FAILED)
		elif not _is_live(conn):
			continue
		elif now - conn.last_heard_ms > SILENCE_MS:
			_lose(conn, JOIN_UNREACHABLE)
		elif not conn.channels_seen_open:
			# The host closing a client's RELIABLE channel is how it ends that client: at once, no
			# fault. On the host a client's own close ends its connection within the grace.
			if not is_host():
				_lose(conn, JOIN_FAILED)
			elif conn.channel_closed_ms < 0:
				conn.channel_closed_ms = now
			elif now - conn.channel_closed_ms >= CHANNEL_GRACE_MS:
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
	# The fault shim's late RELIABLE packets were sent before the end: they still come first.
	while not conn.delayed.is_empty() and _conns.has(conn.peer_id):
		var late: PackedByteArray = conn.delayed.pop_front()
		conn.delayed_due.remove_at(0)
		_take_reliable(conn, late, Time.get_ticks_msec())
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


## Writes to a connection's channel, only while it is open (the M6 ADR §2.6); LATEST gets
## LaneOrder's header and RELIABLE is counted for it. Counts the upload (E56).
func _put(conn: Conn, lane: NetKindTable.Lane, bytes: PackedByteArray) -> Error:
	var channel := conn.channels[lane]
	if channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return ERR_CONNECTION_ERROR
	# The peer never reads an empty message: one put on RELIABLE would be counted for LaneOrder all
	# the same, and every later LATEST packet would wait for one reliable packet more, arriving
	# behind one sent after it (#429). NetFrame never makes one; a modified client's raw send can.
	if bytes.is_empty():
		return ERR_INVALID_DATA
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
	_room_code = ""  # a host's room is gone with its socket (no reclaim)
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
			if _conns.is_empty():  # a connection under way goes on without the service
				_fail_join(JOIN_FAILED)
		SignalCodec.WHY_CANDIDATES, SignalCodec.WHY_TOO_LARGE:
			pass  # one candidate or message refused: the join may still connect, or times out
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
		_lose(conn, JOIN_FAILED)  # an admitted peer leaves
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
	if _signaller == null or role() != Role.CLIENT or expect_protocol < 0 or _found_refused:
		return
	if protocol != expect_protocol:
		_found_refused = true
		_fail_join(JOIN_WRONG_VERSION)
	elif content != expect_content:
		_found_refused = true
		_fail_join(JOIN_WRONG_CONTENT)


## Joiner: one offer per attempt; the connection answers it (session_description_created).
func _on_offer(_id: int, sdp: String, ice_servers: Array) -> void:
	if _signaller == null or role() != Role.CLIENT or not _conns.is_empty() or _client_id != 0:
		return
	if _found_refused:
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
