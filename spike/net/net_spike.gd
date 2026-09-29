extends Control
## Spike (#13): host and clients over ENet on one machine. The host owns every position: a client
## sends only a move intent (a direction), the host moves that client's dot and broadcasts all
## positions. The host is not a player. User args after "--":
##   --host | --join ADDRESS   role (default --host)
##   --port N                  port (default 24560)
##   --auto                    a client walks in a circle by itself (WASD overrides it)
##   --quit-after-seconds N    exit with code 0 after N seconds
## Every process prints "NET ..." lines; spike/net/launch.ps1 starts three and checks the logs.

const BIND_IP := "127.0.0.1"
const DEFAULT_PORT := 24560
const MAX_CLIENTS := 8
const ARENA := Vector2(400, 200)
const SPEED := 80.0  # arena units per second
const SEND_EVERY := 0.05  # intents and position broadcasts at 20 Hz
const STATS_EVERY := 1.0
const HEADER_HEIGHT := 64.0

var _transport: SpikeTransport = SpikeEnetTransport.new()
var _is_host := true
var _address := BIND_IP
var _port := DEFAULT_PORT
var _auto := false
var _quit_after := -1.0
var _status := "starting"
var _elapsed := 0.0
var _since_send := 0.0
var _since_stats := 0.0
# Host: the authoritative state. Client: the last snapshot received.
var _positions: Dictionary[int, Vector2] = {}
# Host only.
var _dirs: Dictionary[int, Vector2] = {}
var _intents: Dictionary[int, int] = {}
var _rejected := 0
# Client only.
var _snapshots := 0
var _label := Label.new()


func _ready() -> void:
	_parse_args(OS.get_cmdline_user_args())
	_label.position = Vector2(12, 8)
	add_child(_label)
	_transport.peer_joined.connect(_on_peer_joined)
	_transport.peer_left.connect(_on_peer_left)
	_transport.packet_received.connect(_on_packet)
	_transport.connected.connect(_on_connected)
	_transport.connect_failed.connect(_on_connect_failed)
	_transport.disconnected.connect(_on_disconnected)
	var err: Error
	get_window().title = "net spike: %s" % ("host" if _is_host else "client")
	if _is_host:
		err = _transport.host(BIND_IP, _port, MAX_CLIENTS)
		_status = "listening on %s:%d" % [BIND_IP, _port]
	else:
		err = _transport.join(_address, _port)
		_status = "joining %s:%d" % [_address, _port]
	if err != OK:
		_status = "FAILED: %s" % error_string(err)
	_log(_status)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	_transport.poll()
	if _is_host:
		_host_step(delta)
	_since_send += delta
	if _since_send >= SEND_EVERY:
		_since_send = 0.0
		if _is_host:
			_broadcast_positions()
		else:
			_send_intent()
	_since_stats += delta
	if _since_stats >= STATS_EVERY:
		_since_stats = 0.0
		_log("t=%.1f %s" % [_elapsed, _summary()])
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		_log("quit %s" % _summary())
		get_tree().quit(0)
		set_process(false)
	_refresh()


func _exit_tree() -> void:
	_transport.close()


