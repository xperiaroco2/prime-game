extends Node3D
## Spike (#14): first-person capsules walking in a greybox room over the #13 ENet transport.
## Movement is client-side (ARCHITECTURE §7): each client moves its own CharacterBody3D and
## reports its position; the host checks every report (SpikeMoveCheck), corrects a client that
## moved too fast or teleported, and broadcasts snapshots of accepted positions. Every window
## shows the other players interpolated between snapshots (SpikeSnapshotBuffer). The host is not
## a player: it watches from above. User args after "--":
##   --host | --join ADDRESS   role (default --host)
##   --bind IP                 the host's listening address (default 127.0.0.1; 0.0.0.0 for a LAN)
##   --port N                  port (default 24560)
##   --tick-hz N               moves and snapshots per second (default 20)
##   --interp-ticks N          interpolation delay in ticks (default 2)
##   --auto                    a client walks in a circle by itself (WASD and the mouse override it)
##   --quit-after-seconds N    exit with code 0 after N seconds
##   --screenshot-at S --screenshot PATH   save the window as a PNG after S seconds (not headless)
##   --cheat-teleport-at S     a client jumps 5 m towards the room centre once, at S seconds
##   --cheat-speed-at S        a client moves at triple speed through walls for 1.5 s from S s
##   --sim-latency-ms N --sim-jitter-ms N --sim-loss P
##                             delay incoming MOVE and SNAPSHOT packets by N + random(0, jitter) ms
##                             and drop a share P of them, like a real network (seeded; PLACE is
##                             reliable and passes untouched). Out-of-order ones are then dropped as
##                             ENet's unreliable ordered mode would. Voice frames are delayed and
##                             lost too, but arrive out of order (they are sent unordered).
## Proximity voice (#15, spike/voice/): a client speaks, the host relays each frame only to the
## listeners its routing rule allows (a distance cutoff, SpikeVoiceRelay), and each listener plays
## it from an AudioStreamPlayer3D on the speaker's capsule (SpikeVoiceSpeaker), on a "Voice" bus
## whose peak level every client logs with the distance ("WALK client level ...").
##   --voice off|mic|tone      what a client speaks (default off; listening is always on)
##   --tone-hz N               the tone's pitch (default 440)
##   --mic-device NAME         the microphone by its name in the logged "voice input devices"
##                             (default: the Windows default; Godot 4.7.2 takes mono or stereo only)
##   --voice-cutoff M          the host's delivery cutoff and the players' max_distance (default 8)
##   --mute-output             mute the Master bus; the Voice bus is still mixed and measured
## Latency and CPU (#16): the speaker's client, the host and each listener log every 25th voice
## frame on the system clock ("lat_send", "lat_host", "lat_play"), so a one-machine run's logs give
## the latency of each leg; the voice lines add the mean encode, decode and relay times.
##   --click-every S           a listener clicks through its loudspeaker every S s (+-20 %) and
##                             plays voice only just after each (SpikeVoiceClicks)
##   --detect-clicks           the microphone client finds those clicks and their relayed echoes
##                             in its raw samples ("click_echo ms=..."): the mouth-to-ear latency
##                             (SpikeVoiceOnsets)
##   --no-denoise              RNNoise off for the microphone
##   --mic-dump PATH           save the raw microphone samples to a WAV file on quit
##   --voice-gain-db N         the Voice bus volume (default 0): louder relayed clicks, same timing
## Every process prints "WALK ..." lines; spike/walk/launch.ps1 starts three and checks the logs.

