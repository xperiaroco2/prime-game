extends GdUnitTestSuite
## WebRtcTransport against forged peers in one process on 127.0.0.1 (the M6 design §2.3, §2.6 and
## §5; #370): what the headless twins cannot make an honest peer do. A FakePeer is a raw Signaller
## and WebRTCPeerConnection with the transport's three channels, playing a joiner or a host by
## hand. LanSignalling listens on a free port (0), so shards never clash. Waits are bounded: a
## condition polled frame by frame, never a sleep. A WebRtcWarmUp lives as long as the suite, so
## the WebRTC library's setup (seconds under load) is in no test's wait (#472).

const WebRtcWarmUp := preload("res://tests/integration/net/webrtc_warm_up.gd")
## The longest wait for one condition, unless a test names its own; a pass takes well under a
## second.
const MAX_WAIT_MS := 5000
## The longest wait for the WebRTC library's setup: 9 to 11 s were measured under load (#472).
const WARM_UP_MS := 30000
## The joins these tests expect to give up do so after this long, not JOIN_TIMEOUT_MS. Every
## other client keeps JOIN_TIMEOUT_MS unless its test names its own: under load a join took up
## to 1.7 s (#472).
const SHORT_JOIN_MS := 1500
const TALK := 1
const STATE := 2

var _kinds := NetKindTable.new()
var _server: LanSignalling
var _transports: Array[WebRtcTransport] = []
var _fakes: Array[FakePeer] = []
var _events := PackedStringArray()
var _warm_up: WebRtcWarmUp


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
	_kinds.add(STATE, NetKindTable.Lane.LATEST, NetKindTable.Direction.BOTH, 64)
	_warm_up = WebRtcWarmUp.new()
	var deadline := Time.get_ticks_msec() + WARM_UP_MS
	while not _warm_up.is_ready() and _warm_up.error == OK and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var why := _warm_up.error_text
	if why.is_empty():
		why = "no offer in %d ms" % WARM_UP_MS
	(
		assert_bool(_warm_up.is_ready())
		. override_failure_message("the WebRTC warm-up is not ready: %s (#472)" % why)
		. is_true()
	)


func after() -> void:
	_warm_up.close()


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
	client.join_timeout_ms = SHORT_JOIN_MS
	assert_int(client.join("ABCDEF", 0)).is_equal(OK)
	assert_bool(await _until(_has.bind("client failed no_room"))).is_true()


## Nothing listens at the service's port. On Linux the refused connect closes the socket at once;
## on Windows the engine never reports it before its 30 s TCP connect timeout (the OS knows in
## about 2 s, #461), so the Signaller's connect timeout ends it, as service_unreachable all the
## same.
func test_a_join_with_no_service_fails_as_unreachable() -> void:
	var closed := TCPServer.new()
	assert_int(closed.listen(0, "127.0.0.1")).is_equal(OK)
	var port := closed.get_local_port()
	closed.stop()
	var client := _client()
	client.signal_url = "ws://127.0.0.1:%d" % port
	client.join_timeout_ms = SHORT_JOIN_MS
	# Under the shortened join timeout: on Windows a refused connect stays connecting (#431).
	client.signal_connect_timeout_ms = SHORT_JOIN_MS >> 1
	assert_int(client.join("ABCDEF", 0)).is_equal(OK)
	assert_bool(await _until(_has.bind("client failed service_unreachable"))).is_true()


## A service that takes the TCP connection and never answers the WebSocket handshake: the socket
## never opens, on every OS. The Signaller's connect timeout ends the join, long before the join
## timeout (#461).
func test_a_service_that_never_opens_ends_the_join_after_the_connect_timeout() -> void:
	var silent := TCPServer.new()
	assert_int(silent.listen(0, "127.0.0.1")).is_equal(OK)
	var client := _client()
	client.signal_url = "ws://127.0.0.1:%d" % silent.get_local_port()
	client.signal_connect_timeout_ms = SHORT_JOIN_MS
	client.join_timeout_ms = MAX_WAIT_MS * 2
	var started_ms := Time.get_ticks_msec()
	assert_int(client.join("ABCDEF", 0)).is_equal(OK)
	assert_bool(await _until(_has.bind("client failed service_unreachable"))).is_true()
	assert_int(Time.get_ticks_msec() - started_ms).is_greater_equal(SHORT_JOIN_MS)
	silent.stop()


