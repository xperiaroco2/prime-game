extends SceneTree
## Three hosts, each with one client: EnetTransport in one process on 127.0.0.1 (#95). Headless:
##   tools\run.cmd run tests/integration/net/enet_stall.gd --headless -- --port=<p>
## --port is required (verify gives a free one); the hosts take <p>, <p> + 1 and <p> + 2. Exits 0
## when every part held, else prints an ERROR line and exits 1.
##
## A transport that is not polled services no ENet: to the other side it is a frozen process, so
## one process can stall one side of a pair while the other runs on and sends it a reliable beat
## every BEAT_EVERY_MS. ENet resends an unacknowledged message with a doubling delay (from the
## round-trip time) and, at a resend check, drops the peer once the oldest unacknowledged send is
## PEER_TIMEOUT_MAX_MS old, or once it is PEER_TIMEOUT_MIN_MS old and the command's attempts have
## reached the timeout limit (the 6th attempt at PEER_TIMEOUT_LIMIT 32). So a drop comes between
## the minimum and about twice it. On one PC ENet's default (5 to 30 s) dropped a stalled host
## after 9.8 s and a stalled client after 5.9 s; with EnetTransport's 10 to 20 s after 10.3 to
## 19.5 s and 12.0 to 14.3 s. On the Linux CI runner (5 runs of #95's PR) both dropped after 10.04
## to 10.07 s and the run took 13 s.
## - Every pair, the timeouts from the moment a connection exists: when the client reports
##   `connected` its host peer must already have EnetTransport's timeouts (applied_timeouts, set
##   in the poll ENet reports the connection in), and so must the host's peer when it reports
##   `peer_joined`. This is the deterministic check that each side calls set_timeout; the drops
##   below check that ENet honours it.
## - Pair 1, a host stalled at the moment of connection: the host stops polling as soon as its
##   client is connected, and the client must still have it after PEER_TIMEOUT_MIN_MS. With no
##   round trip measured yet ENet starts from 500 ms (resend checks at 0.5, 1.5, 3.5, 7.5, 15.5 and
##   31.5 s) and, with EnetTransport's 10 to 20 s as with ENet's default, drops only at about
##   31.5 s. So this pair cannot see a missing set_timeout; it guards only against a maximum below
##   about 7.5 s. Once it has held, neither side is polled again, so ENet's later drop cannot
##   fail the run. But ENet's clock is Godot's (milliseconds since the process started), and a
##   client pings at once when it connects with its clock past the 500 ms ping interval: only a
##   client that connects within its process's first 500 ms (as this run usually does) keeps the
##   31.5 s. One that connects later, as every real game client does from a menu, or this run when
##   its process starts slowly on a loaded PC, measures the round trip from that ping before the
##   stall and drops a host stalled at the connection at about 10 to 12 s instead (#443: 11.8 s
##   after a 600 ms start). A drop at PEER_TIMEOUT_MIN_MS or later is therefore the client keeping
##   the host as long as it must: a frame hitch across the 10 s mark lets that drop's poll run
##   before the hold is seen. A hitch spanning an earlier drop can hide it the same way (see
##   _on_drop).
## - Pair 2, the client's timeout on its host peer: both beat for WARM_MS, so the round trip is
##   measured, then the host stops polling. The client must drop it after PEER_TIMEOUT_MIN_MS to
##   PEER_TIMEOUT_MAX_MS. Known limit: both builds drop at a resend of the same doubling chain, and
##   when the resend before ENet's default drop lands just under 5 s, the default drops just past
##   10 s too (measured once at 9.77 s, 180 ms under the bound). So a removed client set_timeout
##   can pass here in a narrow band of round-trip times; the applied_timeouts check above cannot
##   miss it. A correct build cannot fail this bound, save a frame hitch of over EARLY_MS on the
##   stalled side just before it stops. That margin is thin on CI: drops 89 to 124 ms above the
##   bound. If a correct build ever drops under it, widen EARLY_MS, never the window's top.
## - Pair 3, the host's timeout on its client: first the backlog below; then both beat for
##   WARM_MS, the client stops polling, and the host must drop it within the same window.
## - The window's top is judged at the running side's last poll before the drop (StallWatch):
##   ENet drops only inside a service, so a main-thread hitch on a loaded PC delays the drop's
##   poll past the top although ENet dropped at its first chance (#443: 21649 ms, its run beside
##   two other verifies). The bottom is the drop's wall clock: a hitch only makes a drop later.
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
## PEER_TIMEOUT_MAX_MS: the running side's last poll before the drop may be this much past it.
const LATE_MS := 1000
## Poses in the backlog: more than one ENet service reads, few enough for a default socket receive
## buffer to hold them all. On Linux that is net.core.rmem_default (208 KB), which some container
## kernels fill at 256 small datagrams: doctor warns then and tools/cloud/setup.sh raises it (#159).
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
	## The stall, the running side's polls and its drop of the stalled side.
	var watch := StallWatch.new()
	var held := false
	var last_beat_ms := 0
	var backlog_due := false
	var backlog_sent_ms := -1
	var newest_pose := 0
	var poses_in_poll := 0

	func poll() -> void:
		if not host_paused:
			_poll_side(host, stalling == "client")
		if not client_paused:
			_poll_side(client, stalling == "host")

	func _poll_side(transport: EnetTransport, running: bool) -> void:
		var started := Time.get_ticks_msec()
		transport.poll()
		if running:
			watch.serviced(started)

	func warming() -> bool:
		return (
			connected_ms >= 0
			and watch.stalled_at_ms < 0
			and not backlog_due
			and backlog_sent_ms < 0
			and not hold_only
		)

	func stall() -> void:
		watch.stall(Time.get_ticks_msec())
		host_paused = stalling == "host"
		client_paused = stalling == "client"
		print("NET stall %s: the %s stops polling" % [name, stalling])

	## Reliable beats: both ways while warming, then from the running side to the stalled one.
	func beat() -> void:
		var now := Time.get_ticks_msec()
		if watch.dropped() or held or now - last_beat_ms < BEAT_EVERY_MS:
			return
		if not warming() and watch.stalled_at_ms < 0:
			return
		last_beat_ms = now
		if not client_paused:
			client.send(NetTransport.HOST_ID, BEAT, PackedByteArray([1]))
		if not host_paused and host.peers().size() == 1:
			host.send(host.peers()[0], BEAT, PackedByteArray([1]))

	func dropped() -> void:
		watch.drop(Time.get_ticks_msec())
		print(
			(
				"NET stall %s: the stalled %s dropped after %d ms (the poll before it: %d ms)"
				% [name, stalling, watch.dropped_after_ms(), watch.kept_after_ms()]
			)
		)

	func done() -> bool:
		return held or watch.dropped()


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
	pair.host.peer_joined.connect(_on_joined.bind(pair))
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
		if pair.backlog_due:
			_send_backlog(pair)
		elif pair.warming() and now - pair.connected_ms >= WARM_MS:
			pair.stall()
		elif pair.backlog_sent_ms >= 0 and now - pair.backlog_sent_ms >= BACKLOG_SETTLE_MS:
			_take_backlog(pair)
		elif pair.hold_only and not pair.held and pair.watch.stalled_at_ms >= 0:
			if now - pair.watch.stalled_at_ms >= EnetTransport.PEER_TIMEOUT_MIN_MS:
				_hold(pair, now - pair.watch.stalled_at_ms, "")
	if _pairs.all(func(pair: Pair) -> bool: return pair.done()):
		_finish()
	return false


