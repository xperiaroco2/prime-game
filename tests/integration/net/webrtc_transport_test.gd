extends GdUnitTestSuite
## WebRtcTransport against forged peers in one process on 127.0.0.1 (the M6 design §2.3, §2.6 and
## §5; #370): what the headless twins cannot make an honest peer do. A FakePeer is a raw Signaller
## and WebRTCPeerConnection with the transport's three channels, playing a joiner or a host by
## hand. LanSignalling listens on a free port (0), so shards never clash. Waits are bounded: a
## condition polled frame by frame, never a sleep.

## The longest wait for one condition; a pass takes well under a second.
const MAX_WAIT_MS := 5000
## The joins these tests expect to give up do so after this long, not JOIN_TIMEOUT_MS.
const SHORT_JOIN_MS := 1500
const TALK := 1

var _kinds := NetKindTable.new()
var _server: LanSignalling
var _transports: Array[WebRtcTransport] = []
var _fakes: Array[FakePeer] = []
var _events := PackedStringArray()


## A raw peer that speaks the signalling protocol and opens the transport's channels, forging
## what an honest WebRtcTransport never sends.
class FakePeer:
	extends RefCounted
	var signaller := Signaller.new()
	var pc: WebRTCPeerConnection = null
	var channels: Dictionary[NetKindTable.Lane, WebRTCDataChannel] = {}
	var joiner := 0
	## Joiner: how many times it sends its answer; whether it leaves the service after the offer.
	var answers := 1
	var leave_on_offer := false
	var offers := 0

	func _init(url: String) -> void:
		signaller.connect_to(url)
		signaller.offer_received.connect(_on_offer)
		signaller.joiner_arrived.connect(_on_joiner)
		signaller.answer_received.connect(_on_answer)
		signaller.candidate_received.connect(_on_candidate)

	func poll() -> void:
		signaller.poll()
		if pc != null:
			pc.poll()
			for channel: WebRTCDataChannel in channels.values():
				channel.poll()

	func all_open() -> bool:
		if pc == null or pc.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED:
			return false
		for channel: WebRTCDataChannel in channels.values():
			if channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
				return false
		return true

	func put(lane: NetKindTable.Lane, bytes: PackedByteArray) -> void:
		channels[lane].put_packet(bytes)

	func take(lane: NetKindTable.Lane) -> Array[PackedByteArray]:
		var got: Array[PackedByteArray] = []
		while channels[lane].get_available_packet_count() > 0:
			got.append(channels[lane].get_packet())
		return got

	func close() -> void:
		signaller.close()
		if pc != null:
			pc.close()

	func _open_connection() -> void:
		pc = WebRTCPeerConnection.new()
		pc.initialize({"iceServers": []})
		for lane: NetKindTable.Lane in WebRtcTransport.CHANNEL_IDS:
			var options := {"negotiated": true, "id": WebRtcTransport.CHANNEL_IDS[lane]}
			if lane != NetKindTable.Lane.RELIABLE:
				options["ordered"] = false
				options["maxRetransmits"] = 0
			channels[lane] = pc.create_data_channel(str(lane), options)
		pc.session_description_created.connect(_on_description)
		pc.ice_candidate_created.connect(_on_local_candidate)

	func _on_offer(_id: int, sdp: String, _ice_servers: Array) -> void:
		offers += 1
		if leave_on_offer:
			signaller.close()
			return
		_open_connection()
		pc.set_remote_description("offer", sdp)

	func _on_joiner(from: int) -> void:
		joiner = from
		_open_connection()
		pc.create_offer()

	func _on_answer(_from: int, sdp: String) -> void:
		pc.set_remote_description("answer", sdp)

	func _on_description(type: String, sdp: String) -> void:
		pc.set_local_description(type, sdp)
		if type == "offer":
			signaller.send_offer(joiner, 7, sdp)
		else:
			for _i in answers:
				signaller.send_answer(sdp)

	func _on_local_candidate(media: String, index: int, cand: String) -> void:
		var local := WebRtcTransport._local(cand)
		if local.is_empty():
			return
		if joiner != 0:
			signaller.send_candidate_to(joiner, media, index, local)
		else:
			signaller.send_candidate(media, index, local)

	func _on_candidate(_from: int, mid: String, index: int, cand: String) -> void:
		if pc != null and not cand.is_empty():
			pc.add_ice_candidate(mid, index, cand)


func before() -> void:
	_kinds.add(TALK, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.BOTH, 64)


func before_test() -> void:
	_server = LanSignalling.new()
	assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)


func after_test() -> void:
	for transport: WebRtcTransport in _transports:
		transport.close()
	_transports.clear()
	for fake: FakePeer in _fakes:
		fake.close()
	_fakes.clear()
	_events.clear()
	_server.stop()


func test_a_join_with_an_unknown_code_fails_with_no_room() -> void:
	var client := _client()
	assert_int(client.join("ABCDEF", 0)).is_equal(OK)
	assert_bool(await _until(_has.bind("client failed no_room"))).is_true()


func test_a_join_with_no_service_fails_as_unreachable() -> void:
	var closed := TCPServer.new()
	assert_int(closed.listen(0, "127.0.0.1")).is_equal(OK)
	var port := closed.get_local_port()
	closed.stop()
	var client := _client()
	client.signal_url = "ws://127.0.0.1:%d" % port
	assert_int(client.join("ABCDEF", 0)).is_equal(OK)
	assert_bool(await _until(_has.bind("client failed service_unreachable"))).is_true()


func test_a_code_the_service_would_refuse_is_not_sent() -> void:
	assert_int(_client().join("ABC", 0)).is_equal(ERR_INVALID_PARAMETER)
	var unconfigured := WebRtcTransport.new(_kinds)
	assert_int(unconfigured.join("ABCDEF", 0)).is_equal(ERR_UNCONFIGURED)
	assert_int(unconfigured.host(0, 4)).is_equal(ERR_UNCONFIGURED)


