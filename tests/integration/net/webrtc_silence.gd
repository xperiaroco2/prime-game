extends SceneTree
## A host and two clients over WebRtcTransport in one process on 127.0.0.1, silent for 30 s: the
## silence twin (the M6 design §2.6, #370). Headless:
##   tools\run.cmd run tests/integration/net/webrtc_silence.gd --headless -- --port=<p>
## --port is required (verify gives a free one): LanSignalling serves the room there. Exits 0 when
## it held, else prints an ERROR line and exits 1.
##
## Game messages alone stop for long stretches: a dead player sends no MoveClaim, and the Lobby,
## Loading and End send nothing at all. So poll() keeps each connection alive with KEEPALIVE when
## nothing went to a peer for KEEPALIVE_MS, and only SILENCE_MS without any packet is a leave.
## For SILENT_MS, longer than SILENCE_MS: the host sends client 2 a LATEST snapshot every 50 ms and
## client 2 sends nothing (a dead player); client 3 and the host send each other nothing (a silent
## Lobby). What must hold:
## - nobody is dropped, and the host receives no message at all;
## - each client's upload is keepalives alone, one a KEEPALIVE_MS: exactly the 3-byte frame plus
##   PACKET_OVERHEAD_BYTES each (take_upload, E56);
## - the host's upload is the snapshots plus keepalives to client 3 alone: client 2 hears
##   snapshots, so it needs none.

const ADDRESS := "127.0.0.1"
const PORT_ARG := "--port="
const CODE := "QWTRTC"
const DEADLINE_MS := 50000
const SILENT_MS := 30000
const SNAPSHOT_EVERY_MS := 50
const SNAPSHOT := 1  # host -> client, latest
const SNAPSHOT_BYTES := 16

var _kinds := NetKindTable.new()
var _started_ms := 0
var _done := false
var _signalling: LanSignalling
var _host: WebRtcTransport
## Instance number (2, 3) -> its client.
var _clients: Dictionary[int, WebRtcTransport] = {}
var _peer_of: Dictionary[int, int] = {}
var _silent_since_ms := -1
var _last_snapshot_ms := 0
var _snapshots := 0
var _snapshots_heard := 0
var _host_heard := 0


func _initialize() -> void:
	_kinds.add(SNAPSHOT, NetKindTable.Lane.LATEST, NetKindTable.Direction.HOST_TO_CLIENT, 64)
	_started_ms = Time.get_ticks_msec()
	var port_text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PORT_ARG):
			port_text = arg.trim_prefix(PORT_ARG)
	var port := port_text.to_int() if port_text.is_valid_int() else 0
	if port < 1 or port > 65535:
		_fail("give -- %s<a free port between 1 and 65535>, got '%s'" % [PORT_ARG, port_text])
		return
	_signalling = LanSignalling.new([], func() -> String: return CODE)
	var err := _signalling.listen(port, ADDRESS)
	if err != OK:
		_fail("signalling on %s:%d failed: %s" % [ADDRESS, port, error_string(err)])
		return
	_host = _new_transport(port)
	err = _host.host(0, 4)
	if err != OK:
		_fail("host failed: %s" % error_string(err))
		return
	_host.peer_left.connect(
		func(peer_id: int) -> void: _fail("the host dropped peer %d in the silence" % peer_id)
	)
	_host.packet_received.connect(
		func(_from: int, _kind: int, _payload: PackedByteArray) -> void: _host_heard += 1
	)
	for instance: int in [2, 3]:
		var client := _new_transport(port)
		client.connected.connect(_on_connected.bind(instance))
		client.connect_failed.connect(
			func(reason: StringName) -> void: _fail("client %d failed: %s" % [instance, reason])
		)
		client.host_lost.connect(
			func() -> void: _fail("client %d lost the host in the silence" % instance)
		)
		client.packet_received.connect(_on_client_packet.bind(instance))
		_clients[instance] = client


func _new_transport(port: int) -> WebRtcTransport:
	var transport := WebRtcTransport.new(_kinds)
	transport.signal_url = "ws://%s:%d" % [ADDRESS, port]
	transport.local_candidates = true
	return transport


