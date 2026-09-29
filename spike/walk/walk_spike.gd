extends Node3D
## Spike (#14): first-person capsules walking in a greybox room over the #13 ENet transport.
## Movement is client-side (ARCHITECTURE §7): each client moves its own CharacterBody3D and
## reports its position; the host checks every report (SpikeMoveCheck), corrects a client that
## moved too fast or teleported, and broadcasts snapshots of accepted positions. Every window
## shows the other players interpolated between snapshots (SpikeSnapshotBuffer). The host is not
## a player: it watches from above. User args after "--":
##   --host | --join ADDRESS   role (default --host)
##   --port N                  port (default 24560)
##   --tick-hz N               moves and snapshots per second (default 20)
##   --interp-ticks N          interpolation delay in ticks (default 2)
##   --auto                    a client walks in a circle by itself (WASD and the mouse override it)
##   --quit-after-seconds N    exit with code 0 after N seconds
##   --screenshot-at S --screenshot PATH   save the window as a PNG after S seconds (not headless)
##   --cheat-teleport-at S     a client jumps 5 m forward once, at S seconds
##   --cheat-speed-at S        a client walks at triple speed for 1.5 s, from S seconds
##   --sim-latency-ms N --sim-jitter-ms N --sim-loss P
##                             delay incoming MOVE and SNAPSHOT packets by N + random(0, jitter) ms
##                             and drop a share P of them, like a real network (seeded; PLACE is
##                             reliable and passes untouched). Out-of-order ones are then dropped as
##                             ENet's unreliable ordered mode would.
## Every process prints "WALK ..." lines; spike/walk/launch.ps1 starts three and checks the logs.

const ROOM := preload("res://spike/walk/greybox_room.tscn")
const BIND_IP := "127.0.0.1"
const DEFAULT_PORT := 24560
const MAX_CLIENTS := SpikeWalkMessages.MAX_PLAYERS
const MAX_REJECT_LOGS := 5  # a flooding peer must not fill the log; the stats line keeps the count
const STATS_EVERY := 1.0
const WALK_SPEED := 4.5  # m/s; the host allows SpikeMoveCheck.max_speed (6) with slack
const AUTO_TURN := 1.5  # rad/s to the right while --auto: a 3 m circle, centred 3 m right of spawn
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025  # rad per screen pixel
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.8
const EYE_OFFSET := 0.7  # camera above the capsule centre
const SEES_MOVING_AFTER := 1.0  # metres a remote player must move before "sees_moving" is logged
# Facing -Z; the --auto circles of the first two stay clear of the walls, the others brush the
# inner wall.
const SPAWNS: Array[Vector3] = [
	Vector3(-7, 1, 2.5), Vector3(-7, 1, -2.5), Vector3(3.6, 1, 2.5), Vector3(3.6, 1, -2.5)
]

var _transport: SpikeTransport = SpikeEnetTransport.new()
var _is_host := true
var _address := BIND_IP
var _port := DEFAULT_PORT
var _tick_hz := 20.0
var _interp_ticks := 2.0
var _auto := false
var _quit_after := -1.0
var _screenshot_at := -1.0
var _screenshot_path := ""
var _cheat_teleport_at := -1.0
var _cheat_speed_at := -1.0
var _sim_latency := 0.0
var _sim_jitter := 0.0
var _sim_loss := 0.0
var _sim_rng := RandomNumberGenerator.new()
# [release time, from peer, bytes, arrival seq], in arrival order
var _sim_queue: Array[Array] = []
var _sim_seq := 0
var _sim_last_seq: Dictionary[int, int] = {}
var _sim_dropped := 0  # lost or out of order
var _status := "starting"
var _clock := 0.0
var _since_send := 0.0
var _since_stats := 0.0
var _tick := 0
var _buffer := SpikeSnapshotBuffer.new()
# Remote players (every player, on the host), by peer id.
var _avatars: Dictionary[int, Node3D] = {}
var _label := Label.new()
# Host only.
var _check := SpikeMoveCheck.new()
var _yaws: Dictionary[int, float] = {}
var _moves: Dictionary[int, int] = {}
var _verdicts: Dictionary[String, int] = {}
var _rejected_logs := 0
var _joined := 0
# Client only.
var _body: CharacterBody3D
var _camera: Camera3D
var _epoch := 0  # 0 until the host places this client; it does not move before that
var _snapshots := 0
var _corrections := 0
var _first_seen: Dictionary[int, Vector3] = {}
var _seen_moving: Dictionary[int, bool] = {}