## With the shipped timeouts a silent service ends the join as service_unreachable after
## Signaller.CONNECT_TIMEOUT_MS, before JOIN_TIMEOUT_MS could call the host unreachable (#461).
func test_a_silent_service_ends_a_default_join_as_service_unreachable() -> void:
	var silent := TCPServer.new()
	assert_int(silent.listen(0, "127.0.0.1")).is_equal(OK)
	var client := _client()
	client.signal_url = "ws://127.0.0.1:%d" % silent.get_local_port()
	client.join_timeout_ms = WebRtcTransport.JOIN_TIMEOUT_MS
	assert_int(client.signal_connect_timeout_ms).is_equal(Signaller.CONNECT_TIMEOUT_MS)
	assert_int(Signaller.CONNECT_TIMEOUT_MS).is_less(WebRtcTransport.JOIN_TIMEOUT_MS)
	var started_ms := Time.get_ticks_msec()
	assert_int(client.join("ABCDEF", 0)).is_equal(OK)
	var failed := _has.bind("client failed service_unreachable")
	assert_bool(await _until(failed, Signaller.CONNECT_TIMEOUT_MS + MAX_WAIT_MS)).is_true()
	assert_int(Time.get_ticks_msec() - started_ms).is_greater_equal(Signaller.CONNECT_TIMEOUT_MS)
	assert_bool(_has("client failed host_unreachable")).is_false()
	silent.stop()


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
	late.join_timeout_ms = SHORT_JOIN_MS
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


## The own connection (the M6 design §3 item 4, #431): a client measuring its round trip pings the
## host on VOICE once admitted and every PING_INTERVAL_MS; the answer, echoing the client's clock,
## gives the round trip, and with no TURN server the kind is direct. Neither reaches the game.
func test_a_measuring_client_pings_and_the_answer_gives_its_round_trip() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	client.measure_round_trip = true
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	assert_int(client.own_route()).is_equal(NetTransport.Route.NONE)
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	assert_int(client.own_route()).is_equal(NetTransport.Route.DIRECT)
	assert_int(client.own_round_trip_ms()).is_equal(-1)
	var pings: Array[PackedByteArray] = []
	var pinged := func() -> bool:
		pings.append_array(_probes(fake_host, WebRtcTransport.PING))
		return not pings.is_empty()
	assert_bool(await _until(pinged)).is_true()
	assert_int(pings[0].size()).is_equal(WebRtcTransport.PING_BYTES)
	var answer := pings[0].duplicate()
	answer[NetFrame.HEADER_BYTES] = WebRtcTransport.PONG
	fake_host.put(NetKindTable.Lane.VOICE, answer)
	assert_bool(await _until(func() -> bool: return client.own_round_trip_ms() >= 0)).is_true()
	assert_int(client.own_round_trip_ms()).is_less(MAX_WAIT_MS)
	assert_int(client.rejects.total()).is_equal(0)
	assert_bool(_any_begins_with("client got")).is_false()
	client.close()
	assert_int(client.own_route()).is_equal(NetTransport.Route.NONE)
	assert_int(client.own_round_trip_ms()).is_equal(-1)


