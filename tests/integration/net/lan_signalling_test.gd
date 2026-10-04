extends GdUnitTestSuite
## LanSignalling over real WebSockets on 127.0.0.1 (ARCHITECTURE §4.8; the M6 ADR §6): it replays
## every shared transcript byte for byte from raw clients, and a host and a joiner Signaller go
## through a whole exchange through it. Each server listens on a free port (0), so shards never
## clash. Waits are bounded: a condition polled frame by frame, never a sleep.

const Transcripts := preload("res://tests/unit/net/signal/signal_transcripts.gd")
## The longest wait for one condition; a pass takes a few frames.
const MAX_WAIT_MS := 5000
const SDP := "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\n"
const CAND := "candidate:1 1 UDP 2122317823 127.0.0.1 50000 typ host"

var _server: LanSignalling
## Transcript replay: the raw clients by socket name, and what each received, as lines.
var _clients: Dictionary[String, WebSocketPeer] = {}
var _received: Dictionary[String, PackedStringArray] = {}
var _signallers: Array[Signaller] = []
var _events := PackedStringArray()


func after_test() -> void:
	for client: WebSocketPeer in _clients.values():
		client.close()
	_clients.clear()
	_received.clear()
	for signaller: Signaller in _signallers:
		signaller.close()
	_signallers.clear()
	_events.clear()
	if _server != null:
		_server.stop()
	_server = null


func test_every_transcript_replays_over_websockets() -> void:
	var transcripts := Transcripts.all()
	assert_int(transcripts.size()).is_greater_equal(8)
	for file: String in transcripts:
		var failures := await _replay(transcripts[file])
		(
			assert_array(Array(failures))
			. override_failure_message("%s: %s" % [file, "\n".join(failures)])
			. is_empty()
		)
		after_test()


func test_a_host_and_a_joiner_signal_through_it() -> void:
	_server = LanSignalling.new([], func() -> String: return "ABCDEF")
	_server.close_grace_ms = 100
	assert_int(_server.listen(0, "127.0.0.1")).is_equal(OK)
	var host := _signaller("host")
	var joiner := _signaller("joiner")
	assert_bool(host.open_room(7, -2, 9)).is_true()
	assert_bool(await _until(_has.bind("host room ABCDEF []"))).is_true()
	assert_bool(joiner.join_room("ABCDEF")).is_true()
	var content := SignalCodec.content_text(-2)
	assert_bool(await _until(_has.bind("joiner found 7 %s" % content))).is_true()
	assert_bool(await _until(_has.bind("host joiner 1"))).is_true()
	host.send_offer(1, 2, SDP)
	assert_bool(await _until(_has.bind("joiner offer 2 %s []" % SDP.c_escape()))).is_true()
	joiner.send_answer(SDP)
	assert_bool(await _until(_has.bind("host answer 1 %s" % SDP.c_escape()))).is_true()
	joiner.send_candidate("0", 0, CAND)
	assert_bool(await _until(_has.bind("host candidate 1 0 0 %s" % CAND))).is_true()
	host.send_candidate_to(1, "0", 0, CAND)
	assert_bool(await _until(_has.bind("joiner candidate 0 0 0 %s" % CAND))).is_true()
	host.close_room()
	var late := _signaller("late")
	late.join_room("ABCDEF")
	assert_bool(await _until(_has.bind("late refused %s" % SignalCodec.WHY_STARTED))).is_true()
	host.close()
	assert_bool(await _until(_has.bind("joiner refused %s" % SignalCodec.WHY_HOST_LEFT))).is_true()
	assert_bool(await _until(_has.bind("joiner closed"))).is_true()
	for signaller: Signaller in _signallers:
		assert_int(signaller.rejected).is_equal(0)


