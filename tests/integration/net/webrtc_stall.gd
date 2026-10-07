extends SceneTree
## Three hosts, each with one client: WebRtcTransport in one process on 127.0.0.1, the twin of
## enet_stall.gd (the M6 design §2.6 and §5, #370). Headless:
##   tools\run.cmd run tests/integration/net/webrtc_stall.gd --headless -- --port=<p>
## --port is required (verify gives a free one): one LanSignalling there serves the three rooms.
## Exits 0 when every part held, else prints an ERROR line and exits 1.
##
## A transport that is not polled sends and reads nothing: to the other side it is a hung main
## thread in a live process. WebRTC's own keepalives run on libdatachannel's threads and keep the
## connection CONNECTED (M6-1: a 30 s hang stayed connected), so only WebRtcTransport's silence
## rule can drop it: after SILENCE_MS without a packet, keepalives included.
## - Pair 1, the client drops a stalled host: both beat for WARM_MS, then the host stops polling;
##   the client must see host_lost after SILENCE_MS (from its last packet, which came at most a
##   beat before the stall) and not before.
## - Pair 2, the host drops a stalled client the same way: peer_left after SILENCE_MS.
## - Pair 3, the fault shim's 3 s case (the design's §5): the host's shim delays one RELIABLE beat
##   from the client by 3 s while the client's LATEST poses go on at 20 Hz. No beat arrives in the
##   delay (the ones behind the late beat wait for it, in order), and no pose sent after it either:
##   LaneOrder holds them, its full hold drops the older ones (latest_superseded grows). The peer
##   stays, every beat arrives once and in order, and the poses come again after the late beat.
## The process sets the WebRTC library up (a WebRtcWarmUp, kept for the whole run) before the
## hosts open their rooms: under load the setup took seconds, and in a first connection it
## counted against the join's JOIN_TIMEOUT_MS (#510).

const WebRtcWarmUp := preload("res://tests/integration/net/webrtc_warm_up.gd")
const ADDRESS := "127.0.0.1"
const PORT_ARG := "--port="
## The rooms' codes, handed out in the order the hosts' `open` messages arrive.
const CODES: Array[String] = ["STW2AA", "STW2BB", "STW2CC"]
const DEADLINE_MS := 50000
const BEAT_EVERY_MS := 50
const POSE_EVERY_MS := 50
const WARM_MS := 2500
const RETRY_JOIN_MS := 500
## A drop may come this much before SILENCE_MS after the stall: the running side counts from its
## last packet, which the stalled side may have sent a beat or a frame before it stopped.
const EARLY_MS := 150
## The silence rule is judged once per poll, after the reads: a drop comes a frame or so after it.
const LATE_MS := 1000
## Pair 3: how late the shim delivers the one beat, and how long the run watches afterwards.
const LATE_BEAT_MS := 3000
const AFTER_LATE_BEAT_MS := 1500
## Packets already on their way when the delay starts may still arrive this long into it.
const IN_FLIGHT_MS := 200
const BEAT := 1  # both ways, reliable: a sequence number
const POSE := 2  # client -> host, latest: a sequence number

var _kinds := NetKindTable.new()
var _started_ms := 0
var _done := false
var _warm_up: WebRtcWarmUp
var _signalling: LanSignalling
var _pairs: Array[Pair] = []
var _codes_given := 0


## A host and one client; `stalling` ("host", "client" or "" for pair 3) stops polling.
class Pair:
	extends RefCounted
	var name := ""
	var stalling := ""
	var host: WebRtcTransport
	var client: WebRtcTransport
	var shim: WebRtcTransport.FaultShim
	var host_paused := false
	var client_paused := false
	var next_join_ms := 0
	## When the client started its last join, and its first (the join lines print both).
	var join_started_ms := -1
	var first_join_ms := -1
	var connected_ms := -1
	var stalled_at_ms := -1
	var dropped_after_ms := -1
	var last_beat_ms := 0
	var beat := 0
	var pose := 0
	var last_pose_ms := 0
	## What the host heard from the client.
	var heard_beat := 0
	var heard_pose := 0
	## Pair 3: when the late beat was asked for, when the beats came again, and the poses since.
	var delayed_at_ms := -1
	var beats_back_ms := -1
	var poses_after := 0
	var superseded_at_delay := 0
	var finished := false

	func poll() -> void:
		if not host_paused:
			host.poll()
		if not client_paused:
			client.poll()

	func done() -> bool:
		return finished or dropped_after_ms >= 0