const ROOM := preload("res://spike/walk/greybox_room.tscn")
const BIND_IP := "127.0.0.1"
const DEFAULT_PORT := 24560
const MAX_CLIENTS := SpikeWalkMessages.MAX_PLAYERS
const MAX_REJECT_LOGS := 5  # a flooding peer must not fill the log; the stats line keeps the count
const STATS_EVERY := 1.0
const WALK_SPEED := 4.5  # m/s; also the host's SpikeMoveCheck.max_speed (x slack 1.25)
## rad/s to the right while --auto (to the left from a z < 0 spawn): a 3 m circle whose centre is
## 3 m to the side, towards +X.
const AUTO_TURN := 1.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025  # rad per screen pixel
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.8
const EYE_OFFSET := 0.7  # camera above the capsule centre
const SEES_MOVING_AFTER := 1.0  # metres a remote player must move before "sees_moving" is logged
const VOICE_BUS := &"Voice"
const MOUTH := Vector3(0, EYE_OFFSET - 0.1, 0)  # the voice player on an avatar
const LEVEL_EVERY := 0.25  # seconds between "level" lines
const SILENT_DB := -200.0  # the floor the level lines report for no signal
# The --auto circles of the first two stay clear of the walls, the others brush the inner wall.
const SPAWNS: Array[Vector3] = [
	Vector3(-7, 1, 2.5), Vector3(-7, 1, -2.5), Vector3(3.6, 1, 2.5), Vector3(3.6, 1, -2.5)
]

var _transport: SpikeTransport = SpikeEnetTransport.new()
var _is_host := true
var _bind_ip := BIND_IP
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
var _cheat_dir := Vector3.ZERO
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
# Kept after a disconnect, when the transport reports 0, so the own capsule never becomes remote.
var _own_id := 0
var _clock := 0.0
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
var _rejected_logs: Dictionary[int, int] = {}  # per peer, so one cheater cannot hide another
var _joined := 0
# Client only.
var _body: CharacterBody3D
var _camera: Camera3D
var _epoch := 0  # 0 until the host places this client; it does not move before that
var _auto_turn := AUTO_TURN
var _snapshots := 0
var _corrections := 0
var _first_seen: Dictionary[int, Vector3] = {}
var _seen_moving: Dictionary[int, bool] = {}
# Voice.
var _voice := "off"
var _tone_hz := 440.0
var _mic_device := ""
var _cutoff := 8.0
var _mute_output := false
var _click_every := 0.0
var _detect_clicks := false
var _denoise := true
var _mic_dump_path := ""
var _voice_gain_db := 0.0
# Voice, host only.
var _relay := SpikeVoiceRelay.new()
var _relay_usec := 0
var _relay_calls := 0
var _voice_pairs_logged: Dictionary[String, bool] = {}
var _payload_out_before := 0
var _voice_kbps := 0.0
var _net_kbps := 0.0
# Voice, client only.
var _source: SpikeVoiceSource
var _voice_seq := 0
var _voice_sent := 0
var _speakers: Dictionary[int, SpikeVoiceSpeaker] = {}
var _speakers_failed: Dictionary[int, bool] = {}
var _voice_no_avatar := 0
var _voice_bus := -1
var _level_db := SILENT_DB
var _since_level := 0.0
var _mic_meter := 0.0  # on screen: the microphone's recent peak, falling back slowly
var _heard_db := SILENT_DB  # on screen: the Voice bus's recent peak
var _clicks := SpikeVoiceClicks.new(_log)
var _last_throttle := ""


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
		# The host allows the walking speed; SpikeMoveCheck.slack covers the jitter.
		_check.max_speed = WALK_SPEED
		_relay.routing.cutoff = _cutoff
		err = _transport.host(_bind_ip, _port, MAX_CLIENTS)
		_own_id = SpikeTransport.HOST_ID if err == OK else 0
		_status = "listening on %s:%d" % [_bind_ip, _port]
	else:
		_spawn_local_player()
		_setup_voice()
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
		_relay.advance(delta)
	_transport.poll()
	_release_simulated()
	if not _is_host:
		_update_voice(delta)
	_log_throttle_changes()
	# The tick comes from the clock, so tick / tick_hz stays the sender's time; after a long frame
	# (or a tick rate above the frame rate) ticks are skipped, never sent in a burst.
	var tick := floori(_clock * _tick_hz)
	if tick > _tick:
		_tick = tick
		if _is_host:
			_broadcast_snapshot()
		else:
			_send_move()
	_update_avatars()
	_since_stats += delta
	if _since_stats >= STATS_EVERY:
		_measure_bandwidth(_since_stats)
		_since_stats = 0.0
		_log("t=%.1f %s" % [_clock, _summary()])
		_log("voice t=%.1f %s" % [_clock, _voice_summary()])
		var enet := _transport as SpikeEnetTransport
		if enet != null:
			_log(
				(
					"enet t=%.1f fps=%.0f %s"
					% [_clock, Engine.get_frames_per_second(), enet.peers_line()]
				)
			)
	if _screenshot_at >= 0.0 and _clock >= _screenshot_at:
		_screenshot_at = -1.0
		_save_screenshot()
	if _quit_after > 0.0 and _clock >= _quit_after:
		_save_mic_dump()
		if _source != null and _source.detector != null:
			_clicks.log_echoes(_source.detector.rate)
		_log("voice quit %s" % _voice_summary())
		_log("quit %s" % _summary())
		get_tree().quit(0)
		set_process(false)
	_refresh_label()


