extends Control
## Spike (#21): a host and two clients; spike/kill/kill_probe.ps1 hard-kills client 2 and this
## checks that the host and client 1 keep hearing each other. User args after "--":
##   --role=host|client        default: PRIME_INSTANCE 1 hosts, 2 and 3 join (run --instances 3)
##   --name=client1|client2    default: from PRIME_INSTANCE
##   --impl=spike|real|raw     spike: ENetMultiplayerPeer under SceneMultiplayer (the #13 spike);
##                             real: net/'s EnetTransport; raw: a bare ENetConnection (default real)
##   --timeouts=short|real     ENet peer timeouts for spike and raw (short = the spike's 2-4 s)
##   --address=IP              where clients join (default 127.0.0.1)
##   --bind=IP                 where the host listens (default 127.0.0.1; "*" for a second machine)
##   --port=N                  ENet port (default 24580); the side channel uses N+1
##   --seconds=N               clients quit after N s, the host 3 s later
##   --pid-dir=PATH            writes <name>.pid there, for the launcher's kill
##   --freeze=S:MS             blocks this process's main thread for MS ms, S s after start
## Every packet carries its sender, a sequence number and the sender's wall clock, so on one machine
## the receiver sees each packet's delay. A plain UDP side channel (PacketPeerUDP, no ENet) runs
## next to it, to tell an ENet problem from a socket or OS one. Lines start with "PROBE <name>".

const GAP_LIMIT_MS := 1000.0
const SEND_EVERY_MS := 50
const DEBUG_EVERY_MS := 250
const HOST_EXTRA_S := 3.0
const SHORT_TIMEOUT: Array[int] = [8, 2000, 4000]
const REAL_TIMEOUT: Array[int] = [
	EnetTransport.PEER_TIMEOUT_LIMIT,
	EnetTransport.PEER_TIMEOUT_MIN_MS,
	EnetTransport.PEER_TIMEOUT_MAX_MS
]
const PACKET_SIZE := 32

var _impl := "real"
var _is_host := true
var _name := "host"
var _who := 0
var _address := "127.0.0.1"
var _bind := "127.0.0.1"
var _port := 24580
var _seconds := -1.0
var _timeout: Array[int] = SHORT_TIMEOUT
var _net: ProbeNet
var _side := PacketPeerUDP.new()
var _side_peers: Dictionary[String, float] = {}
var _started_ms := 0
var _last_send_ms := 0
var _last_debug_ms := 0
var _last_frame_us := 0
var _max_frame_ms := 0.0
var _seq := 0
var _status := "starting"
var _left: Array[int] = []
var _lost := false
# Per sender (0 host, 1 client 1, 2 client 2): whole-run and per-debug-window stats.
var _rx: Dictionary[int, Stats] = {}
var _side_rx: Dictionary[int, Stats] = {}
var _dots: Dictionary[int, Vector2] = {}
# --freeze=S:MS blocks the main thread for MS ms once, S s after start: the freeze a kill caused.
var _freeze_at_ms := -1
var _freeze_ms := 0
var _label := Label.new()


class Stats:
	extends RefCounted
	var count := 0
	var window := 0
	var window_max_delay := 0.0
	var last_ms := 0.0
	var max_gap := 0.0
	var max_gap_at := 0.0
	var max_delay := 0.0
	var max_delay_at := 0.0
	var last_seq := -1
	var skipped := 0

	func add(now_ms: float, sent_ms: float, seq: int) -> void:
		if last_ms > 0.0 and now_ms - last_ms > max_gap:
			max_gap = now_ms - last_ms
			max_gap_at = now_ms
		var delay := now_ms - sent_ms
		if delay > max_delay:
			max_delay = delay
			max_delay_at = now_ms
		window_max_delay = maxf(window_max_delay, delay)
		if last_seq >= 0 and seq > last_seq + 1:
			skipped += seq - last_seq - 1
		last_seq = maxi(last_seq, seq)
		last_ms = now_ms
		count += 1
		window += 1

	func pop_window() -> String:
		var text := "%d/%.0f" % [window, window_max_delay]
		window = 0
		window_max_delay = 0.0
		return text


