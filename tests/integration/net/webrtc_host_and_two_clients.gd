extends SceneTree
## A host and two clients over WebRTC on 127.0.0.1, one process each: the twin of
## enet_host_and_two_clients.gd (the M6 design §6, #370). Headless only:
##   tools\run.cmd run tests/integration/net/webrtc_host_and_two_clients.gd --headless
##     --instances 3 -- --port=<p>
## --port is required (verify gives a free one): the host serves LanSignalling there over ws://,
## with no ICE servers and a fixed room code, and every candidate is a host one on 127.0.0.1.
## PRIME_INSTANCE picks the part: 1 hosts and plays through its own loopback client; 2 and 3 join.
## Each process exits 0 when its part held, else prints an ERROR line and exits 1.
##
## The script: both clients join with the code and say hello; the host assigned them ids 2 and 3
## in order. A third client joins in the host's process and the host disconnects it
## (disconnect_peer) right after a last message: that message arrives first, the host sees
## peer_left once, the client host_lost. The host sends every peer (its own client too) one message
## per lane carrying that peer's id (the first ones' upload counted at once, take_upload: frame
## bytes plus E56's overhead per packet); each peer checks the id and echoes it, so a message sent
## on another peer's connection fails the run (the design's §5). The host starts refusing joins
## and proves it with a fourth client in its own process, which the service turns away with
## joins_closed. Client 3 leaves when told to. The host closes; client 2 and the host's own client
## see host_lost. No packet may be rejected anywhere.

const ADDRESS := "127.0.0.1"
const PORT_ARG := "--port="
const CODE := "TWNRTC"
const DEADLINE_MS := 60000
const RESEND_MS := 100
const RETRY_JOIN_MS := 500
const POLLS_AFTER_LOST := 10
const TALK := 1  # both ways, reliable
const LATEST := 2  # both ways, latest
const VOICE := 3  # both ways, voice lane
const COMMAND := 4  # host -> client, reliable
const LANES: Array[int] = [TALK, LATEST, VOICE]

var _kinds := NetKindTable.new()
var _instance := 0
var _port := 0
var _started_ms := 0
var _done := false
# Host part.
var _signalling: LanSignalling
var _host: WebRtcTransport
var _own: EchoClient
var _peer_of_instance: Dictionary[int, int] = {}
var _echoed: Dictionary[String, bool] = {}
var _last_resend_ms := 0
var _phase := ""
var _prober: WebRtcTransport
var _prober_result := ""
var _kickee: WebRtcTransport
var _kicked_id := 0
var _kicked_left := false
var _kickee_lost := false
var _kickee_got_bye := false
# Frames polled after host_lost, to see that it fires only once.
var _polls_after_lost := 0
# Client part.
var _client: EchoClient
var _next_join_ms := 0


## A client of the script: says hello, checks and echoes pings, leaves when told to.
class EchoClient:
	extends RefCounted
	var transport: NetTransport
	var instance: int
	var failure := ""
	var host_lost := false
	var host_lost_count := 0
	var told_to_leave := false
	var pinged_lanes: Dictionary[int, bool] = {}

	func _init(client_transport: NetTransport, instance_number: int) -> void:
		transport = client_transport
		instance = instance_number
		transport.connected.connect(_on_connected)
		transport.packet_received.connect(_on_packet_received)
		transport.host_lost.connect(_on_host_lost)

	func _on_connected(own_id: int) -> void:
		print("NET client %d connected as peer %d" % [instance, own_id])
		transport.send(NetTransport.HOST_ID, TALK, ("hello %d" % instance).to_utf8_buffer())

	func _on_packet_received(from_peer: int, kind: int, payload: PackedByteArray) -> void:
		var words := payload.get_string_from_utf8().split(" ")
		if from_peer != NetTransport.HOST_ID:
			failure = "a packet from peer %d, not the host" % from_peer
		elif kind == COMMAND and words[0] == "leave":
			told_to_leave = true
		elif kind in LANES and words.size() == 2 and words[0] == "ping":
			if int(words[1]) != transport.own_id():
				failure = "got peer %s's message on lane %d" % [words[1], kind]
				return
			pinged_lanes[kind] = true
			transport.send(from_peer, kind, ("echo %s" % words[1]).to_utf8_buffer())
		else:
			failure = "unexpected message kind %d: %s" % [kind, payload.get_string_from_utf8()]

	func _on_host_lost() -> void:
		host_lost = true
		host_lost_count += 1