func _ready() -> void:
	_parse_args(OS.get_cmdline_user_args())
	_buffer.tick_hz = _tick_hz
	_buffer.delay = _interp_ticks / _tick_hz
	add_child(ROOM.instantiate())
	var hud := CanvasLayer.new()
	_label.position = Vector2(12, 8)
	hud.add_child(_label)
	add_child(hud)
	_transport.peer_joined.connect(_on_peer_joined)
	_transport.peer_left.connect(_on_peer_left)
	_transport.packet_received.connect(_on_packet)
	_transport.connected.connect(_on_connected)
	_transport.connect_failed.connect(_on_connect_failed)
	_transport.disconnected.connect(_on_disconnected)
	var err: Error
	get_window().title = "walk spike: %s" % ("host" if _is_host else "client")
	if _is_host:
		_spawn_overhead_camera()
		err = _transport.host(BIND_IP, _port, MAX_CLIENTS)
		_status = "listening on %s:%d" % [BIND_IP, _port]
	else:
		_spawn_local_player()
		err = _transport.join(_address, _port)
		_status = "joining %s:%d" % [_address, _port]
	if err != OK:
		_status = "FAILED: %s" % error_string(err)
	_log(_status)
	_sim_rng.seed = 14
	_log(
		(
			"tick_hz=%.0f interp_delay_ms=%.0f sim_latency_ms=%.0f sim_jitter_ms=%.0f sim_loss=%.2f"
			% [_tick_hz, _buffer.delay * 1000.0, _sim_latency * 1000, _sim_jitter * 1000, _sim_loss]
		)
	)


func _process(delta: float) -> void:
	_clock += delta
	# Refill the move budget before reading this frame's packets: after a long frame (a hitch, a
	# screenshot) the moves queued during it arrive at once and must find the time already paid.
	if _is_host:
		_check.advance(delta)
	_transport.poll()
	_release_simulated()
	# A fixed-rate tick, so tick / tick_hz tracks the sender's clock; after a long frame it
	# restarts instead of sending a burst.
	var interval := 1.0 / _tick_hz
	_since_send += delta
	if _since_send >= interval:
		_since_send = _since_send - interval if _since_send < 2.0 * interval else 0.0
		_tick += 1
		if _is_host:
			_broadcast_snapshot()
		else:
			_send_move()
	_update_avatars()
	_buffer.relax(delta)
	_since_stats += delta
	if _since_stats >= STATS_EVERY:
		_since_stats = 0.0
		_log("t=%.1f %s" % [_clock, _summary()])
	if _screenshot_at >= 0.0 and _clock >= _screenshot_at:
		_screenshot_at = -1.0
		_save_screenshot()
	if _quit_after > 0.0 and _clock >= _quit_after:
		_log("quit %s" % _summary())
		get_tree().quit(0)
		set_process(false)
	_refresh_label()


func _physics_process(delta: float) -> void:
	if _is_host or _epoch == 0:
		return
	var speed := WALK_SPEED
	if _cheat_speed_at >= 0.0 and _clock >= _cheat_speed_at and _clock < _cheat_speed_at + 1.5:
		speed *= 3.0
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if input == Vector2.ZERO and _auto:
		_body.rotation.y -= AUTO_TURN * delta
		input = Vector2(0, -1)
	var wish := _body.global_basis * Vector3(input.x, 0, input.y)
	wish.y = 0.0
	wish = wish.normalized() * speed
	_body.velocity.x = wish.x
	_body.velocity.z = wish.z
	_body.velocity.y = 0.0 if _body.is_on_floor() else _body.velocity.y - GRAVITY * delta
	_body.move_and_slide()
	if _cheat_teleport_at >= 0.0 and _clock >= _cheat_teleport_at:
		_cheat_teleport_at = -1.0
		_body.global_position += -_body.global_basis.z * 5.0
		_log("cheat teleport to %s" % _fmt(_body.global_position))