## The three ways to reach ENet. Signals fire from poll().
class ProbeNet:
	extends RefCounted
	signal joined(id: int)
	signal left(id: int)
	signal packet(from_id: int, bytes: PackedByteArray)
	signal connected
	signal lost

	func host(_bind: String, _port: int) -> Error:
		return ERR_UNAVAILABLE

	func join(_address: String, _port: int) -> Error:
		return ERR_UNAVAILABLE

	func poll() -> void:
		pass

	func send_host(_bytes: PackedByteArray) -> void:
		pass

	func send_all(_bytes: PackedByteArray) -> void:
		pass

	## The ENetConnection, for its counters; null once closed.
	func conn() -> ENetConnection:
		return null

	func close() -> void:
		pass


## As the #13 spike: SceneMultiplayer over ENetMultiplayerPeer, raw bytes, no RPCs.
class SpikeNet:
	extends ProbeNet
	var mp := SceneMultiplayer.new()
	var peer: ENetMultiplayerPeer
	var timeout: Array[int]

	func _init(peer_timeout: Array[int]) -> void:
		timeout = peer_timeout
		mp.root_path = ^"/root"
		mp.server_relay = false
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.connected_to_server.connect(_on_connected_to_server)
		mp.server_disconnected.connect(_on_server_disconnected)
		mp.peer_packet.connect(_on_peer_packet)

	func host(bind: String, port: int) -> Error:
		peer = ENetMultiplayerPeer.new()
		peer.set_bind_ip(bind)
		var err := peer.create_server(port, 4)
		if err == OK:
			mp.multiplayer_peer = peer
		return err

	func join(address: String, port: int) -> Error:
		peer = ENetMultiplayerPeer.new()
		var err := peer.create_client(address, port)
		if err == OK:
			mp.multiplayer_peer = peer
		return err

	func poll() -> void:
		if peer != null:
			mp.poll()

	func send_host(bytes: PackedByteArray) -> void:
		_send(1, bytes)

	func send_all(bytes: PackedByteArray) -> void:
		_send(0, bytes)

	func _send(to: int, bytes: PackedByteArray) -> void:
		if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			mp.send_bytes(bytes, to, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)

	func conn() -> ENetConnection:
		if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return null
		return peer.host

	func close() -> void:
		if peer != null:
			peer.close()
			peer = null

	func _on_peer_connected(id: int) -> void:
		var packet_peer := peer.get_peer(id)
		if packet_peer != null:
			packet_peer.set_timeout(timeout[0], timeout[1], timeout[2])
		joined.emit(id)

	func _on_peer_disconnected(id: int) -> void:
		left.emit(id)

	func _on_connected_to_server() -> void:
		connected.emit()

	func _on_server_disconnected() -> void:
		lost.emit()

	func _on_peer_packet(id: int, bytes: PackedByteArray) -> void:
		packet.emit(id, bytes)


## net/'s EnetTransport (#40): ENetMultiplayerPeer read directly, its own timeouts.
class RealNet:
	extends ProbeNet
	const KIND_UP := 1
	const KIND_DOWN := 2
	var transport: EnetTransport

	func _init() -> void:
		var kinds := NetKindTable.new()
		kinds.add(KIND_UP, NetKindTable.Lane.LATEST, NetKindTable.Direction.CLIENT_TO_HOST, 64)
		kinds.add(KIND_DOWN, NetKindTable.Lane.LATEST, NetKindTable.Direction.HOST_TO_CLIENT, 64)
		transport = EnetTransport.new(kinds)
		# Bound methods, not lambdas: a lambda capturing self, held by the transport self owns, leaks.
		transport.peer_joined.connect(joined.emit)
		transport.peer_left.connect(left.emit)
		transport.packet_received.connect(_on_packet_received)
		transport.connected.connect(_on_connected)
		transport.host_lost.connect(lost.emit)

	func _on_packet_received(from_id: int, _kind: int, payload: PackedByteArray) -> void:
		packet.emit(from_id, payload)

	func _on_connected(_id: int) -> void:
		connected.emit()

	func host(bind: String, port: int) -> Error:
		transport.bind_address = bind
		return transport.host(port, 4)

	func join(address: String, port: int) -> Error:
		return transport.join(address, port)

	func poll() -> void:
		transport.poll()

	func send_host(bytes: PackedByteArray) -> void:
		transport.send(NetTransport.HOST_ID, KIND_UP, bytes)

	func send_all(bytes: PackedByteArray) -> void:
		for id in transport.peers():
			if id != NetTransport.HOST_ID:
				transport.send(id, KIND_DOWN, bytes)

	func conn() -> ENetConnection:
		var peer: ENetMultiplayerPeer = transport.get("_peer")
		if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return null
		return peer.host

	func close() -> void:
		transport.close()