func _on_connected(pair: Pair) -> void:
	pair.connected_ms = Time.get_ticks_msec()
	_check_timeouts(pair, "client", pair.client, NetTransport.HOST_ID)
	if pair.hold_only:
		pair.stall()
	elif pair.backlog:
		# Sent from _process: this handler runs inside the client's poll.
		pair.backlog_due = true


func _on_joined(peer_id: int, pair: Pair) -> void:
	_check_timeouts(pair, "host", pair.host, peer_id)


## The side reporting a connection must already have EnetTransport's timeouts on that peer.
func _check_timeouts(pair: Pair, side: String, transport: EnetTransport, peer_id: int) -> void:
	var want := Vector3i(
		EnetTransport.PEER_TIMEOUT_LIMIT,
		EnetTransport.PEER_TIMEOUT_MIN_MS,
		EnetTransport.PEER_TIMEOUT_MAX_MS
	)
	var have: Vector3i = transport.applied_timeouts.get(peer_id, Vector3i.ZERO)
	if have != want:
		_fail(
			(
				"%s: the %s reported the connection with timeouts %s on peer %d, not %s"
				% [pair.name, side, have, peer_id, want]
			)
		)


## Pair 1 kept its host for PEER_TIMEOUT_MIN_MS: ENet would drop it later (at about 31.5 s, or
## soon after 10 s once a round trip was measured), so neither side is polled again.
func _hold(pair: Pair, kept_ms: int, note: String) -> void:
	pair.held = true
	pair.host_paused = true
	pair.client_paused = true
	print("NET stall %s: the client kept the host for %d ms%s" % [pair.name, kept_ms, note])


## The running side lost the stalled one: expected, and timed. Pair 1 must have kept it first for
## PEER_TIMEOUT_MIN_MS: a drop at or after it, which a hitch let run before the hold was seen, is
## that hold. Its bottom is the drop's wall clock, so a hitch that spans a too-early drop can hide
## it (a maximum of about 7.5 s dropped at 10.5 s behind a hitch), as at the bottom of pairs 2 and
## 3; the hold line prints the poll before the drop to show such a gap.
func _on_drop(pair: Pair, side: String) -> void:
	if pair.held:
		return
	var running := "client" if pair.stalling == "host" else "host"
	if side != running or pair.watch.stalled_at_ms < 0:
		_fail("%s: the %s lost the other side in the run" % [pair.name, side])
		return
	pair.dropped()
	if not pair.hold_only:
		return
	var kept_ms := pair.watch.dropped_after_ms()
	if kept_ms < EnetTransport.PEER_TIMEOUT_MIN_MS:
		_fail(
			(
				"%s: the client dropped the stalled host after %d ms, under %d ms"
				% [pair.name, kept_ms, EnetTransport.PEER_TIMEOUT_MIN_MS]
			)
		)
		return
	_hold(
		pair,
		kept_ms,
		(
			", then dropped it at its resend check (its poll before: %d ms)"
			% pair.watch.kept_after_ms()
		)
	)


## One pose per client poll: each poll flushes what was sent since the last one as one datagram.
## The host is not polled until _take_backlog.
func _send_backlog(pair: Pair) -> void:
	pair.backlog_due = false
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
		var why := "" if pair.hold_only else pair.watch.judge(low, high)
		if why != "":
			var running := "client" if pair.stalling == "host" else "host"
			_fail(
				(
					"%s: the %s %s, not within %d to %d ms: its peer does not have EnetTransport's timeout"
					% [pair.name, running, why, low, high]
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