func _unhandled_input(event: InputEvent) -> void:
	if _is_host:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).screen_relative
		_body.rotation.y -= motion.x * MOUSE_SENSITIVITY
		_camera.rotation.x = clampf(
			_camera.rotation.x - motion.y * MOUSE_SENSITIVITY, -PI * 0.45, PI * 0.45
		)


func _exit_tree() -> void:
	_transport.close()


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
			"--tick-hz":
				_tick_hz = clampf(next.to_float(), 1.0, 120.0)
			"--interp-ticks":
				_interp_ticks = clampf(next.to_float(), 0.0, 20.0)
			"--auto":
				_auto = true
			"--quit-after-seconds":
				_quit_after = next.to_float()
			"--screenshot-at":
				_screenshot_at = next.to_float()
			"--screenshot":
				_screenshot_path = next
			"--cheat-teleport-at":
				_cheat_teleport_at = next.to_float()
			"--cheat-speed-at":
				_cheat_speed_at = next.to_float()
			"--sim-latency-ms":
				_sim_latency = maxf(next.to_float(), 0.0) / 1000.0
			"--sim-jitter-ms":
				_sim_jitter = maxf(next.to_float(), 0.0) / 1000.0
			"--sim-loss":
				_sim_loss = clampf(next.to_float(), 0.0, 1.0)


func _spawn_overhead_camera() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 17, 12), Vector3(0, 0, 0.5))
	camera.current = true


func _spawn_local_player() -> void:
	_body = CharacterBody3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_body.add_child(collision)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, EYE_OFFSET, 0)
	_camera.current = true
	_body.add_child(_camera)
	_body.position = Vector3(0, 1, 0)
	add_child(_body)


func _new_avatar(id: int) -> Node3D:
	var color := Color.from_hsv(fmod(id * 0.618, 1.0), 0.65, 0.95)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var capsule := CapsuleMesh.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	capsule.material = material
	var avatar := MeshInstance3D.new()
	avatar.mesh = capsule
	# A dark visor on the front (-Z) shows where the player looks.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.4, 0.15, 0.2)
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color(0.1, 0.1, 0.12)
	visor_mesh.material = visor_material
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0, EYE_OFFSET - 0.05, -CAPSULE_RADIUS + 0.05)
	avatar.add_child(visor)
	add_child(avatar)
	return avatar


func _update_avatars() -> void:
	var own := _transport.own_id()
	var ids := _buffer.ids()
	for id: int in _avatars.keys():
		if not ids.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)
	for id: int in ids:
		if id == own and not _is_host:
			continue
		if not _avatars.has(id):
			_avatars[id] = _new_avatar(id)
		var s := _buffer.sample(id, _clock)
		var pos: Vector3 = s[0]
		_avatars[id].position = pos
		_avatars[id].rotation = Vector3(0, s[1] as float, 0)
		if not _is_host and not _seen_moving.has(id) and _first_seen.has(id):
			if pos.distance_to(_first_seen[id]) > SEES_MOVING_AFTER:
				_seen_moving[id] = true
				_log("sees_moving id=%d" % id)


func _broadcast_snapshot() -> void:
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for id: int in _yaws:
		ids.append(id)
		positions.append(_check.position_of(id))
		yaws.append(_yaws[id])
	# The host shows the same view a client gets, through its own buffer.
	_buffer.push(_clock, _tick, ids, positions, yaws)
	if ids.is_empty():
		return
	var bytes := SpikeWalkMessages.encode_snapshot(_tick, ids, positions, yaws)
	_transport.send(SpikeTransport.EVERYONE, bytes, false)


func _send_move() -> void:
	if _epoch == 0 or _status != "connected":
		return
	var bytes := SpikeWalkMessages.encode_move(_epoch, _body.global_position, _body.rotation.y)
	_transport.send(SpikeTransport.HOST_ID, bytes, false)


