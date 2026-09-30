extends SceneTree
## Three hosts, each with one client: EnetTransport in one process on 127.0.0.1 (#95). Headless:
##   tools\run.cmd run tests/integration/net/enet_stall.gd --headless -- --port=<p>
## --port is required (verify gives a free one); the hosts take <p>, <p> + 1 and <p> + 2. Exits 0
## when every part held, else prints an ERROR line and exits 1.
##
## A transport that is not polled services no ENet: to the other side it is a frozen process, so
## one process can stall one side of a pair while the other runs on and sends it a reliable beat
## every BEAT_EVERY_MS. ENet resends an unacknowledged message with a doubling delay (from the
## round-trip time) and drops the peer at the first resend past the timeout's minimum, or past its
## maximum, so a drop comes between the minimum and about twice it. On one PC ENet's default
## (5 to 30 s) dropped a stalled host after 9.8 s and a stalled client after 5.9 s; with
## EnetTransport's 10 to 20 s after 19.5 s and 14.3 s.
## - Pair 1, from the moment a connection exists: the host stops polling as soon as its client is
##   connected. The client must still have the host after PEER_TIMEOUT_MIN_MS. With no round trip
##   measured yet ENet starts from 500 ms and would wait about 31 s, whatever the timeout.
## - Pair 2, the client's timeout on its host peer: both beat for WARM_MS, so the round trip is
##   measured, then the host stops polling. The client must drop it after PEER_TIMEOUT_MIN_MS to
##   PEER_TIMEOUT_MAX_MS.
## - Pair 3, the host's timeout on its client: first the backlog below; then both beat for
##   WARM_MS, the client stops polling, and the host must drop it within the same window.
## - Backlog: pair 3's host is not polled while its client sends more LATEST poses than ENet reads
##   per service (EnetTransport.ENET_RECEIVES_PER_SERVICE), one datagram each. The host's next poll
##   must take the whole backlog: its newest pose is past the first service's worth, and the poll
##   after it brings no pose left over.

const ADDRESS := "127.0.0.1"
const PORT_ARG := "--port="
const DEADLINE_MS := 45000
const BEAT_EVERY_MS := 50
const WARM_MS := 2500
## A drop may come this much before PEER_TIMEOUT_MIN_MS after the stall began: ENet counts from
## the oldest unacknowledged send, which the stalled side may have missed a frame before it
## stopped.
const EARLY_MS := 50
## ENet checks a timeout only when a resend is due, so a drop may come a little after
## PEER_TIMEOUT_MAX_MS.
const LATE_MS := 1000
## Poses in the backlog: more than one ENet service reads, few enough for Linux's default socket
## receive buffer (208 KB, doubled) to hold them all.
const BACKLOG_POSES := EnetTransport.ENET_RECEIVES_PER_SERVICE + 64
## Loopback delivery is fast but not synchronous: wait this long before the host takes the backlog.
const BACKLOG_SETTLE_MS := 200
const BEAT := 1  # both ways, reliable
const POSE := 2  # client -> host, latest: a sequence number

var _kinds := NetKindTable.new()
var _started_ms := 0
var _done := false
var _pairs: Array[Pair] = []