func _initialize() -> void:
	_kinds.add(BEAT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.BOTH, 4)
	_kinds.add(POSE, NetKindTable.Lane.LATEST, NetKindTable.Direction.CLIENT_TO_HOST, 4)
	_started_ms = Time.get_ticks_msec()
	var port_text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PORT_ARG):
			port_text = arg.trim_prefix(PORT_ARG)
	var port := port_text.to_int() if port_text.is_valid_int() else 0
	if port < 1 or port > 65535:
		_fail("give -- %s<a free port between 1 and 65535>, got '%s'" % [PORT_ARG, port_text])
		return
	_warm_up = WebRtcWarmUp.new()
	if not _warm_up.wait():
		_fail("the WebRTC warm-up failed: %s" % _warm_up.error_text)
		return
	print("NET stall WebRTC set up after %d ms" % (Time.get_ticks_msec() - _started_ms))
	_signalling = LanSignalling.new([], _next_code)
	var err := _signalling.listen(port, ADDRESS)
	if err != OK:
		_fail("signalling on %s:%d failed: %s" % [ADDRESS, port, error_string(err)])
		return
	for i in 3:
		var pair := Pair.new()
		pair.name = "pair %d" % (i + 1)
		pair.stalling = ["host", "client", ""][i]
		if not _start(pair, port):
			return
		_pairs.append(pair)


func _next_code() -> String:
	_codes_given += 1
	return CODES[(_codes_given - 1) % CODES.size()]


func _new_transport(port: int) -> WebRtcTransport:
	var transport := WebRtcTransport.new(_kinds)
	transport.signal_url = "ws://%s:%d" % [ADDRESS, port]
	transport.local_candidates = true
	return transport


func _start(pair: Pair, port: int) -> bool:
	pair.host = _new_transport(port)
	var err := pair.host.host(0, 1)
	if err != OK:
		_fail("%s: host failed: %s" % [pair.name, error_string(err)])
		return false
	if pair.stalling == "":
		pair.shim = WebRtcTransport.FaultShim.new(370)
		if pair.host.use_faults(pair.shim) != OK:
			_fail("the fault shim needs a debug build")
			return false
	pair.client = _new_transport(port)
	pair.client.connect_failed.connect(_on_connect_failed.bind(pair))
	pair.client.connected.connect(_on_connected.bind(pair).unbind(1))
	pair.client.packet_received.connect(_on_client_packet.bind(pair))
	pair.host.packet_received.connect(_on_host_packet.bind(pair))
	pair.client.host_lost.connect(_on_drop.bind(pair, "client"))
	pair.host.peer_left.connect(_on_drop.bind(pair, "host").unbind(1))
	return true


func _process(_delta: float) -> bool:
	if _done:
		return false
	var now := Time.get_ticks_msec()
	if now - _started_ms > DEADLINE_MS:
		_fail("deadline: a part never ended")
		return false
	_signalling.poll()
	for pair in _pairs:
		_join(pair, now)
		pair.poll()
		if _done:
			return false
		_traffic(pair, now)
		if pair.stalling != "" and pair.connected_ms >= 0 and pair.stalled_at_ms < 0:
			if now - pair.connected_ms >= WARM_MS:
				pair.stalled_at_ms = now
				pair.host_paused = pair.stalling == "host"
				pair.client_paused = pair.stalling == "client"
				print("NET stall %s: the %s stops polling" % [pair.name, pair.stalling])
		elif pair.stalling == "" and pair.connected_ms >= 0:
			_late_beat_step(pair, now)
	if _pairs.all(func(pair: Pair) -> bool: return pair.done()):
		_finish()
	return false


func _join(pair: Pair, now: int) -> void:
	if pair.client.role() == NetTransport.Role.IDLE and pair.connected_ms < 0:
		if now >= pair.next_join_ms and pair.host.room_code() != "":
			var err := pair.client.join(pair.host.room_code(), 0)
			if err != OK:
				_fail("%s: join failed to start: %s" % [pair.name, error_string(err)])
				return
			pair.join_started_ms = now
			if pair.first_join_ms < 0:
				pair.first_join_ms = now


## Reliable beats both ways while both run, then from the running side; poses from the client.
func _traffic(pair: Pair, now: int) -> void:
	if pair.connected_ms < 0 or pair.done():
		return
	if now - pair.last_beat_ms >= BEAT_EVERY_MS:
		pair.last_beat_ms = now
		pair.beat += 1
		var beat := PackedByteArray()
		beat.resize(4)
		beat.encode_u32(0, pair.beat)
		if not pair.client_paused:
			pair.client.send(NetTransport.HOST_ID, BEAT, beat)
		if not pair.host_paused and pair.host.peers().size() == 1:
			pair.host.send(pair.host.peers()[0], BEAT, beat)
	if not pair.client_paused and now - pair.last_pose_ms >= POSE_EVERY_MS:
		pair.last_pose_ms = now
		pair.pose += 1
		var pose := PackedByteArray()
		pose.resize(4)
		pose.encode_u32(0, pair.pose)
		pair.client.send(NetTransport.HOST_ID, POSE, pose)


## Pair 3: after WARM_MS the shim delays the next beat by LATE_BEAT_MS; the run watches the beats
## come back and the poses after them.
func _late_beat_step(pair: Pair, now: int) -> void:
	if pair.delayed_at_ms < 0 and now - pair.connected_ms >= WARM_MS:
		pair.delayed_at_ms = now
		pair.superseded_at_delay = pair.host.latest_superseded
		pair.shim.delay_next_reliable(LATE_BEAT_MS)
		print(
			"NET stall %s: the next beat to the host arrives %d ms late" % [pair.name, LATE_BEAT_MS]
		)
	elif pair.beats_back_ms >= 0 and now - pair.beats_back_ms >= AFTER_LATE_BEAT_MS:
		pair.finished = true