func _on_peer_joined(id: int) -> void:
	_log("peer_joined id=%d" % id)
	if not _is_host:
		return
	var spawn := SPAWNS[_joined % SPAWNS.size()]
	_joined += 1
	var epoch := _check.place(id, spawn)
	_yaws[id] = 0.0
	_moves[id] = 0
	_transport.send(id, SpikeWalkMessages.encode_place(epoch, spawn), true)


func _on_peer_left(id: int) -> void:
	_log("peer_left id=%d" % id)
	# Nothing arrives from a peer after it has left, delayed or not.
	var kept: Array[Array] = []
	kept.assign(_sim_queue.filter(func(item: Array) -> bool: return item[1] != id))
	_sim_queue = kept
	if _is_host:
		_check.forget(id)
		_yaws.erase(id)
		_moves.erase(id)


func _on_connected(own_id: int) -> void:
	_status = "connected"
	_log("connected id=%d" % own_id)
	get_window().title = "walk spike: client %d" % own_id


func _on_connect_failed() -> void:
	_status = "connection failed"
	_log(_status)


func _on_disconnected() -> void:
	_status = "server disconnected"
	_log(_status)


func _on_packet(from_peer: int, bytes: PackedByteArray) -> void:
	var simulated := _sim_latency > 0.0 or _sim_jitter > 0.0 or _sim_loss > 0.0
	if simulated and not _is_reliable_kind(bytes):
		if _sim_rng.randf() < _sim_loss:
			_sim_dropped += 1
			return
		var release := _clock + _sim_latency + _sim_rng.randf() * _sim_jitter
		_sim_seq += 1
		_sim_queue.append([release, from_peer, bytes, _sim_seq])
		return
	_handle_packet(from_peer, bytes)


func _is_reliable_kind(bytes: PackedByteArray) -> bool:
	var msg := SpikeWalkMessages.decode(bytes)
	return not msg.is_empty() and msg[0] == SpikeWalkMessages.KIND_PLACE


## Delivers the simulated packets that are due, and drops those overtaken by a newer one, as
## ENet's unreliable ordered mode does.
func _release_simulated() -> void:
	var due: Array[Array] = []
	var waiting: Array[Array] = []
	for item: Array in _sim_queue:
		if (item[0] as float) <= _clock:
			due.append(item)
		else:
			waiting.append(item)
	_sim_queue = waiting
	due.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as float) < (b[0] as float))
	for item: Array in due:
		var from_peer: int = item[1]
		var seq: int = item[3]
		if seq < _sim_last_seq.get(from_peer, 0):
			_sim_dropped += 1
			continue
		_sim_last_seq[from_peer] = seq
		_handle_packet(from_peer, item[2] as PackedByteArray)


func _handle_packet(from_peer: int, bytes: PackedByteArray) -> void:
	var msg := SpikeWalkMessages.decode(bytes)
	if _is_host:
		_host_receive(from_peer, msg, bytes.size())
	else:
		_client_receive(from_peer, msg, bytes.size())


func _host_receive(from_peer: int, msg: Array, size_bytes: int) -> void:
	# A client may only report its own movement, and only once the host has placed it.
	if msg.is_empty() or msg[0] != SpikeWalkMessages.KIND_MOVE or not _check.has_peer(from_peer):
		_count_reject("malformed", from_peer, "%d bytes" % size_bytes)
		return
	var pos: Vector3 = msg[2]
	var verdict := _check.check(from_peer, msg[1] as int, pos)
	var verdict_name := SpikeMoveCheck.VERDICT_NAMES[verdict]
	_verdicts[verdict_name] = _verdicts.get(verdict_name, 0) + 1
	match verdict:
		SpikeMoveCheck.Verdict.ACCEPTED:
			_yaws[from_peer] = wrapf(msg[3] as float, -PI, PI)
			_moves[from_peer] += 1
			if _moves[from_peer] == 1:
				_log("first_move id=%d pos=%s" % [from_peer, _fmt(pos)])
		SpikeMoveCheck.Verdict.STALE:
			pass
		_:
			# Back to the last accepted position, in a new epoch.
			var back := _check.position_of(from_peer)
			var epoch := _check.place(from_peer, back)
			_transport.send(from_peer, SpikeWalkMessages.encode_place(epoch, back), true)
			_count_reject(verdict_name, from_peer, "at %s, back to %s" % [_fmt(pos), _fmt(back)])