func _physics_process(delta: float) -> void:
	if _is_host or _epoch == 0:
		return
	if _cheat_speed_at >= 0.0 and _clock >= _cheat_speed_at and _clock < _cheat_speed_at + 1.5:
		# A speed hack with noclip, so no wall can slow it down: straight towards the room centre
		# from wherever it starts, at triple speed.
		if _cheat_dir == Vector3.ZERO:
			_cheat_dir = Vector3(-_body.position.x, 0, -_body.position.z).normalized()
			_log("cheat speed towards %s" % _fmt(_cheat_dir))
		_body.global_position += _cheat_dir * WALK_SPEED * 3.0 * delta
		return
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if input == Vector2.ZERO and _auto:
		_body.rotation.y -= _auto_turn * delta
		input = Vector2(0, -1)
	var wish := _body.global_basis * Vector3(input.x, 0, input.y)
	wish.y = 0.0
	wish = wish.normalized() * WALK_SPEED
	_body.velocity.x = wish.x
	_body.velocity.z = wish.z
	_body.velocity.y = 0.0 if _body.is_on_floor() else _body.velocity.y - GRAVITY * delta
	_body.move_and_slide()
	if _cheat_teleport_at >= 0.0 and _clock >= _cheat_teleport_at:
		_cheat_teleport_at = -1.0
		# Towards the room centre, so the jump stays inside the room: a teleport, not out of bounds.
		_body.global_position += Vector3(-_body.position.x, 0, -_body.position.z).normalized() * 5.0
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
	if _source != null:
		_save_mic_dump()
		if _source != null and _source.detector != null:
			_clicks.log_echoes(_source.detector.rate)
		_source.stop()
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
			"--bind":
				_bind_ip = next if next != "" else BIND_IP
			"--port":
				_port = next.to_int()
			"--voice":
				_voice = next if next in ["off", "mic", "tone"] else "off"
			"--tone-hz":
				_tone_hz = clampf(next.to_float(), 50.0, 4000.0)
			"--mic-device":
				_mic_device = next
			"--voice-cutoff":
				_cutoff = clampf(next.to_float(), 0.5, 100.0)
			"--mute-output":
				_mute_output = true
			"--voice-gain-db":
				_voice_gain_db = clampf(next.to_float(), -60.0, 24.0)
			"--click-every":
				_click_every = clampf(next.to_float(), 0.0, 60.0)
			"--detect-clicks":
				_detect_clicks = true
			"--no-denoise":
				_denoise = false
			"--mic-dump":
				_mic_dump_path = next
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
	# Steep enough that the near wall hides no one.
	camera.look_at_from_position(Vector3(0, 12, 4), Vector3(0, 0, 0.4))
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
	var own := _own_id
	var ids := _buffer.ids()
	for id: int in _avatars.keys():
		if not ids.has(id):
			# The voice player is a child of the avatar and goes with it.
			_avatars[id].queue_free()
			_avatars.erase(id)
			_speakers.erase(id)
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
		_relay.forget(id)
		_yaws.erase(id)
		_moves.erase(id)


func _on_connected(own_id: int) -> void:
	_own_id = own_id
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
		# Voice travels unordered on its own channel: late voice frames still arrive.
		var ordered := SpikeVoiceMessages.decode(bytes).is_empty()
		_sim_queue.append([release, from_peer, bytes, _sim_seq, ordered])
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
		if item[4] as bool:
			if seq < _sim_last_seq.get(from_peer, 0):
				_sim_dropped += 1
				continue
			_sim_last_seq[from_peer] = seq
		_handle_packet(from_peer, item[2] as PackedByteArray)