## Turning measuring off forgets the round trip: reopened later, the line reads "not measured yet"
## until the first new answer, never the figure of minutes ago.
func test_turning_measuring_off_forgets_the_round_trip() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	client.measure_round_trip = true
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	var pings: Array[PackedByteArray] = []
	var pinged := func() -> bool:
		pings.append_array(_probes(fake_host, WebRtcTransport.PING))
		return not pings.is_empty()
	assert_bool(await _until(pinged)).is_true()
	var answer := pings[0].duplicate()
	answer[NetFrame.HEADER_BYTES] = WebRtcTransport.PONG
	fake_host.put(NetKindTable.Lane.VOICE, answer)
	assert_bool(await _until(func() -> bool: return client.own_round_trip_ms() >= 0)).is_true()
	client.measure_round_trip = false
	assert_bool(await _until(func() -> bool: return client.own_round_trip_ms() == -1)).is_true()
	client.measure_round_trip = true
	await _poll_for(300, func() -> void: pass)
	assert_int(client.own_round_trip_ms()).is_equal(-1)


## A client not measuring sends no ping, so its upload stays the keepalives of §2.6.
func test_a_client_not_measuring_sends_no_ping() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	var heard: Array[PackedByteArray] = []
	var take_voice := func() -> void: heard.append_array(fake_host.take(NetKindTable.Lane.VOICE))
	await _poll_for(WebRtcTransport.PING_INTERVAL_MS + 300, take_voice)
	# Under load the first keepalive came up to 1.7 s after the admit (#472): listen on for it.
	var heard_one := func() -> bool:
		take_voice.call()
		return not heard.is_empty()
	assert_bool(await _until(heard_one)).is_true()
	for bytes: PackedByteArray in heard:
		assert_bool(bytes == PackedByteArray(WebRtcTransport.KEEPALIVE)).is_true()


## The host answers the pings a peer sent since its last poll once, echoing the last one read
## (VOICE is unordered, so the last read); its own route is none: a host has no connection of its
## own, and nothing tells it a peer's.
func test_the_host_answers_the_pings_of_one_poll_once() -> void:
	var joiner := await _admitted_fake()
	var host := _transports[0]
	joiner.put(NetKindTable.Lane.VOICE, _probe(WebRtcTransport.PING, 5))
	joiner.put(NetKindTable.Lane.VOICE, _probe(WebRtcTransport.PING, 9))
	await _idle(300)
	var answers: Array[PackedByteArray] = []
	var answered := func() -> bool:
		answers.append_array(_probes(joiner, WebRtcTransport.PONG))
		return not answers.is_empty()
	assert_bool(await _until(answered)).is_true()
	await _poll_for(
		300, func() -> void: answers.append_array(_probes(joiner, WebRtcTransport.PONG))
	)
	assert_int(answers.size()).is_equal(1)
	assert_int(answers[0].size()).is_equal(WebRtcTransport.PING_BYTES)
	assert_int(answers[0].decode_u32(NetFrame.HEADER_BYTES + 1)).is_in([5, 9])
	assert_int(host.rejects.total()).is_equal(0)
	assert_bool(_any_begins_with("host got")).is_false()
	assert_int(host.own_route()).is_equal(NetTransport.Route.NONE)
	assert_int(host.own_round_trip_ms()).is_equal(-1)


## A ping the wrong way is a kind-0 packet like any other: rejected. An answer to a ping the host
## never got (stamped later than now) changes no round trip.
func test_probes_the_wrong_way_are_rejected_and_an_impossible_answer_ignored() -> void:
	var joiner := await _admitted_fake()
	var host := _transports[0]
	joiner.put(NetKindTable.Lane.VOICE, _probe(WebRtcTransport.PONG, 1))
	assert_bool(await _until(func() -> bool: return host.rejects.total() == 1)).is_true()
	assert_int(host.rejects.of_reason(NetRejects.Reason.UNKNOWN_KIND)).is_equal(1)
	var fake_host := await _fake_host()
	var client := _client()
	client.measure_round_trip = true
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	fake_host.put(NetKindTable.Lane.VOICE, _probe(WebRtcTransport.PING, 1))
	var future := (Time.get_ticks_msec() + 60000) & 0xFFFFFFFF
	fake_host.put(NetKindTable.Lane.VOICE, _probe(WebRtcTransport.PONG, future))
	assert_bool(await _until(func() -> bool: return client.rejects.total() == 1)).is_true()
	await _poll_for(300, func() -> void: pass)
	assert_int(client.rejects.of_reason(NetRejects.Reason.UNKNOWN_KIND)).is_equal(1)
	assert_int(client.rejects.total()).is_equal(1)
	assert_int(client.own_round_trip_ms()).is_equal(-1)