func _on_connected(pair: Pair) -> void:
	pair.connected_ms = Time.get_ticks_msec()
	print(
		(
			"NET stall %s: connected; its join took %d ms, %d ms after its first"
			% [
				pair.name,
				pair.connected_ms - pair.join_started_ms,
				pair.connected_ms - pair.first_join_ms
			]
		)
	)


func _on_connect_failed(reason: StringName, pair: Pair) -> void:
	var took := Time.get_ticks_msec() - pair.join_started_ms
	print("NET stall %s: join failed (%s) after %d ms; retrying" % [pair.name, reason, took])
	pair.next_join_ms = Time.get_ticks_msec() + RETRY_JOIN_MS


## The running side lost the stalled one: expected, and timed. Anything else fails.
func _on_drop(pair: Pair, side: String) -> void:
	var running := "client" if pair.stalling == "host" else "host"
	if pair.stalling == "" or side != running or pair.stalled_at_ms < 0:
		_fail("%s: the %s lost the other side in the run" % [pair.name, side])
		return
	pair.dropped_after_ms = Time.get_ticks_msec() - pair.stalled_at_ms
	print(
		(
			"NET stall %s: the stalled %s dropped after %d ms"
			% [pair.name, pair.stalling, pair.dropped_after_ms]
		)
	)


func _on_host_packet(from_peer: int, kind: int, payload: PackedByteArray, pair: Pair) -> void:
	var seq := payload.decode_u32(0)
	if kind == BEAT:
		if seq != pair.heard_beat + 1 and pair.heard_beat != 0:
			_fail("%s: beat %d after beat %d" % [pair.name, seq, pair.heard_beat])
		pair.heard_beat = seq
		if pair.delayed_at_ms >= 0 and pair.beats_back_ms < 0:
			var waited := Time.get_ticks_msec() - pair.delayed_at_ms
			if waited < LATE_BEAT_MS - IN_FLIGHT_MS:
				_fail("%s: beat %d arrived %d ms into the delay" % [pair.name, seq, waited])
				return
			pair.beats_back_ms = Time.get_ticks_msec()
			print("NET stall %s: the beats came again after %d ms" % [pair.name, waited])
	elif kind == POSE:
		if seq <= pair.heard_pose:
			_fail("%s: pose %d after pose %d" % [pair.name, seq, pair.heard_pose])
		pair.heard_pose = seq
		if pair.beats_back_ms >= 0:
			pair.poses_after += 1
		elif pair.delayed_at_ms >= 0:
			var into := Time.get_ticks_msec() - pair.delayed_at_ms
			if into > IN_FLIGHT_MS:
				_fail("%s: pose %d arrived %d ms into the delay, not held" % [pair.name, seq, into])
	else:
		_fail("%s: the host got kind %d from peer %d" % [pair.name, kind, from_peer])


func _on_client_packet(from_peer: int, kind: int, _payload: PackedByteArray, pair: Pair) -> void:
	if kind != BEAT:
		_fail("%s: the client got kind %d from peer %d" % [pair.name, kind, from_peer])


func _finish() -> void:
	var low := WebRtcTransport.SILENCE_MS - EARLY_MS
	var high := WebRtcTransport.SILENCE_MS + LATE_MS
	for pair in _pairs:
		if pair.stalling != "" and (pair.dropped_after_ms < low or pair.dropped_after_ms > high):
			_fail(
				(
					"%s: the stalled %s was dropped after %d ms, not within %d to %d ms"
					% [pair.name, pair.stalling, pair.dropped_after_ms, low, high]
				)
			)
			return
		if pair.stalling == "" and pair.host.latest_superseded <= pair.superseded_at_delay:
			_fail("%s: the hold dropped no pose in a 3 s delay" % pair.name)
			return
		if pair.stalling == "" and (pair.poses_after < 5 or pair.host.peers().size() != 1):
			_fail(
				(
					"%s: after the late beat the host has peers %s and %d new poses"
					% [pair.name, pair.host.peers(), pair.poses_after]
				)
			)
			return
		if pair.host.rejects.total() + pair.client.rejects.total() != 0:
			_fail(
				(
					"%s: rejected on the host: %s; on the client: %s"
					% [pair.name, pair.host.rejects.totals(), pair.client.rejects.totals()]
				)
			)
			return
	for pair in _pairs:
		pair.client.close()
		pair.host.close()
	_signalling.stop()
	_warm_up.close()
	print(
		"NET stall each stalled side dropped by the silence rule; the late beat kept its peer; PASS"
	)
	_done = true
	quit(0)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("NET stall FAIL: %s" % message)
	quit(1)