func _initialize() -> void:
	_kinds.add(TALK, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.BOTH, 64)
	_kinds.add(LATEST, NetKindTable.Lane.LATEST, NetKindTable.Direction.BOTH, 64)
	_kinds.add(VOICE, NetKindTable.Lane.VOICE, NetKindTable.Direction.BOTH, 64)
	_kinds.add(COMMAND, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.HOST_TO_CLIENT, 64)
	_instance = int(OS.get_environment("PRIME_INSTANCE"))
	_started_ms = Time.get_ticks_msec()
	var port_text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PORT_ARG):
			port_text = arg.trim_prefix(PORT_ARG)
	_port = port_text.to_int() if port_text.is_valid_int() else 0
	if _port < 1 or _port > 65535:
		_fail("give -- %s<a free port between 1 and 65535>, got '%s'" % [PORT_ARG, port_text])
	elif _instance == 1:
		_start_host()
	elif _instance in [2, 3]:
		_client = EchoClient.new(_new_transport(), _instance)
		_client.transport.connect_failed.connect(_on_client_connect_failed)
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


func _new_transport() -> WebRtcTransport:
	var transport := WebRtcTransport.new(_kinds)
	transport.signal_url = "ws://%s:%d" % [ADDRESS, _port]
	transport.local_candidates = true
	return transport


func _start_host() -> void:
	_signalling = LanSignalling.new([], func() -> String: return CODE)
	var err := _signalling.listen(_port, ADDRESS)
	if err != OK:
		_fail("signalling on %s:%d failed: %s" % [ADDRESS, _port, error_string(err)])
		return
	_host = _new_transport()
	err = _host.host(0, 4)
	if err != OK:
		_fail("host failed: %s" % error_string(err))
		return
	_host.room_opened.connect(func(code: String) -> void: print("NET host room %s" % code))
	_host.peer_joined.connect(
		func(peer_id: int) -> void: print("NET host peer_joined %d" % peer_id)
	)
	_host.peer_left.connect(_on_host_peer_left)
	_host.packet_received.connect(_on_host_packet)
	_own = EchoClient.new(LoopbackTransport.own_client_of(_host), 1)
	_phase = "join"
	print("NET host signalling on ws://%s:%d" % [ADDRESS, _port])


func _host_step() -> void:
	_signalling.poll()
	_host.poll()
	if _own.transport.role() != NetTransport.Role.IDLE:
		_own.transport.poll()
	if _prober != null:
		_prober.poll()
	if _own.failure != "":
		_fail("own client: " + _own.failure)
		return
	match _phase:
		"join":
			if _peer_of_instance.size() == 3:
				_check_ids()
				_start_kick()
		"kick":
			_kick_step()
			if _kicked_left and _kickee_lost:
				print(
					(
						"NET host disconnected peer %d: it saw host_lost, the host peer_left"
						% _kicked_id
					)
				)
				_kickee = null
				_host.set_refuse_new_connections(true)
				print("NET host all joined %s; refusing new joins" % _peer_of_instance)
				_phase = "ping"
				_send_first_pings()
		"ping":
			_resend_unreliable_pings()
			if _echoed.size() == 3 * LANES.size():
				print("NET host every peer echoed its own id on every lane")
				_start_probe()
		"probe":
			if _prober_result == String(NetTransport.JOIN_STARTED):
				print(
					"NET host a join while refusing failed with %s, as it should" % _prober_result
				)
				_prober = null
				_phase = "leave"
				_host.send(_peer_of_instance[3], COMMAND, "leave".to_utf8_buffer())
			elif _prober_result != "":
				_fail("a join while refusing got: " + _prober_result)
		"close":
			if _own.host_lost:
				_polls_after_lost += 1
				if _polls_after_lost >= POLLS_AFTER_LOST:
					_finish_host()