## The peer never reads an empty message, so the transport refuses one rather than count it for
## LaneOrder: counted, every later LATEST packet would name one reliable packet more than the host
## ever reads, wait for the next one and arrive behind it (#429: a chaos peer's 0-byte frame put
## its LATEST claims behind the RELIABLE claims sent after them).
func test_an_empty_packet_is_refused_and_not_counted_for_lane_order() -> void:
	var fake_host := await _fake_host()
	var client := BotWebRtc.new(_kinds, _server.port(), 0)
	_transports.append(client)
	client.connected.connect(func(id: int) -> void: _events.append("client connected %d" % id))
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	var empty := ChaosFrames.Packet.new()
	assert_bool(client.send_raw(empty)).is_false()
	assert_int(client.send(NetTransport.HOST_ID, STATE, "now".to_utf8_buffer())).is_equal(OK)
	var latest: Array[PackedByteArray] = []
	var latest_came := func() -> bool:
		latest.append_array(fake_host.take(NetKindTable.Lane.LATEST))
		return not latest.is_empty()
	assert_bool(await _until(latest_came)).is_true()
	assert_array(fake_host.take(NetKindTable.Lane.RELIABLE)).is_empty()
	# LaneOrder's header: the reliable packets sent before it, none of which was empty.
	assert_int(latest[0].decode_u16(0)).is_equal(0)


## A client's own close resets its channels before the connection ends, and under load the host
## can read the first in a poll before the second: that is an honest leave, never a reject.
func test_a_client_closing_its_channels_then_its_connection_leaves_unrejected() -> void:
	var joiner := await _admitted_fake()
	joiner.channels[NetKindTable.Lane.LATEST].close()
	var after := Time.get_ticks_msec() + WebRtcTransport.CHANNEL_GRACE_MS / 4
	await _until(func() -> bool: return Time.get_ticks_msec() >= after)
	joiner.pc.close()
	assert_bool(await _until(_has.bind("host left 2"))).is_true()
	assert_int(_transports[0].rejects.total()).is_equal(0)


## A channel closed under a connection that stays up is a fault: the peer leaves after the grace,
## counted as CHANNEL_CLOSED.
func test_a_channel_closed_under_a_live_connection_is_a_counted_leave() -> void:
	var joiner := await _admitted_fake()
	var closed_ms := Time.get_ticks_msec()
	joiner.channels[NetKindTable.Lane.LATEST].close()
	assert_bool(await _until(_has.bind("host left 2"))).is_true()
	assert_int(Time.get_ticks_msec() - closed_ms).is_greater_equal(WebRtcTransport.CHANNEL_GRACE_MS)
	var host := _transports[0]
	assert_int(host.rejects.of_reason(NetRejects.Reason.CHANNEL_CLOSED)).is_equal(1)
	assert_int(host.rejects.total()).is_equal(1)


## What a peer sent just before its connection ended is read before the leave, as ENet delivers
## it: the host reads the closed connection and the packet in the same poll.
func test_a_peers_last_message_comes_before_its_leave() -> void:
	var joiner := await _admitted_fake()
	joiner.put(NetKindTable.Lane.RELIABLE, NetFrame.encode(TALK, "last".to_utf8_buffer()))
	joiner.pc.close()
	await _idle(200)
	assert_bool(await _until(_has.bind("host left 2"))).is_true()
	assert_array(_events.slice(_events.find("host got 2 1 last"))).contains_exactly(
		["host got 2 1 last", "host left 2"]
	)