## A joiner that took its offer and left the service still holds the host's only place until the
## half-made connection gives up: the next joiner gets no offer and its join gives up too.
func test_a_half_made_connection_counts_against_the_maximum() -> void:
	var host := _host(1)
	assert_bool(await _until(func() -> bool: return host.room_code() != "")).is_true()
	var half := _fake()
	half.leave_on_offer = true
	half.signaller.join_room(host.room_code())
	assert_bool(await _until(func() -> bool: return half.offers == 1)).is_true()
	assert_int(host.connection_count()).is_equal(1)
	var late := _client()
	assert_int(late.join(host.room_code(), 0)).is_equal(OK)
	assert_bool(await _until(_has.bind("client failed host_unreachable"))).is_true()
	assert_int(late.connection_count()).is_equal(0)
	assert_array(host.peers()).is_empty()


## The host never applies a second answer: libdatachannel would refuse it too (with an engine error
## line), so this checks the outcome, the connection closed, more than the host's own rule.
func test_a_second_answer_to_one_offer_closes_the_connection() -> void:
	var host := _host(4)
	assert_bool(await _until(func() -> bool: return host.room_code() != "")).is_true()
	var joiner := _fake()
	joiner.answers = 2
	joiner.signaller.join_room(host.room_code())
	assert_bool(await _until(func() -> bool: return joiner.offers == 1)).is_true()
	assert_bool(await _until(func() -> bool: return host.connection_count() == 0)).is_true()
	assert_bool(_has("host joined 2")).is_false()


## The client learns its id from ADMIT and refuses the host's own id: a host cannot make a client
## take peer 1, whom every other peer trusts.
func test_the_client_refuses_an_admit_of_the_host_id() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(NetTransport.HOST_ID))
	assert_bool(await _until(_has.bind("client failed connect_failed"))).is_true()
	assert_bool(_has("client connected 1")).is_false()


## Keepalives are exactly [0, 0, 0] on VOICE both ways and never reach the game; any other
## kind-0 packet is a counted reject.
func test_keepalives_go_on_voice_and_other_kind_0_packets_are_rejected() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	var heard: Array[PackedByteArray] = []
	var keepalive_came := func() -> bool:
		heard.append_array(fake_host.take(NetKindTable.Lane.VOICE))
		return not heard.is_empty()
	assert_bool(await _until(keepalive_came)).is_true()
	assert_array(heard).is_equal([PackedByteArray(WebRtcTransport.KEEPALIVE)])
	fake_host.put(NetKindTable.Lane.VOICE, PackedByteArray(WebRtcTransport.KEEPALIVE))
	fake_host.put(NetKindTable.Lane.RELIABLE, PackedByteArray(WebRtcTransport.KEEPALIVE))
	fake_host.put(NetKindTable.Lane.VOICE, PackedByteArray([0, 1, 0, 9]))
	fake_host.put(NetKindTable.Lane.RELIABLE, NetFrame.encode(TALK, "after".to_utf8_buffer()))
	assert_bool(await _until(_has.bind("client got 1 after"))).is_true()
	assert_int(client.rejects.of_reason(NetRejects.Reason.UNKNOWN_KIND)).is_equal(2)
	assert_int(client.rejects.total()).is_equal(2)


func _client() -> WebRtcTransport:
	var client := _transport()
	client.join_timeout_ms = SHORT_JOIN_MS
	client.connected.connect(func(id: int) -> void: _events.append("client connected %d" % id))
	client.connect_failed.connect(
		func(reason: StringName) -> void: _events.append("client failed %s" % reason)
	)
	client.packet_received.connect(
		func(_from: int, kind: int, payload: PackedByteArray) -> void:
			_events.append("client got %d %s" % [kind, payload.get_string_from_utf8()])
	)
	return client


func _host(max_clients: int) -> WebRtcTransport:
	var host := _transport()
	host.join_timeout_ms = SHORT_JOIN_MS * 2
	host.peer_joined.connect(func(id: int) -> void: _events.append("host joined %d" % id))
	assert_int(host.host(0, max_clients)).is_equal(OK)
	return host


func _transport() -> WebRtcTransport:
	var transport := WebRtcTransport.new(_kinds)
	transport.signal_url = "ws://127.0.0.1:%d" % _server.port()
	transport.local_candidates = true
	_transports.append(transport)
	return transport


func _fake() -> FakePeer:
	var fake := FakePeer.new("ws://127.0.0.1:%d" % _server.port())
	_fakes.append(fake)
	return fake


## A FakePeer hosting a room: it offers to whoever joins.
func _fake_host() -> FakePeer:
	var fake := _fake()
	var codes := PackedStringArray()
	fake.signaller.room_opened.connect(func(code: String, _ice: Array) -> void: codes.append(code))
	fake.signaller.open_room(0, 0, 4)
	assert_bool(await _until(func() -> bool: return codes.size() == 1)).is_true()
	fake.set_meta("code", codes[0])
	return fake


func _room_of(fake: FakePeer) -> String:
	await get_tree().process_frame
	return str(fake.get_meta("code"))


static func _admit(peer_id: int) -> PackedByteArray:
	var admit := PackedByteArray([0, 4, 0])
	admit.resize(WebRtcTransport.ADMIT_BYTES)
	admit.encode_u32(NetFrame.HEADER_BYTES, peer_id)
	return admit


func _has(line: String) -> bool:
	return line in _events


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		_server.poll()
		for transport: WebRtcTransport in _transports:
			transport.poll()
		for fake: FakePeer in _fakes:
			fake.poll()
		if condition.call():
			return true
		await get_tree().process_frame
	return false