func _handle_packet(from_peer: int, bytes: PackedByteArray) -> void:
	var t0 := Time.get_ticks_usec()
	var voice := SpikeVoiceMessages.decode(bytes)
	if not voice.is_empty():
		if _is_host:
			_host_voice(from_peer, voice)
			# The host's whole cost of one voice frame: decoding the message, routing, sending.
			_relay_usec += Time.get_ticks_usec() - t0
			_relay_calls += 1
			var seq: int = voice[1]
			if voice[0] == SpikeVoiceMessages.KIND_VOICE_UP and SpikeVoiceSpeaker.is_timed(seq):
				var now := Time.get_unix_time_from_system()
				_log("lat_host from=%d seq=%d unix=%.4f" % [from_peer, seq, now])
		else:
			_client_voice(from_peer, voice)
		return
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
	_rejected_logs[from_peer] = _rejected_logs.get(from_peer, 0) + 1
	if _rejected_logs[from_peer] <= MAX_REJECT_LOGS:
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
				# Spawns at z < 0 mirror those at z > 0, so paired --auto players meet face to
				# face once per circle.
				if pos.z < 0.0:
					_body.rotation.y = PI
					_auto_turn = -AUTO_TURN
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
	var own := _own_id
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


func _setup_voice() -> void:
	# Every voice player plays on its own bus, so its level can be measured apart from anything
	# else and even with the Master bus muted.
	AudioServer.add_bus()
	_voice_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_voice_bus, VOICE_BUS)
	AudioServer.set_bus_send(_voice_bus, &"Master")
	if _mute_output:
		AudioServer.set_bus_mute(0, true)
	AudioServer.set_bus_volume_db(_voice_bus, _voice_gain_db)
	if _voice != "off":
		_source = SpikeVoiceSource.new()
		if _voice == "mic":
			_log("voice input devices: %s" % ", ".join(AudioServer.get_input_device_list()))
		var problem := _source.start(0.0 if _voice == "mic" else _tone_hz, _mic_device, _denoise)
		if problem != "":
			push_error("WALK voice source failed: " + problem)
			_source = null
		elif _source.is_mic():
			if _detect_clicks:
				_source.detector = SpikeVoiceOnsets.new(_source.input_rate())
			_source.dump_mic = _mic_dump_path != ""
	if _click_every > 0.0:
		_clicks.start_clicking(self, _voice_bus, _click_every)
	_log(
		(
			(
				"voice source=%s cutoff=%.1f audio_driver=%s mute_output=%s mix_rate=%d"
				+ " output_latency_ms=%.1f output_device='%s' voice_gain_db=%.1f click_every=%.1f"
				+ " detect_clicks=%s"
			)
			% [
				_source.describe() if _source != null else "off",
				_cutoff,
				AudioServer.get_driver_name(),
				_mute_output,
				int(AudioServer.get_mix_rate()),
				AudioServer.get_output_latency() * 1000.0,
				AudioServer.output_device,
				_voice_gain_db,
				_click_every,
				_source != null and _source.detector != null,
			]
		)
	)