## The host assigns ids from 2 upward in the order the joiners came: two remote clients, 2 and 3.
func _check_ids() -> void:
	var remote := [_peer_of_instance[2], _peer_of_instance[3]]
	remote.sort()
	if remote != [2, 3]:
		_fail("the clients got peer ids %s, not 2 and 3" % [remote])


## One reliable ping to every peer; take_upload() right after holds each remote ping as its frame
## plus WebRtcTransport.PACKET_OVERHEAD_BYTES (E56), one packet each, and the own client's nothing.
func _send_first_pings() -> void:
	_host.take_upload()
	var remote_bytes := 0
	var remote := 0
	for peer_id: int in _peer_of_instance.values():
		var payload := ("ping %d" % peer_id).to_utf8_buffer()
		_host.send(peer_id, TALK, payload)
		if peer_id != NetTransport.HOST_ID:
			remote += 1
			remote_bytes += (
				payload.size() + NetFrame.HEADER_BYTES + WebRtcTransport.PACKET_OVERHEAD_BYTES
			)
	var upload := _host.take_upload()
	if upload != Vector2i(remote_bytes, remote):
		_fail(
			(
				"the pings' upload was %d B in %d packets, expected %d B in %d"
				% [upload.x, upload.y, remote_bytes, remote]
			)
		)
		return
	print("NET host the first pings went out as %d B in %d packets" % [upload.x, upload.y])


func _resend_unreliable_pings() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_resend_ms < RESEND_MS:
		return
	_last_resend_ms = now
	for peer_id: int in _peer_of_instance.values():
		for kind: int in [LATEST, VOICE]:
			if not _echoed.has("%d/%d" % [peer_id, kind]):
				_host.send(peer_id, kind, ("ping %d" % peer_id).to_utf8_buffer())


func _start_kick() -> void:
	_phase = "kick"
	_kickee = _new_transport()
	_kickee.packet_received.connect(
		func(_from: int, kind: int, _payload: PackedByteArray) -> void:
			_kickee_got_bye = kind == COMMAND
	)
	_kickee.host_lost.connect(_on_kickee_host_lost)
	_kickee.connect_failed.connect(
		func(reason: StringName) -> void: _fail("the kick client could not join: %s" % reason)
	)
	var err := _kickee.join(CODE, 0)
	if err != OK:
		_fail("kick client failed to start: " + error_string(err))


## Once the extra client is connected on both sides, the host disconnects it.
func _kick_step() -> void:
	if _kickee != null:
		_kickee.poll()
	if _kicked_id != 0 or _kickee == null:
		return
	var id := _kickee.own_id()
	if NetTransport.HOST_ID in _kickee.peers() and id in _host.peers():
		_kicked_id = id
		if id != 4:
			_fail("the third joiner got peer id %d, not 4" % id)
			return
		# The last word before the kick must still arrive (a reason, say), as on the loopback.
		_host.send(id, COMMAND, "bye".to_utf8_buffer())
		var err := _host.disconnect_peer(id)
		if err != OK or id in _host.peers():
			_fail("disconnect_peer(%d) gave %s" % [id, error_string(err)])


func _on_kickee_host_lost() -> void:
	if not _kickee_got_bye:
		_fail("the disconnected client lost the host before the message sent just before the kick")
	_kickee_lost = true


func _start_probe() -> void:
	_phase = "probe"
	_prober = _new_transport()
	_prober.connected.connect(func(_id: int) -> void: _prober_result = "connected")
	_prober.connect_failed.connect(
		func(reason: StringName) -> void: _prober_result = String(reason)
	)
	var err := _prober.join(CODE, 0)
	if err != OK:
		_fail("probe join failed to start: " + error_string(err))