## A bare ENetConnection: no MultiplayerPeer at all. Peer ids are local counters.
class RawNet:
	extends ProbeNet
	var connection := ENetConnection.new()
	var server: ENetPacketPeer
	var is_host := false
	var timeout: Array[int]
	var next_id := 2
	var open := false

	func _init(peer_timeout: Array[int]) -> void:
		timeout = peer_timeout

	func host(bind: String, port: int) -> Error:
		is_host = true
		var err := connection.create_host_bound(bind, port, 4, 1)
		open = err == OK
		return err

	func join(address: String, port: int) -> Error:
		var err := connection.create_host(1, 1)
		if err == OK:
			server = connection.connect_to_host(address, port, 1)
			open = server != null
			return OK if open else ERR_CANT_CONNECT
		return err

	func poll() -> void:
		while open:
			var event: Array = connection.service(0)
			var type: ENetConnection.EventType = event[0]
			if type == ENetConnection.EVENT_NONE:
				return
			var peer: ENetPacketPeer = event[1]
			match type:
				ENetConnection.EVENT_CONNECT:
					peer.set_timeout(timeout[0], timeout[1], timeout[2])
					if is_host:
						peer.set_meta(&"id", next_id)
						next_id += 1
						joined.emit(peer.get_meta(&"id"))
					else:
						connected.emit()
				ENetConnection.EVENT_DISCONNECT:
					if is_host:
						left.emit(peer.get_meta(&"id", 0))
					else:
						open = false
						lost.emit()
				ENetConnection.EVENT_RECEIVE:
					var bytes := peer.get_packet()
					packet.emit(peer.get_meta(&"id", 1) if is_host else 1, bytes)
				_:
					print("PROBE raw service error %d" % type)
					return

	func send_host(bytes: PackedByteArray) -> void:
		if server != null and server.get_state() == ENetPacketPeer.STATE_CONNECTED:
			server.send(0, bytes, 0)

	func send_all(bytes: PackedByteArray) -> void:
		if open:
			connection.broadcast(0, bytes, 0)

	func conn() -> ENetConnection:
		return connection if open else null

	func close() -> void:
		if open:
			open = false
			connection.destroy()


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_parse_args(OS.get_cmdline_user_args())
	get_window().title = "kill probe: %s %s" % [_impl, _name]
	_label.position = Vector2(8, 4)
	add_child(_label)
	match _impl:
		"spike":
			_net = SpikeNet.new(_timeout)
		"raw":
			_net = RawNet.new(_timeout)
		_:
			_impl = "real"
			_net = RealNet.new()
	_net.joined.connect(func(id: int) -> void: _event("joined id=%d" % id))
	_net.left.connect(_on_left)
	_net.packet.connect(_on_packet)
	_net.connected.connect(_on_connected)
	_net.lost.connect(_on_lost)
	var err: Error
	if _is_host:
		err = _net.host(_bind, _port)
		_side.bind(_port + 1, _bind)
		_status = "listening on %s:%d" % [_bind, _port]
	else:
		err = _net.join(_address, _port)
		_side.set_dest_address(_address, _port + 1)
		_status = "joining %s:%d" % [_address, _port]
	if err != OK:
		_status = "FAILED: %s" % error_string(err)
	_event(
		(
			"start pid=%d impl=%s timeouts=%s window=%s %s"
			% [OS.get_process_id(), _impl, _timeout, DisplayServer.get_name(), _status]
		)
	)


