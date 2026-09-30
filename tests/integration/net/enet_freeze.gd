extends SceneTree
## A 5.2 s main-thread freeze on the host, then on a client, over EnetTransport on 127.0.0.1, one
## process each (#70; the #21 probe's -FreezeHost 8:5200). Headless only:
##   tools\run.cmd run tests/integration/net/enet_freeze.gd --headless --instances 3 -- --port=<p>
## --port is required, so no run takes a fixed port: give it a free UDP port (verify does).
## PRIME_INSTANCE picks the part: 1 hosts; 2 and 3 join. Each process exits 0 when its part held,
## else prints an ERROR line and exits 1.
##
## ENet runs only on the main thread, so a frozen process sends and acknowledges nothing; on Windows
## a windowed D3D12 process can freeze about 5 s when another one on the same PC is killed or
## starts (#21). Each side sends the other a LATEST pose (a sequence number and the send time)
## every 50 ms and a reliable beat (a sequence number) every 100 ms. The host freezes for 5.2 s;
## then it tells client 2 to freeze for 5.2 s; then it ends the run. What must hold:
## - No drop: the host sees no peer_left and no client sees host_lost before the end.
## - Reliable beats arrive complete and in order through both freezes.
## - At most one pose per peer per poll between that peer's reliable messages, ever (the LATEST
##   lane's rule, NetTransport: a reliable message separates the runs it merges). In the first poll
##   after a freeze the backlog arrives, and each run of a peer's poses is merged into its newest:
##   at least one pose is merged away, and the one applied is not the backlog's 5 s old head.
## On one PC (Windows 11) the thawed host's newest pose from each client was about 1 s old, and the
## poses of the freeze's last second never arrived, probably because the host's socket buffer
## filled with two senders; the thawed client's, from one sender, was 2 ms old. Reliable messages
## are sent again, so they all arrive.

const ADDRESS := "127.0.0.1"
const PORT_ARG := "--port="
const FREEZE_MS := 5200
const DEADLINE_MS := 45000
## Traffic before the host's freeze, and after each thaw before the next step.
const WARM_MS := 1500
const SETTLE_MS := 1500
const POSE_EVERY_MS := 50
const BEAT_EVERY_MS := 100
const RETRY_JOIN_MS := 500
## The pose applied at the thaw is younger than this: the backlog's head is FREEZE_MS old.
const THAW_MAX_AGE_MS := FREEZE_MS / 2.0
const HELLO := 1  # client -> host, reliable: the client's instance number
const BEAT := 2  # both ways, reliable: a sequence number
const POSE := 3  # both ways, latest: a sequence number and the send time
const COMMAND := 4  # host -> client, reliable: "freeze" or "end"
const REPORT := 5  # client -> host, reliable: "thawed"
const FROZEN_CLIENT := 2

var _kinds := NetKindTable.new()
var _instance := 0
var _port := 0
var _started_ms := 0
var _done := false
var _transport: EnetTransport
## What this side heard from each peer, by peer id.
var _heard: Dictionary[int, Heard] = {}
var _beat := 0
var _pose := 0
var _last_beat_ms := 0
var _last_pose_ms := 0
## Set by a freeze: the next poll is the first after the thaw.
var _thawing := false
var _frozen_ms := 0
var _superseded_before := 0
var _pose_before: Dictionary[int, int] = {}
# Host part.
var _phase := "join"
var _phase_started_ms := 0
var _peer_of_instance: Dictionary[int, int] = {}
var _beat_at_phase: Dictionary[int, int] = {}
var _left: Array[int] = []
# Client part.
var _next_join_ms := 0
var _freeze_requested := false
var _told_to_end := false
var _last_packet_ms := 0


## What one side heard from one peer.
class Heard:
	extends RefCounted
	## The last reliable beat, -1 before the first.
	var beat := -1
	## The last pose's sequence number and how old it was when it arrived.
	var pose := 0
	var pose_age_ms := 0.0
	## Poses in this poll since this peer's last reliable message.
	var poses_in_run := 0

	## "" when the packet fits, else what went wrong.
	func take(kind: int, payload: PackedByteArray) -> String:
		if kind != POSE:
			poses_in_run = 0
		if kind == BEAT:
			var seq := payload.decode_u32(0)
			if beat >= 0 and seq != beat + 1:
				return "beat %d after beat %d: a reliable message was lost" % [seq, beat]
			beat = seq
		elif kind == POSE:
			poses_in_run += 1
			if poses_in_run > 1:
				return (
					(
						"%d poses in one poll with no reliable message between them: the"
						+ " LATEST lane delivered more than the newest"
					)
					% [poses_in_run]
				)
			var seq := payload.decode_u32(0)
			if seq <= pose:
				return "pose %d after pose %d" % [seq, pose]
			pose = seq
			pose_age_ms = Time.get_unix_time_from_system() * 1000.0 - payload.decode_double(4)
		return ""