func _on_host_packet(from_peer: int, kind: int, payload: PackedByteArray) -> void:
	var words := payload.get_string_from_utf8().split(" ")
	if words.size() != 2:
		_fail("host got a malformed payload from %d" % from_peer)
	elif kind == TALK and words[0] == "hello":
		_peer_of_instance[int(words[1])] = from_peer
		print("NET host hello from instance %s = peer %d" % [words[1], from_peer])
	elif kind in LANES and words[0] == "echo":
		if int(words[1]) != from_peer:
			_fail("peer %d echoed peer %s's message" % [from_peer, words[1]])
		_echoed["%d/%d" % [from_peer, kind]] = true
	else:
		_fail("host got unexpected kind %d from %d" % [kind, from_peer])


func _on_host_peer_left(peer_id: int) -> void:
	print("NET host peer_left %d" % peer_id)
	if _phase == "kick" and peer_id == _kicked_id and not _kicked_left:
		_kicked_left = true
		return
	if _phase != "leave" or peer_id != _peer_of_instance[3]:
		_fail("peer %d left unexpectedly in phase '%s'" % [peer_id, _phase])
		return
	var expected := [1, _peer_of_instance[2]]
	expected.sort()
	if Array(_host.peers()) != expected:
		_fail("after client 3 left the host has peers %s, expected %s" % [_host.peers(), expected])
		return
	print("NET host closing (the host leaves)")
	_phase = "close"
	_host.close()


func _finish_host() -> void:
	var rejected := _host.rejects.total() + _own.transport.rejects.total()
	if rejected != 0:
		_fail("%d packet(s) rejected on the host" % rejected)
		return
	if _own.host_lost_count != 1:
		_fail("the host's own client saw host_lost %d times" % _own.host_lost_count)
		return
	_signalling.stop()
	print("NET host own client saw host_lost once; rejected=0; PASS")
	_pass()


func _client_step() -> void:
	var transport := _client.transport
	if _client.host_lost:
		transport.poll()  # a second host_lost would show up here
		_polls_after_lost += 1
		if _polls_after_lost >= POLLS_AFTER_LOST:
			_finish_client()
		return
	if transport.role() == NetTransport.Role.IDLE and not _client.told_to_leave:
		if Time.get_ticks_msec() >= _next_join_ms:
			var err := transport.join(CODE, 0)
			if err != OK:
				_fail("join failed to start: " + error_string(err))
				return
	transport.poll()
	if _client.failure != "":
		_fail(_client.failure)
	elif _client.told_to_leave:
		print("NET client %d leaving (rejected=%d)" % [_instance, transport.rejects.total()])
		transport.close()
		_check_client_rejects()
		if not _done:
			print("NET client %d PASS" % _instance)
			_pass()


func _on_client_connect_failed(reason: StringName) -> void:
	# The clients start with the host: until its service listens and its room is open, a join
	# fails and is tried again.
	print("NET client %d join failed (%s); retrying" % [_instance, reason])
	_next_join_ms = Time.get_ticks_msec() + RETRY_JOIN_MS


func _finish_client() -> void:
	if _instance != 2:
		_fail("client %d lost the host before it was told to leave" % _instance)
		return
	if _client.pinged_lanes.size() != LANES.size():
		_fail("client 2 got pings on lanes " + str(_client.pinged_lanes.keys()))
		return
	if _client.host_lost_count != 1:
		_fail("client 2 saw host_lost %d times" % _client.host_lost_count)
		return
	_check_client_rejects()
	if not _done:
		print("NET client 2 saw host_lost after the host left; PASS")
		_pass()


func _check_client_rejects() -> void:
	if _client.transport.rejects.total() != 0:
		_fail("%d packet(s) rejected on client %d" % [_client.transport.rejects.total(), _instance])


func _pass() -> void:
	_done = true
	quit(0)


func _fail(message: String) -> void:
	if _done:
		return
	_done = true
	push_error("NET instance %d FAIL: %s" % [_instance, message])
	quit(1)