func _parse_args(args: PackedStringArray) -> void:
	var instance := OS.get_environment("PRIME_INSTANCE").to_int()
	if instance >= 2:
		_is_host = false
		_name = "client%d" % (instance - 1)
	var pid_dir := ""
	for arg in args:
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"--role":
				_is_host = value == "host"
			"--name":
				_name = value
			"--impl":
				_impl = value
			"--timeouts":
				_timeout = REAL_TIMEOUT if value == "real" else SHORT_TIMEOUT
			"--address":
				_address = value
			"--bind":
				_bind = value
			"--port":
				_port = value.to_int()
			"--seconds":
				_seconds = value.to_float()
			"--pid-dir":
				pid_dir = value
			"--freeze":
				_freeze_at_ms = int(value.get_slice(":", 0).to_float() * 1000.0)
				_freeze_ms = value.get_slice(":", 1).to_int()
	if _is_host:
		_name = "host"
	_who = 0 if _is_host else (2 if _name == "client2" else 1)
	if _impl == "real":
		_timeout = REAL_TIMEOUT
	if pid_dir != "":
		DirAccess.make_dir_recursive_absolute(pid_dir)
		var file := FileAccess.open(pid_dir.path_join(_name + ".pid"), FileAccess.WRITE)
		if file != null:
			file.store_string(str(OS.get_process_id()))


func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	if _last_frame_us > 0:
		_max_frame_ms = maxf(_max_frame_ms, (now_us - _last_frame_us) / 1000.0)
	_last_frame_us = now_us
	if _freeze_at_ms >= 0 and Time.get_ticks_msec() - _started_ms >= _freeze_at_ms:
		_freeze_at_ms = -1
		_event("freezing the main thread for %d ms" % _freeze_ms)
		OS.delay_msec(_freeze_ms)
	_net.poll()
	_poll_side()
	var ticks := Time.get_ticks_msec()
	if ticks - _last_send_ms >= SEND_EVERY_MS:
		_last_send_ms = ticks
		_send()
	if ticks - _last_debug_ms >= DEBUG_EVERY_MS:
		_last_debug_ms = ticks
		_debug()
	var limit := _seconds + (HOST_EXTRA_S if _is_host else 0.0)
	if _seconds > 0.0 and (ticks - _started_ms) / 1000.0 >= limit:
		_finish()
	_label.text = "%s %s\n%s" % [_impl, _name, _status]
	queue_redraw()


func _draw() -> void:
	var origin := Vector2(8, 48)
	for who: int in _dots:
		draw_circle(origin + _dots[who], 8.0, Color.from_hsv(who * 0.3, 0.7, 0.95))


func _send() -> void:
	_seq += 1
	var bytes := PackedByteArray()
	bytes.resize(PACKET_SIZE)
	bytes.encode_u8(0, _who)
	bytes.encode_u32(1, _seq)
	bytes.encode_double(5, _wall_ms())
	if _is_host:
		_net.send_all(bytes)
		for key: String in _side_peers:
			if _wall_ms() - _side_peers[key] > GAP_LIMIT_MS:
				continue  # a killed client's port: stop, so the side channel sends nothing into the void
			_side.set_dest_address(key.get_slice(" ", 0), key.get_slice(" ", 1).to_int())
			_side.put_packet(bytes)
	else:
		_net.send_host(bytes)
		_side.put_packet(bytes)
	var angle := _seq * 0.05
	_dots[_who] = Vector2(60, 40) + Vector2(cos(angle), sin(angle)) * 30.0


func _poll_side() -> void:
	while _side.get_available_packet_count() > 0:
		var bytes := _side.get_packet()
		if _is_host:
			_side_peers["%s %d" % [_side.get_packet_ip(), _side.get_packet_port()]] = _wall_ms()
		_record(_side_rx, bytes)