## Replays one transcript over WebSockets; returns what went wrong.
func _replay(transcript: Dictionary) -> PackedStringArray:
	var failures := PackedStringArray()
	_server = LanSignalling.new(
		Transcripts.ice_servers(transcript), Transcripts.code_source(transcript)
	)
	_server.close_grace_ms = 100
	if _server.listen(0, "127.0.0.1") != OK:
		return PackedStringArray(["could not listen"])
	var url := "ws://127.0.0.1:%d" % _server.port()
	var expected: Dictionary[String, PackedStringArray] = {}
	var closes: Dictionary[String, bool] = {}
	var index := 0
	for step: Dictionary in Transcripts.steps_of(transcript):
		index += 1
		var handled := _server.handled()
		if step.has("open"):
			var name_open := str(step["open"])
			var client := WebSocketPeer.new()
			client.connect_to_url(url)
			_clients[name_open] = client
			_received[name_open] = PackedStringArray()
		elif step.has("gone"):
			_clients[str(step["gone"])].close()
		else:
			var raw: String = step["raw"]
			_clients[str(step["from"])].send_text(raw)
		if not await _until(func() -> bool: return _server.handled() == handled + 1):
			failures.append("step %d: the server did not handle it" % index)
			return failures
		for each: Dictionary in step.get("expect", []):
			var to := str(each["to"])
			var lines: PackedStringArray = expected.get(to, PackedStringArray())
			lines.append(Transcripts.canonical(each["msg"]))
			expected[to] = lines
			if each.get("close", false):
				closes[to] = true
	if not await _until(_all_arrived.bind(expected)):
		failures.append("not everything arrived")
	for name_got: String in _received:
		var want: PackedStringArray = expected.get(name_got, PackedStringArray())
		if _received[name_got] != want:
			failures.append("%s: expected %s, got %s" % [name_got, want, _received[name_got]])
	for name_closed: String in closes:
		var state := _clients[name_closed].get_ready_state()
		if not await _until(func() -> bool: return _closed_by_service(name_closed)):
			failures.append("%s: not closed by the service (state %d)" % [name_closed, state])
	return failures


func _all_arrived(expected: Dictionary[String, PackedStringArray]) -> bool:
	for name_want: String in expected:
		var got: PackedStringArray = _received.get(name_want, PackedStringArray())
		if got.size() < expected[name_want].size():
			return false
	return true


func _closed_by_service(client_name: String) -> bool:
	return _clients[client_name].get_ready_state() == WebSocketPeer.STATE_CLOSED


## Polls everything once a frame until `condition` holds, at most MAX_WAIT_MS.
func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		_pump()
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _pump() -> void:
	_server.poll()
	for client_name: String in _clients:
		var client := _clients[client_name]
		client.poll()
		while client.get_available_packet_count() > 0:
			var json := JSON.new()
			json.parse(client.get_packet().get_string_from_ascii())
			_received[client_name].append(Transcripts.canonical(json.data))
	for signaller: Signaller in _signallers:
		signaller.poll()


func _has(line: String) -> bool:
	return _events.has(line)


## A Signaller connected to the server whose every signal is logged in _events as
## "<who> <signal> <arguments>".
func _signaller(who: String) -> Signaller:
	var signaller := Signaller.new()
	assert_int(signaller.connect_to("ws://127.0.0.1:%d" % _server.port())).is_equal(OK)
	var log_event := func(event: String, args: Array) -> void:
		var parts := PackedStringArray([who, event])
		for arg: Variant in args:
			parts.append(str(arg).c_escape() if arg is String else JSON.stringify(arg))
		_events.append(" ".join(parts))
	signaller.closed.connect(func() -> void: log_event.call("closed", []))
	signaller.room_opened.connect(
		func(code: String, ice: Array) -> void: log_event.call("room", [code, ice])
	)
	signaller.joiner_arrived.connect(func(n: int) -> void: log_event.call("joiner", [n]))
	signaller.answer_received.connect(
		func(n: int, sdp: String) -> void: log_event.call("answer", [n, sdp])
	)
	signaller.candidate_received.connect(
		func(n: int, mid: String, i: int, cand: String) -> void:
			log_event.call("candidate", [n, mid, i, cand])
	)
	signaller.room_found.connect(
		func(protocol: int, content: String) -> void: log_event.call("found", [protocol, content])
	)
	signaller.offer_received.connect(
		func(id: int, sdp: String, ice: Array) -> void: log_event.call("offer", [id, sdp, ice])
	)
	signaller.refused.connect(func(why: String) -> void: log_event.call("refused", [why]))
	_signallers.append(signaller)
	return signaller