## A host and one client; `stalling` ("host" or "client") is the side that stops polling.
class Pair:
	extends RefCounted
	var name := ""
	var stalling := ""
	## Pair 1 checks only that the connection holds past the minimum; 2 and 3 wait for the drop.
	var hold_only := false
	var backlog := false
	var host: EnetTransport
	var client: EnetTransport
	var host_paused := false
	var client_paused := false
	var connected_ms := -1
	var stalled_at_ms := -1
	var dropped_after_ms := -1
	var held := false
	var last_beat_ms := 0
	var backlog_sent_ms := -1
	var newest_pose := 0
	var poses_in_poll := 0

	func poll() -> void:
		if not host_paused:
			host.poll()
		if not client_paused:
			client.poll()

	func warming() -> bool:
		return connected_ms >= 0 and stalled_at_ms < 0 and backlog_sent_ms < 0 and not hold_only

	func stall() -> void:
		stalled_at_ms = Time.get_ticks_msec()
		host_paused = stalling == "host"
		client_paused = stalling == "client"
		print("NET stall %s: the %s stops polling" % [name, stalling])

	## Reliable beats: both ways while warming, then from the running side to the stalled one.
	func beat() -> void:
		var now := Time.get_ticks_msec()
		if dropped_after_ms >= 0 or held or now - last_beat_ms < BEAT_EVERY_MS:
			return
		if not warming() and stalled_at_ms < 0:
			return
		last_beat_ms = now
		if not client_paused:
			client.send(NetTransport.HOST_ID, BEAT, PackedByteArray([1]))
		if not host_paused and host.peers().size() == 1:
			host.send(host.peers()[0], BEAT, PackedByteArray([1]))

	func dropped() -> void:
		dropped_after_ms = Time.get_ticks_msec() - stalled_at_ms if stalled_at_ms >= 0 else 0
		print(
			"NET stall %s: the stalled %s dropped after %d ms" % [name, stalling, dropped_after_ms]
		)

	func done() -> bool:
		return held or dropped_after_ms >= 0


func _initialize() -> void:
	_kinds.add(BEAT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.BOTH, 1)
	_kinds.add(POSE, NetKindTable.Lane.LATEST, NetKindTable.Direction.CLIENT_TO_HOST, 4)
	_started_ms = Time.get_ticks_msec()
	var port_text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PORT_ARG):
			port_text = arg.trim_prefix(PORT_ARG)
	var port := port_text.to_int() if port_text.is_valid_int() else 0
	if port < 1 or port > 65533:
		_fail("give -- %s<a free UDP port between 1 and 65533>, got '%s'" % [PORT_ARG, port_text])
		return
	for i in 3:
		var pair := Pair.new()
		pair.name = "pair %d" % (i + 1)
		pair.stalling = "client" if i == 2 else "host"
		pair.hold_only = i == 0
		pair.backlog = i == 2
		if not _start(pair, port + i):
			return
		_pairs.append(pair)


func _start(pair: Pair, port: int) -> bool:
	pair.host = EnetTransport.new(_kinds)
	pair.host.bind_address = ADDRESS
	var err := pair.host.host(port, 1)
	if err != OK:
		_fail("%s: host on %s:%d failed: %s" % [pair.name, ADDRESS, port, error_string(err)])
		return false
	pair.client = EnetTransport.new(_kinds)
	err = pair.client.join(ADDRESS, port)
	if err != OK:
		_fail("%s: join failed to start: %s" % [pair.name, error_string(err)])
		return false
	pair.client.connect_failed.connect(_fail.bind("%s: the client could not join" % pair.name))
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
		_fail("deadline: a stalled side was never dropped")
		return false
	for pair in _pairs:
		pair.poll()
		if _done:
			return false
		pair.beat()
		if pair.warming() and now - pair.connected_ms >= WARM_MS:
			pair.stall()
		elif pair.backlog_sent_ms >= 0 and now - pair.backlog_sent_ms >= BACKLOG_SETTLE_MS:
			_take_backlog(pair)
		elif pair.hold_only and not pair.held and pair.stalled_at_ms >= 0:
			if now - pair.stalled_at_ms >= EnetTransport.PEER_TIMEOUT_MIN_MS:
				pair.held = true
				print(
					(
						"NET stall %s: the client kept the host for %d ms"
						% [pair.name, now - pair.stalled_at_ms]
					)
				)
	if _pairs.all(func(pair: Pair) -> bool: return pair.done()):
		_finish()
	return false


func _on_connected(pair: Pair) -> void:
	pair.connected_ms = Time.get_ticks_msec()
	if pair.hold_only:
		pair.stall()
	elif pair.backlog:
		_send_backlog(pair)