func _process(_delta: float) -> bool:
	if _done:
		return false
	var now := Time.get_ticks_msec()
	if now - _started_ms > DEADLINE_MS:
		_fail("deadline: still %s" % ("joining" if _silent_since_ms < 0 else "silent"))
		return false
	_signalling.poll()
	_host.poll()
	for instance: int in _clients:
		var client := _clients[instance]
		if client.role() == NetTransport.Role.IDLE and _host.room_code() == CODE:
			if client.join(CODE, 0) != OK:
				_fail("client %d could not start its join" % instance)
				return false
		client.poll()
	if _done:
		return false
	if _silent_since_ms < 0:
		if _peer_of.size() == 2 and _host.peers().size() == 2:
			_start_silence()
	elif now - _silent_since_ms >= SILENT_MS:
		_finish()
	elif now - _last_snapshot_ms >= SNAPSHOT_EVERY_MS:
		_last_snapshot_ms = now
		var snapshot := PackedByteArray()
		snapshot.resize(SNAPSHOT_BYTES)
		if _host.send(_peer_of[2], SNAPSHOT, snapshot) != OK:
			_fail("a snapshot was not sent")
		_snapshots += 1
	return false


func _on_connected(own_id: int, instance: int) -> void:
	print("NET silence client %d connected as peer %d" % [instance, own_id])
	_peer_of[instance] = own_id


func _on_client_packet(_from: int, kind: int, _payload: PackedByteArray, instance: int) -> void:
	if instance != 2 or kind != SNAPSHOT:
		_fail("client %d got kind %d" % [instance, kind])
	_snapshots_heard += 1


## Counting starts here: whatever went out while joining is taken and dropped.
func _start_silence() -> void:
	_silent_since_ms = Time.get_ticks_msec()
	_last_snapshot_ms = _silent_since_ms
	_host.take_upload()
	for client: WebRtcTransport in _clients.values():
		client.take_upload()
	print("NET silence for %d ms: snapshots to client 2 only, nothing else" % SILENT_MS)


func _finish() -> void:
	var keepalive := WebRtcTransport.KEEPALIVE.size() + WebRtcTransport.PACKET_OVERHEAD_BYTES
	@warning_ignore("integer_division")
	var most := SILENT_MS / WebRtcTransport.KEEPALIVE_MS + 1
	var fewest := most - 3
	for instance: int in _clients:
		var upload := _clients[instance].take_upload()
		print("NET silence client %d sent %d B in %d packets" % [instance, upload.x, upload.y])
		if upload.y < fewest or upload.y > most or upload.x != upload.y * keepalive:
			_fail(
				(
					"client %d sent %d B in %d packets, not %d to %d keepalives of %d B"
					% [instance, upload.x, upload.y, fewest, most, keepalive]
				)
			)
			return
	var host_upload := _host.take_upload()
	var snapshot_bytes := (
		SNAPSHOT_BYTES
		+ NetFrame.HEADER_BYTES
		+ LaneOrder.HEADER_BYTES
		+ WebRtcTransport.PACKET_OVERHEAD_BYTES
	)
	var keepalives := host_upload.y - _snapshots
	print(
		(
			"NET silence the host sent %d B in %d packets: %d snapshots and %d keepalives"
			% [host_upload.x, host_upload.y, _snapshots, keepalives]
		)
	)
	if (
		keepalives < fewest
		or keepalives > most
		or host_upload.x != _snapshots * snapshot_bytes + keepalives * keepalive
	):
		_fail("the host's upload is not the snapshots and keepalives to client 3 alone")
		return
	if _host_heard != 0 or _snapshots_heard == 0:
		_fail("the host heard %d messages; client 2 %d snapshots" % [_host_heard, _snapshots_heard])
		return
	var rejected := _host.rejects.total()
	for client: WebRtcTransport in _clients.values():
		rejected += client.rejects.total()
	if rejected != 0:
		_fail("%d packet(s) rejected; the host's: %s" % [rejected, _host.rejects.totals()])
		return
	for client: WebRtcTransport in _clients.values():
		client.close()
	_host.close()
	_signalling.stop()
	print("NET silence nobody was dropped in %d ms of silence; PASS" % SILENT_MS)
	_done = true
	quit(0)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("NET silence FAIL: %s" % message)
	quit(1)