## disconnect_peer's reason arrives before host_lost even when the client reads the reason and
## the closed channel in the same poll.
func test_the_reason_before_a_kick_arrives_when_read_with_the_close() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	client.host_lost.connect(func() -> void: _events.append("client lost the host"))
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()
	fake_host.put(NetKindTable.Lane.RELIABLE, NetFrame.encode(TALK, "reason".to_utf8_buffer()))
	fake_host.channels[NetKindTable.Lane.RELIABLE].close()
	await _idle(200)
	assert_bool(await _until(_has.bind("client lost the host"))).is_true()
	assert_array(_events.slice(_events.find("client got 1 reason"))).contains_exactly(
		["client got 1 reason", "client lost the host"]
	)


## The host's signalling socket going away ends a join still waiting for an offer, not one whose
## connection is already being made: the service says "the host left" to every joiner first.
func test_a_join_under_way_outlives_the_hosts_signalling() -> void:
	var fake_host := await _fake_host()
	var client := _client()
	assert_int(client.join(await _room_of(fake_host), 0)).is_equal(OK)
	assert_bool(await _until(fake_host.all_open)).is_true()
	fake_host.signaller.close()
	await _idle(200)
	fake_host.put(NetKindTable.Lane.RELIABLE, _admit(2))
	assert_bool(await _until(_has.bind("client connected 2"))).is_true()


## Ids are never reused in a session: after peer 2 leaves, the next joiner is peer 3.
func test_a_freed_id_is_not_handed_out_again() -> void:
	var first := await _admitted_fake()
	first.close()
	assert_bool(await _until(_has.bind("host left 2"))).is_true()
	var second := _fake()
	second.signaller.join_room(_transports[0].room_code())
	assert_bool(await _until(_has.bind("host joined 3"))).is_true()


## A FakePeer joiner the host admitted as peer 2.
func _admitted_fake() -> FakePeer:
	var host := _host(4)
	host.peer_left.connect(func(id: int) -> void: _events.append("host left %d" % id))
	host.packet_received.connect(
		func(from: int, kind: int, payload: PackedByteArray) -> void:
			_events.append("host got %d %d %s" % [from, kind, payload.get_string_from_utf8()])
	)
	assert_bool(await _until(func() -> bool: return host.room_code() != "")).is_true()
	var joiner := _fake()
	joiner.signaller.join_room(host.room_code())
	assert_bool(await _until(_has.bind("host joined 2"))).is_true()
	assert_bool(await _until(joiner.all_open)).is_true()
	return joiner


## Waits `ms` while polling only the fakes, so what they send piles up for one transport poll.
func _idle(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		_server.poll()
		for fake: FakePeer in _fakes:
			fake.poll()
		await get_tree().process_frame


func _client() -> WebRtcTransport:
	var client := _transport()
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


## A round-trip probe as WebRtcTransport sends it: a kind-0 frame of 5 bytes, its type and a stamp.
static func _probe(type: int, stamp: int) -> PackedByteArray:
	var bytes := PackedByteArray([0, 5, 0, type, 0, 0, 0, 0])
	bytes.encode_u32(NetFrame.HEADER_BYTES + 1, stamp)
	return bytes


## The probes of `type` the fake has received on VOICE since the last take (keepalives dropped).
static func _probes(fake: FakePeer, type: int) -> Array[PackedByteArray]:
	var found: Array[PackedByteArray] = []
	for bytes: PackedByteArray in fake.take(NetKindTable.Lane.VOICE):
		if bytes.size() == WebRtcTransport.PING_BYTES and bytes[NetFrame.HEADER_BYTES] == type:
			found.append(bytes)
	return found


## Polls everything for `ms`, calling `each` after every round.
func _poll_for(ms: int, each: Callable) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		_server.poll()
		for transport: WebRtcTransport in _transports:
			transport.poll()
		for fake: FakePeer in _fakes:
			fake.poll()
		each.call()
		await get_tree().process_frame


func _any_begins_with(prefix: String) -> bool:
	return Array(_events).any(func(line: String) -> bool: return line.begins_with(prefix))


func _has(line: String) -> bool:
	return line in _events


func _until(condition: Callable, max_wait_ms := MAX_WAIT_MS) -> bool:
	var deadline := Time.get_ticks_msec() + max_wait_ms
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
