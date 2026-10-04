extends GdUnitTestSuite
## SignalRouter replays every shared transcript (tests/fixtures/signal/, ARCHITECTURE §4.8): after
## each step, exactly the expected messages to exactly the expected sockets, in order. The forged
## ones are the M6 ADR §5 check: a joiner's offer, a candidate with a "to", close and reopen never
## reach another joiner, and change no room.

const Transcripts := preload("res://tests/unit/net/signal/signal_transcripts.gd")


func test_there_is_a_transcript_per_flow_and_per_forged_type() -> void:
	assert_array(Transcripts.all().keys()).contains_exactly(Transcripts.NAMES)


func test_every_transcript_replays() -> void:
	var transcripts := Transcripts.all()
	assert_array(transcripts.keys()).contains_exactly(Transcripts.NAMES)
	var failures := PackedStringArray()
	for file: String in transcripts:
		# SignalRouter never mints TURN credentials: the Worker's service.test.js replays it.
		if Transcripts.turn_only(transcripts[file]):
			continue
		failures.append_array(_replay(file, transcripts[file]))
	assert_array(Array(failures)).is_empty()


func test_a_binary_message_is_a_bad_message() -> void:
	var router := SignalRouter.new([], func() -> String: return "ABCDEF")
	router.opened(1)
	var text := SignalCodec.encode(SignalCodec.Side.UNSET, "join", {"code": "ABCDEF"})
	var out := router.received(1, text.to_ascii_buffer(), false)
	assert_int(out.size()).is_equal(1)
	assert_str(str(out[0].message["why"])).is_equal(SignalCodec.WHY_BAD)


func test_a_message_from_an_unknown_or_closed_socket_is_ignored() -> void:
	var router := SignalRouter.new([], func() -> String: return "ABCDEF")
	var text := SignalCodec.encode(SignalCodec.Side.UNSET, "join", {"code": "ABCDEF"})
	assert_array(router.received(7, text.to_ascii_buffer())).is_empty()
	router.opened(7)
	router.closed(7)
	assert_array(router.received(7, text.to_ascii_buffer())).is_empty()
	assert_array(router.closed(7)).is_empty()


func test_no_free_code_is_an_error_and_no_room() -> void:
	var router := SignalRouter.new([], func() -> String: return "ABCDEF")
	var open := {"protocol": 7, "content": "0123456789abcdef", "max": 9}
	var text := SignalCodec.encode(SignalCodec.Side.UNSET, "open", open).to_ascii_buffer()
	router.opened(1)
	router.opened(2)
	assert_str(str(router.received(1, text)[0].message["t"])).is_equal("room")
	var out := router.received(2, text)
	assert_str(str(out[0].message["why"])).is_equal(SignalCodec.WHY_BUSY)
	assert_int(router.room_count()).is_equal(1)


## Replays one transcript; returns what went wrong, one line per wrong step.
func _replay(file: String, transcript: Dictionary) -> PackedStringArray:
	var failures := PackedStringArray()
	var router := SignalRouter.new(
		Transcripts.ice_servers(transcript), Transcripts.code_source(transcript)
	)
	var sockets: Dictionary[String, int] = {}
	var names: Dictionary[int, String] = {}
	var index := 0
	for step: Dictionary in Transcripts.steps_of(transcript):
		index += 1
		var out: Array[SignalRouter.Outgoing] = []
		if step.has("open"):
			var socket := sockets.size() + 1
			sockets[str(step["open"])] = socket
			names[socket] = str(step["open"])
			router.opened(socket)
		elif step.has("gone"):
			out = router.closed(sockets[str(step["gone"])])
		else:
			var text: String = step["raw"]
			out = router.received(sockets[str(step["from"])], text.to_ascii_buffer())
		var got := PackedStringArray()
		for each: SignalRouter.Outgoing in out:
			got.append(Transcripts.line(names[each.socket], each.message, each.close))
		var expected := Transcripts.expected_lines(step)
		if got != expected:
			failures.append("%s step %d: expected %s, got %s" % [file, index, expected, got])
	return failures