func _update_voice(delta: float) -> void:
	if _source != null:
		# Always drain the source, so the microphone never backs up before the host places us.
		var frames := _source.pull(delta)
		if _epoch != 0 and _status == "connected":
			for k in frames.size():
				var opus := frames[k]
				if opus.size() > SpikeVoiceMessages.MAX_OPUS_BYTES:
					continue
				_voice_seq += 1
				var bytes := SpikeVoiceMessages.encode_up(_voice_seq, opus)
				_transport.send(SpikeTransport.HOST_ID, bytes, false, SpikeTransport.CHANNEL_VOICE)
				_voice_sent += 1
				if SpikeVoiceSpeaker.is_timed(_voice_seq):
					_log(
						(
							"lat_send seq=%d unix=%.4f age_ms=%.1f"
							% [_voice_seq, Time.get_unix_time_from_system(), _source.ages[k]]
						)
					)
		_mic_meter = maxf(_mic_meter - delta * 0.8, _source.last_peak)
		if _source.detector != null:
			_clicks.add_onsets(_source.onsets, _source.detector.floor_level)
			_source.onsets.clear()
	for id: int in _speakers:
		var speaker := _speakers[id]
		speaker.update()
		for t: Array in speaker.timed:
			_log(
				(
					"lat_play from=%d seq=%d recv=%.4f push=%.4f queue_ms=%.1f playing=%s out_ms=%.1f"
					% [id, t[0], t[1], t[2], t[3], t[4], AudioServer.get_output_latency() * 1000.0]
				)
			)
		speaker.timed.clear()
	_clicks.update(_clock)
	if _voice_bus < 0:
		return
	var peak := maxf(
		AudioServer.get_bus_peak_volume_left_db(_voice_bus, 0),
		AudioServer.get_bus_peak_volume_right_db(_voice_bus, 0)
	)
	_level_db = maxf(_level_db, peak)
	_heard_db = maxf(_heard_db - delta * 40.0, peak)
	_since_level += delta
	if _since_level < LEVEL_EVERY:
		return
	_since_level = 0.0
	if _epoch != 0:
		# The listener is the camera on this body; the distance is measured as the audio engine
		# sees it, to the voice player on each drawn avatar. peak_db is the whole Voice bus, so
		# a line speaks for one speaker only while one remote player talks (the launcher's case).
		var ear := _camera.global_position
		for id: int in _avatars:
			var mouth := _avatars[id].to_global(MOUTH)
			_log(
				(
					"level from=%d dist=%.2f peak_db=%.1f"
					% [id, ear.distance_to(mouth), maxf(_level_db, SILENT_DB)]
				)
			)
	_level_db = SILENT_DB


func _save_mic_dump() -> void:
	if _mic_dump_path == "" or _source == null or not _source.dump_mic:
		return
	var err := _source.save_dump(_mic_dump_path)
	_log("mic_dump %s %s" % [_mic_dump_path, error_string(err)])
	_mic_dump_path = ""


## Host: a VOICE_UP frame from a client, relayed to the listeners the routing rule allows.
func _host_voice(from_peer: int, msg: Array) -> void:
	if msg[0] != SpikeVoiceMessages.KIND_VOICE_UP:
		_count_reject("voice", from_peer, "kind %d" % (msg[0] as int))
		return
	var positions: Dictionary[int, Vector3] = {}
	for id: int in _yaws:
		positions[id] = _check.position_of(id)
	var sends := _relay.relay(from_peer, msg[1] as int, msg[2] as PackedByteArray, positions)
	for item: Array in sends:
		var to: int = item[0]
		_transport.send(to, item[1] as PackedByteArray, false, SpikeTransport.CHANNEL_VOICE)
		var pair := "%d>%d" % [from_peer, to]
		if not _voice_pairs_logged.has(pair):
			_voice_pairs_logged[pair] = true
			var dist := positions[from_peer].distance_to(positions[to])
			_log("voice_first %s dist=%.2f" % [pair, dist])


## Client: a VOICE_DOWN frame, played from the speaker's avatar.
func _client_voice(from_peer: int, msg: Array) -> void:
	if from_peer != SpikeTransport.HOST_ID or msg[0] != SpikeVoiceMessages.KIND_VOICE_DOWN:
		_log("rejected voice from id=%d" % from_peer)
		return
	var speaker: int = msg[1]
	if speaker == _own_id:
		_log("rejected own voice")
		return
	if not _speakers.has(speaker):
		# Voice comes from a drawn player only; the first snapshots arrive before any voice.
		if not _avatars.has(speaker):
			_voice_no_avatar += 1
			return
		if _speakers_failed.has(speaker):
			return
		var created := SpikeVoiceSpeaker.new(_cutoff, VOICE_BUS)
		if not created.attach(_avatars[speaker], MOUTH):
			# Once: without this every frame (50 a second) would add a player and an error.
			created.player.queue_free()
			_speakers_failed[speaker] = true
			push_error("WALK voice: no AudioStreamPlaybackOpus for id=%d" % speaker)
			return
		_speakers[speaker] = created
		_log("voice_first from=%d" % speaker)
	_speakers[speaker].push(msg[2] as int, msg[3] as PackedByteArray)