## The running side lost the stalled one: expected, and timed, unless this pair only holds.
func _on_drop(pair: Pair, side: String) -> void:
	var running := "client" if pair.stalling == "host" else "host"
	if side != running or pair.stalled_at_ms < 0 or pair.hold_only:
		_fail("%s: the %s lost the other side in the run" % [pair.name, side])
		return
	pair.dropped()


## One pose per client poll: each poll flushes what was sent since the last one as one datagram.
## The host is not polled until _take_backlog.
func _send_backlog(pair: Pair) -> void:
	pair.host_paused = true
	for seq in range(1, BACKLOG_POSES + 1):
		var pose := PackedByteArray()
		pose.resize(4)
		pose.encode_u32(0, seq)
		if pair.client.send(NetTransport.HOST_ID, POSE, pose) != OK:
			_fail("%s: pose %d was not sent" % [pair.name, seq])
			return
		pair.client.poll()
	pair.backlog_sent_ms = Time.get_ticks_msec()


func _take_backlog(pair: Pair) -> void:
	pair.backlog_sent_ms = -1
	pair.host_paused = false
	pair.poses_in_poll = 0
	pair.host.poll()
	var first_poll := pair.poses_in_poll
	var newest := pair.newest_pose
	pair.poses_in_poll = 0
	pair.host.poll()
	print(
		(
			(
				"NET stall %s backlog: %d poses sent; the host's first poll handed over pose %d (%d"
				+ " merged away), the next poll %d more"
			)
			% [pair.name, BACKLOG_POSES, newest, pair.host.latest_superseded, pair.poses_in_poll]
		)
	)
	if first_poll != 1:
		_fail("%s: the host's first poll handed over %d poses" % [pair.name, first_poll])
	elif newest <= EnetTransport.ENET_RECEIVES_PER_SERVICE:
		_fail(
			(
				(
					"%s: the host's first poll after the backlog reached only pose %d of %d: it read"
					+ " one ENet service's worth, not the whole backlog"
				)
				% [pair.name, newest, BACKLOG_POSES]
			)
		)
	elif pair.poses_in_poll != 0:
		_fail("%s: %d pose(s) of the backlog came a poll late" % [pair.name, pair.poses_in_poll])
	else:
		# Warm from here on.
		pair.connected_ms = Time.get_ticks_msec()


func _on_host_packet(from_peer: int, kind: int, payload: PackedByteArray, pair: Pair) -> void:
	if kind == POSE:
		pair.poses_in_poll += 1
		pair.newest_pose = payload.decode_u32(0)
	elif kind != BEAT:
		_fail("%s: the host got kind %d from peer %d" % [pair.name, kind, from_peer])


func _on_client_packet(from_peer: int, kind: int, _payload: PackedByteArray, pair: Pair) -> void:
	if kind != BEAT:
		_fail("%s: the client got kind %d from peer %d" % [pair.name, kind, from_peer])


func _finish() -> void:
	var low := EnetTransport.PEER_TIMEOUT_MIN_MS - EARLY_MS
	var high := EnetTransport.PEER_TIMEOUT_MAX_MS + LATE_MS
	for pair in _pairs:
		if not pair.hold_only and (pair.dropped_after_ms < low or pair.dropped_after_ms > high):
			var running := "client" if pair.stalling == "host" else "host"
			_fail(
				(
					(
						"%s: the %s dropped the stalled %s after %d ms, not within %d to %d ms: its"
						+ " peer does not have EnetTransport's timeout"
					)
					% [pair.name, running, pair.stalling, pair.dropped_after_ms, low, high]
				)
			)
			return
		if pair.host.rejects.total() + pair.client.rejects.total() != 0:
			_fail("%s: packets were rejected" % pair.name)
			return
	for pair in _pairs:
		pair.client.close()
		pair.host.close()
	print("NET stall no side was dropped early, and each within its timeout; PASS")
	_done = true
	quit(0)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("NET stall FAIL: %s" % message)
	quit(1)