func _draw() -> void:
	var avail := size - Vector2(24, HEADER_HEIGHT + 12)
	var scale_by := minf(avail.x / ARENA.x, avail.y / ARENA.y)
	if scale_by <= 0.0:
		return
	var origin := Vector2(12, HEADER_HEIGHT)
	draw_rect(Rect2(origin, ARENA * scale_by), Color(0.5, 0.5, 0.5), false, 2.0)
	var font := ThemeDB.fallback_font
	for id: int in _positions:
		var at := origin + _positions[id] * scale_by
		var color := Color.from_hsv(fmod(id * 0.618, 1.0), 0.7, 0.95)
		var radius := 10.0 if id == _transport.own_id() else 7.0
		draw_circle(at, radius, color)
		draw_string(font, at + Vector2(12, 5), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _parse_args(args: PackedStringArray) -> void:
	for i in args.size():
		var next := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--host":
				_is_host = true
			"--join":
				_is_host = false
				_address = next if next != "" else BIND_IP
			"--port":
				_port = next.to_int()
			"--auto":
				_auto = true
			"--quit-after-seconds":
				_quit_after = next.to_float()


func _host_step(delta: float) -> void:
	for id: int in _positions:
		var moved := _positions[id] + _dirs[id] * SPEED * delta
		_positions[id] = moved.clamp(Vector2.ZERO, ARENA)


func _broadcast_positions() -> void:
	if _positions.is_empty():
		return
	var ids := PackedInt32Array(_positions.keys())
	var points := PackedVector2Array(_positions.values())
	_transport.send(SpikeTransport.EVERYONE, SpikeNetMessages.encode_positions(ids, points), false)


func _send_intent() -> void:
	if _transport.own_id() == 0 or _status != "connected":
		return
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if dir == Vector2.ZERO and _auto:
		var phase := float(_transport.own_id() % 628) / 100.0
		dir = Vector2(cos(_elapsed * 1.5 + phase), sin(_elapsed * 1.5 + phase))
	var bytes := SpikeNetMessages.encode_move_intent(dir.limit_length(1.0))
	_transport.send(SpikeTransport.HOST_ID, bytes, false)


func _on_peer_joined(id: int) -> void:
	_log("peer_joined id=%d" % id)
	if not _is_host:
		return
	_positions[id] = ARENA / 2.0 + Vector2(40.0 * (_positions.size() % 5) - 80.0, 0.0)
	_dirs[id] = Vector2.ZERO
	_intents[id] = 0


func _on_peer_left(id: int) -> void:
	_log("peer_left id=%d" % id)
	if _is_host:
		_positions.erase(id)
		_dirs.erase(id)
		_intents.erase(id)


func _on_connected(own_id: int) -> void:
	_status = "connected"
	_log("connected id=%d" % own_id)
	get_window().title = "net spike: client %d" % own_id


func _on_connect_failed() -> void:
	_status = "connection failed"
	_log(_status)


func _on_disconnected() -> void:
	_status = "server disconnected"
	_positions.clear()
	_log(_status)


func _on_packet(from_peer: int, bytes: PackedByteArray) -> void:
	var msg := SpikeNetMessages.decode(bytes)
	if _is_host:
		_host_receive(from_peer, msg, bytes.size())
	else:
		_client_receive(from_peer, msg, bytes.size())


func _host_receive(from_peer: int, msg: Array, size_bytes: int) -> void:
	# Clients send intents, never state: anything else, or a peer the host does not know, is dropped.
	if msg.is_empty() or msg[0] != SpikeNetMessages.KIND_MOVE_INTENT or not _dirs.has(from_peer):
		_rejected += 1
		_log("rejected %d bytes from id=%d" % [size_bytes, from_peer])
		return
	var dir: Vector2 = msg[1]
	_dirs[from_peer] = dir.limit_length(1.0)
	_intents[from_peer] += 1
	if _intents[from_peer] == 1:
		_log("first_intent id=%d dir=%s" % [from_peer, _dirs[from_peer]])


func _client_receive(from_peer: int, msg: Array, size_bytes: int) -> void:
	if (
		from_peer != SpikeTransport.HOST_ID
		or msg.is_empty()
		or msg[0] != SpikeNetMessages.KIND_POSITIONS
	):
		_log("rejected %d bytes from id=%d" % [size_bytes, from_peer])
		return
	var ids: PackedInt32Array = msg[1]
	var points: PackedVector2Array = msg[2]
	var fresh: Dictionary[int, Vector2] = {}
	for i in ids.size():
		fresh[ids[i]] = points[i]
		if not _positions.has(ids[i]):
			_log("sees id=%d" % ids[i])
	for id: int in _positions:
		if not fresh.has(id):
			_log("lost id=%d" % id)
	_positions = fresh
	_snapshots += 1


func _summary() -> String:
	var players := PackedStringArray()
	var ids := _positions.keys()
	ids.sort()
	for id: int in ids:
		players.append("%d@(%.0f,%.0f)" % [id, _positions[id].x, _positions[id].y])
	if _is_host:
		return "peers=[%s] intents=%s rejected=%d" % [",".join(players), _intents, _rejected]
	return (
		"id=%d status=%s snapshots=%d players=[%s]"
		% [_transport.own_id(), _status, _snapshots, ",".join(players)]
	)


func _refresh() -> void:
	var role := "HOST" if _is_host else "CLIENT"
	var id := _transport.own_id()
	_label.text = "%s  peer id %s\n%s" % [role, str(id) if id != 0 else "-", _status]
	queue_redraw()


func _log(line: String) -> void:
	print("NET %s %s" % ["host" if _is_host else "client", line])