## ENet's throttle drops unreliable packets at random; every change is logged with its time.
func _log_throttle_changes() -> void:
	var enet := _transport as SpikeEnetTransport
	if enet == null:
		return
	var line := enet.throttle_line()
	if line != _last_throttle:
		_last_throttle = line
		_log("throttle t=%.3f %s" % [_clock, line])


func _measure_bandwidth(seconds: float) -> void:
	if not _is_host or seconds <= 0.0:
		return
	var sent := _transport.pop_sent_bytes()
	_net_kbps = sent * 8.0 / 1000.0 / seconds if sent >= 0 else -1.0
	_voice_kbps = (_relay.payload_bytes_out - _payload_out_before) * 8.0 / 1000.0 / seconds
	_payload_out_before = _relay.payload_bytes_out


func _voice_summary() -> String:
	if _is_host:
		var r := _relay
		return (
			(
				"cutoff=%.1f received=%s delivered=%s culled=%s max_delivered=%.2f min_culled=%.2f"
				+ " flood=%d unplaced=%d voice_payload_kbps=%.1f net_out_kbps=%.1f relay_us=%.1f"
			)
			% [
				r.routing.cutoff,
				r.received,
				r.delivered,
				r.culled,
				r.max_delivered_distance,
				r.min_culled_distance if r.min_culled_distance != INF else -1.0,
				r.dropped_flood,
				r.dropped_unplaced,
				_voice_kbps,
				_net_kbps,
				float(_relay_usec) / maxi(1, _relay_calls),
			]
		)
	var parts := PackedStringArray()
	var ids: Array[int] = _speakers.keys()
	ids.sort()
	for id: int in ids:
		parts.append("%d:{%s}" % [id, _speakers[id].stats()])
	var peak := _source.peak if _source != null else 0.0
	if _source != null:
		_source.peak = 0.0
	var encode_us := 0.0
	if _source != null:
		encode_us = float(_source.encode_usec) / maxi(1, _source.encoded)
	return (
		"sent=%d src_peak=%.3f encode_us=%.1f no_avatar=%d from=[%s]"
		% [_voice_sent, peak, encode_us, _voice_no_avatar, ", ".join(parts)]
	)


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
	var own := _own_id
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
	var id := _own_id
	_label.text = (
		"%s  peer id %s\n%s\ntick %.0f Hz, interpolation delay %.0f ms\n%s\n%s"
		% [
			role,
			str(id) if id != 0 else "-",
			_status,
			_tick_hz,
			_buffer.delay * 1000.0,
			(
				"voice cutoff %.0f m" % _cutoff
				if _is_host
				else (
					"voice: %s, output %s, cutoff %.0f m"
					% [
						_source.describe() if _source != null else "listen only",
						"MUTED" if _mute_output else "on",
						_cutoff,
					]
				)
			),
			"" if _is_host else "click: mouse look, Esc: release, WASD: walk\n" + _meters(),
		]
	)


## Live meters for a listening test: what this client's microphone picks up, and how loud the
## voices it plays are (the Voice bus, before the Master mute).
func _meters() -> String:
	var mic := ""
	if _source != null and _source.is_mic():
		mic = "mic   %s %.2f\n" % [_bar(_mic_meter), _mic_meter]
	var heard := clampf((_heard_db + 60.0) / 60.0, 0.0, 1.0)  # -60 dB .. 0 dB
	var level := "silent" if _heard_db <= -60.0 else "%.0f dB" % _heard_db
	return mic + "heard %s %s" % [_bar(heard), level]


static func _bar(fraction: float) -> String:
	var filled := clampi(roundi(fraction * 20.0), 0, 20)
	return "[" + "|".repeat(filled) + ".".repeat(20 - filled) + "]"


static func _fmt(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]


func _log(line: String) -> void:
	print("WALK %s %s" % ["host" if _is_host else "client", line])