func _count_reject(reason: String, from_peer: int, detail: String) -> void:
	if reason == "malformed":
		_verdicts[reason] = _verdicts.get(reason, 0) + 1
	_rejected_logs += 1
	if _rejected_logs <= MAX_REJECT_LOGS:
		_log("rejected %s id=%d %s" % [reason, from_peer, detail])


func _client_receive(from_peer: int, msg: Array, size_bytes: int) -> void:
	if from_peer != SpikeTransport.HOST_ID or msg.is_empty():
		_log("rejected %d bytes from id=%d" % [size_bytes, from_peer])
		return
	match msg[0] as int:
		SpikeWalkMessages.KIND_PLACE:
			var pos: Vector3 = msg[2]
			if _epoch == 0:
				_log("placed epoch=%d pos=%s" % [msg[1] as int, _fmt(pos)])
			else:
				_corrections += 1
				_log("corrected epoch=%d pos=%s" % [msg[1] as int, _fmt(pos)])
			_epoch = msg[1]
			_body.global_position = pos
			_body.velocity = Vector3.ZERO
		SpikeWalkMessages.KIND_SNAPSHOT:
			_client_snapshot(msg)
		_:
			_log("rejected %d bytes from id=%d" % [size_bytes, from_peer])


func _client_snapshot(msg: Array) -> void:
	var ids: PackedInt32Array = msg[2]
	var positions: PackedVector3Array = msg[3]
	var own := _transport.own_id()
	for i in ids.size():
		if ids[i] != own and not _first_seen.has(ids[i]):
			_first_seen[ids[i]] = positions[i]
			_log("sees id=%d" % ids[i])
	for id: int in _first_seen.keys():
		if not ids.has(id):
			_first_seen.erase(id)
			_seen_moving.erase(id)
			_log("lost id=%d" % id)
	_buffer.push(_clock, msg[1] as int, ids, positions, msg[4] as PackedFloat32Array)
	_snapshots += 1


func _save_screenshot() -> void:
	if DisplayServer.get_name() == "headless" or _screenshot_path == "":
		return
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(_screenshot_path)
	_log("screenshot %s %s" % [_screenshot_path, error_string(err)])


func _summary() -> String:
	# The host lists its accepted positions; a client lists the remote players it shows.
	var players := PackedStringArray()
	var ids: Array[int] = []
	ids.assign(_yaws.keys() if _is_host else _avatars.keys())
	ids.sort()
	var own := _transport.own_id()
	for id: int in ids:
		var pos := _check.position_of(id) if _is_host else _avatars[id].position
		players.append("%d@%s" % [id, _fmt(pos)])
	var interp := (
		"interpolated=%d starved=%d sim_dropped=%d"
		% [_buffer.interpolated, _buffer.starved, _sim_dropped]
	)
	if _is_host:
		return "peers=[%s] moves=%s verdicts=%s %s" % [",".join(players), _moves, _verdicts, interp]
	var at := _fmt(_body.global_position) if _epoch != 0 else "-"
	return (
		"id=%d status=%s epoch=%d at=%s snapshots=%d corrections=%d %s players=[%s]"
		% [own, _status, _epoch, at, _snapshots, _corrections, interp, ",".join(players)]
	)


func _refresh_label() -> void:
	var role := "HOST (not a player)" if _is_host else "CLIENT"
	var id := _transport.own_id()
	_label.text = (
		"%s  peer id %s\n%s\ntick %.0f Hz, interpolation delay %.0f ms\n%s"
		% [
			role,
			str(id) if id != 0 else "-",
			_status,
			_tick_hz,
			_buffer.delay * 1000.0,
			"" if _is_host else "click: mouse look, Esc: release, WASD: walk",
		]
	)


static func _fmt(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]


func _log(line: String) -> void:
	print("WALK %s %s" % ["host" if _is_host else "client", line])