func _record(table: Dictionary[int, Stats], bytes: PackedByteArray) -> void:
	if bytes.size() < 13:
		return
	var who := bytes.decode_u8(0)
	if not table.has(who):
		table[who] = Stats.new()
	table[who].add(_wall_ms(), bytes.decode_double(5), bytes.decode_u32(1))


func _on_packet(_from_id: int, bytes: PackedByteArray) -> void:
	_record(_rx, bytes)


func _on_left(id: int) -> void:
	_left.append(id)
	_event("left id=%d" % id)


func _on_connected() -> void:
	_status = "connected"
	_event("connected")


func _on_lost() -> void:
	_lost = true
	_status = "host lost"
	_event("host_lost")


func _debug() -> void:
	var conn := _net.conn()
	var counters := "enet=closed"
	var states := PackedStringArray()
	if conn != null:
		counters = (
			"enet_sent=%d enet_recv=%d"
			% [
				conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS),
				conn.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS),
			]
		)
		for p in conn.get_peers():
			(
				states
				. append(
					(
						"%d:s%d:rtt%.0f"
						% [
							p.get_remote_port(),
							p.get_state(),
							p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
						]
					)
				)
			)
	var rx := PackedStringArray()
	for who: int in _rx:
		rx.append("%d:%s" % [who, _rx[who].pop_window()])
	var side := PackedStringArray()
	for who: int in _side_rx:
		side.append("%d:%s" % [who, _side_rx[who].pop_window()])
	print(
		(
			"PROBE %s dbg wall=%d fps=%d maxframe=%.0f %s rx=[%s] side=[%s] peers=[%s]"
			% [
				_name,
				int(_wall_ms()),
				Engine.get_frames_per_second(),
				_max_frame_ms,
				counters,
				" ".join(rx),
				" ".join(side),
				" ".join(states),
			]
		)
	)
	_max_frame_ms = 0.0


func _finish() -> void:
	set_process(false)
	# The survivor's traffic: the host judges client 1, a client judges the host.
	var watched := 1 if _is_host else 0
	var stats: Stats = _rx.get(watched, Stats.new())
	var side: Stats = _side_rx.get(watched, Stats.new())
	if not _is_host and stats.last_ms > 0.0:
		# A client quits first, so silence up to its end counts as a gap.
		var trailing := _wall_ms() - stats.last_ms
		if trailing > stats.max_gap:
			stats.max_gap = trailing
			stats.max_gap_at = _wall_ms()
	var problems := PackedStringArray()
	if stats.count == 0:
		problems.append("never heard %d" % watched)
	if stats.max_gap > GAP_LIMIT_MS:
		problems.append("gap")
	if _lost:
		problems.append("host_lost")
	# Client 1 quits HOST_EXTRA_S before the host; a longer silence at the end is a drop.
	if (
		_is_host
		and stats.last_ms > 0.0
		and _wall_ms() - stats.last_ms > (HOST_EXTRA_S + 1.5) * 1000.0
	):
		problems.append("dropped")
	var verdict := "PASS" if problems.is_empty() else "FAIL(%s)" % ",".join(problems)
	var line := (
		"verdict %s watched=%d count=%d skipped=%d max_gap=%.0f@%d max_delay=%.0f@%d"
		+ " side_count=%d side_max_gap=%.0f@%d side_max_delay=%.0f left=%s"
	)
	_event(
		(
			line
			% [
				verdict,
				watched,
				stats.count,
				stats.skipped,
				stats.max_gap,
				int(stats.max_gap_at),
				stats.max_delay,
				int(stats.max_delay_at),
				side.count,
				side.max_gap,
				int(side.max_gap_at),
				side.max_delay,
				_left,
			]
		)
	)
	_net.close()
	_side.close()
	get_tree().quit(0 if problems.is_empty() else 1)


func _event(text: String) -> void:
	print("PROBE %s ev wall=%d %s" % [_name, int(_wall_ms()), text])


func _wall_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0