func _initialize() -> void:
	_kinds.add(HELLO, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, 4)
	_kinds.add(BEAT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.BOTH, 4)
	_kinds.add(POSE, NetKindTable.Lane.LATEST, NetKindTable.Direction.BOTH, 12)
	_kinds.add(COMMAND, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.HOST_TO_CLIENT, 16)
	_kinds.add(REPORT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, 16)
	_instance = int(OS.get_environment("PRIME_INSTANCE"))
	_started_ms = Time.get_ticks_msec()
	var port_text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PORT_ARG):
			port_text = arg.trim_prefix(PORT_ARG)
	_port = port_text.to_int() if port_text.is_valid_int() else 0
	if _port < 1 or _port > 65535:
		_fail("give -- %s<a free UDP port between 1 and 65535>, got '%s'" % [PORT_ARG, port_text])
		return
	_transport = EnetTransport.new(_kinds)
	_transport.packet_received.connect(_on_packet)
	if _instance == 1:
		_start_host()
	elif _instance in [2, 3]:
		_transport.connected.connect(_on_connected)
		_transport.connect_failed.connect(_on_connect_failed)
		_transport.host_lost.connect(_on_host_lost)
	else:
		_fail("PRIME_INSTANCE must be 1, 2 or 3 (run with --instances 3), got '%s'" % _instance)


func _process(_delta: float) -> bool:
	if _done:
		return false
	if Time.get_ticks_msec() - _started_ms > DEADLINE_MS:
		_fail("deadline: still in phase '%s'" % (_phase if _instance == 1 else "client"))
	elif _instance == 1:
		_host_step()
	else:
		_client_step()
	return false


## Polls, checks the per-poll rule and, after a freeze, what the thaw brought.
func _poll() -> void:
	for heard: Heard in _heard.values():
		heard.poses_in_run = 0
	_transport.poll()
	if _thawing and not _done:
		_thawing = false
		_check_thaw()


func _check_thaw() -> void:
	var merged := _transport.latest_superseded - _superseded_before
	var seen: Array[String] = []
	for peer_id: int in _pose_before:
		var heard := _heard[peer_id]
		var jump := heard.pose - _pose_before[peer_id]
		seen.append("peer %d: pose +%d, %.0f ms old" % [peer_id, jump, heard.pose_age_ms])
	print(
		(
			"NET instance %d thawed after %d ms: %d stale poses merged; %s"
			% [_instance, _frozen_ms, merged, "; ".join(seen)]
		)
	)
	for peer_id: int in _pose_before:
		var heard := _heard[peer_id]
		if heard.pose == _pose_before[peer_id]:
			_fail("no pose from peer %d arrived in the first poll after the freeze" % peer_id)
		elif heard.pose_age_ms > THAW_MAX_AGE_MS:
			_fail("after the freeze peer %d's pose was %.0f ms old" % [peer_id, heard.pose_age_ms])
	if merged < 1:
		_fail("no pose was merged after the freeze: no backlog arrived")


func _freeze() -> void:
	_superseded_before = _transport.latest_superseded
	_pose_before.clear()
	for peer_id: int in _heard:
		_pose_before[peer_id] = _heard[peer_id].pose
	print("NET instance %d freezing its main thread for %d ms" % [_instance, FREEZE_MS])
	var before := Time.get_ticks_msec()
	OS.delay_msec(FREEZE_MS)
	_frozen_ms = Time.get_ticks_msec() - before
	_thawing = true


func _send_traffic(to_peers: Array[int]) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_pose_ms >= POSE_EVERY_MS:
		_last_pose_ms = now
		_pose += 1
		var pose := PackedByteArray()
		pose.resize(12)
		pose.encode_u32(0, _pose)
		pose.encode_double(4, Time.get_unix_time_from_system() * 1000.0)
		for peer_id in to_peers:
			_transport.send(peer_id, POSE, pose)
	if now - _last_beat_ms >= BEAT_EVERY_MS:
		_last_beat_ms = now
		_beat += 1
		var beat := PackedByteArray()
		beat.resize(4)
		beat.encode_u32(0, _beat)
		for peer_id in to_peers:
			if _transport.send(peer_id, BEAT, beat) != OK:
				_fail("a beat to peer %d was not sent" % peer_id)


func _on_packet(from_peer: int, kind: int, payload: PackedByteArray) -> void:
	_last_packet_ms = Time.get_ticks_msec()
	if not _heard.has(from_peer):
		_heard[from_peer] = Heard.new()
	# Every message goes through take(): any reliable one ends a run of poses.
	var problem := _heard[from_peer].take(kind, payload)
	if problem != "":
		_fail("from peer %d: %s" % [from_peer, problem])
	elif kind == HELLO:
		_peer_of_instance[payload.decode_u32(0)] = from_peer
		print("NET host client %d is peer %d" % [payload.decode_u32(0), from_peer])
	elif kind == REPORT:
		if _phase == "client frozen" and from_peer == _peer_of_instance.get(FROZEN_CLIENT, 0):
			_enter("settle after the client's freeze")
		else:
			_fail("an unexpected report from peer %d in phase '%s'" % [from_peer, _phase])
	elif kind == COMMAND:
		var command := payload.get_string_from_utf8()
		if command == "freeze":
			_freeze_requested = true
		elif command == "end":
			_told_to_end = true
		else:
			_fail("an unknown command '%s'" % command)


func _start_host() -> void:
	_transport.bind_address = ADDRESS
	var err := _transport.host(_port, 4)
	if err != OK:
		_fail("host on %s:%d failed: %s" % [ADDRESS, _port, error_string(err)])
		return
	_transport.peer_left.connect(_on_host_peer_left)
	print("NET host listening on %s:%d" % [ADDRESS, _port])


func _host_step() -> void:
	_poll()
	if _done:
		return
	var clients: Array[int] = []
	clients.assign(_peer_of_instance.values())
	if _phase != "end":
		_send_traffic(clients)
	var in_phase := Time.get_ticks_msec() - _phase_started_ms
	match _phase:
		"join":
			if _peer_of_instance.size() == 2:
				_enter("warm")
		"warm":
			if in_phase >= WARM_MS:
				_enter("host frozen")
				_freeze()
		"host frozen":
			# The thaw was checked in this step's poll.
			_enter("settle after the host's freeze")
		"settle after the host's freeze":
			if in_phase >= SETTLE_MS and _still_talking():
				_enter("client frozen")
				_transport.send(
					_peer_of_instance[FROZEN_CLIENT], COMMAND, "freeze".to_utf8_buffer()
				)
		"settle after the client's freeze":
			if in_phase >= SETTLE_MS and _still_talking():
				_enter("end")
				for peer_id in clients:
					_transport.send(peer_id, COMMAND, "end".to_utf8_buffer())


func _enter(phase: String) -> void:
	print("NET host phase '%s'" % phase)
	_phase = phase
	_phase_started_ms = Time.get_ticks_msec()
	for peer_id: int in _heard:
		_beat_at_phase[peer_id] = _heard[peer_id].beat


## True when every client's beats went on during this phase.
func _still_talking() -> bool:
	for peer_id: int in _peer_of_instance.values():
		if not _heard.has(peer_id) or _heard[peer_id].beat <= _beat_at_phase.get(peer_id, -1):
			_fail("peer %d sent no beat in phase '%s'" % [peer_id, _phase])
			return false
	return true


func _on_host_peer_left(peer_id: int) -> void:
	if _phase != "end":
		_fail("peer %d was dropped in phase '%s'" % [peer_id, _phase])
		return
	_left.append(peer_id)
	if _left.size() < _peer_of_instance.size():
		return
	if _transport.rejects.total() != 0:
		_fail("%d packet(s) rejected on the host" % _transport.rejects.total())
		return
	print("NET host both clients stayed through both freezes and left at the end; PASS")
	_transport.close()
	_pass()


func _client_step() -> void:
	if _transport.role() == NetTransport.Role.IDLE:
		if Time.get_ticks_msec() >= _next_join_ms:
			var err := _transport.join(ADDRESS, _port)
			if err != OK:
				_fail("join failed to start: " + error_string(err))
				return
	_poll()
	if _done or NetTransport.HOST_ID not in _transport.peers():
		return
	if _thawing_reported():
		return
	if _told_to_end:
		_finish_client()
		return
	var host: Array[int] = [NetTransport.HOST_ID]
	_send_traffic(host)
	if _freeze_requested:
		_freeze_requested = false
		_freeze()


## After this client's thaw was checked, it tells the host once. True when it just did.
func _thawing_reported() -> bool:
	if _frozen_ms == 0 or _thawing:
		return false
	_frozen_ms = 0
	_transport.send(NetTransport.HOST_ID, REPORT, "thawed".to_utf8_buffer())
	return true


func _on_connected(own_id: int) -> void:
	print("NET client %d connected as peer %d" % [_instance, own_id])
	var hello := PackedByteArray()
	hello.resize(4)
	hello.encode_u32(0, _instance)
	_transport.send(NetTransport.HOST_ID, HELLO, hello)


func _on_host_lost() -> void:
	var silent := Time.get_ticks_msec() - _last_packet_ms
	_fail("lost the host in the run, %d ms after its last packet" % silent)


func _on_connect_failed() -> void:
	# The clients start with the host: until it listens, a join fails and is tried again.
	print("NET client %d join failed; retrying" % _instance)
	_next_join_ms = Time.get_ticks_msec() + RETRY_JOIN_MS


func _finish_client() -> void:
	var heard: Heard = _heard.get(NetTransport.HOST_ID)
	if heard == null or heard.beat < 1:
		_fail("heard no beat from the host")
		return
	if _transport.rejects.total() != 0:
		_fail("%d packet(s) rejected on client %d" % [_transport.rejects.total(), _instance])
		return
	_transport.close()
	print("NET client %d stayed connected through the freezes; PASS" % _instance)
	_pass()


func _pass() -> void:
	_done = true
	quit(0)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("NET instance %d FAIL: %s" % [_instance, message])
	quit(1)
