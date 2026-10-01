extends GdUnitTestSuite
## ClientSession (ARCHITECTURE §4.6) against a scripted host over a LoopbackHub: Hello on
## connected, intents with a rising seq, VoiceUp, the debug ForceRole, E14's client rule (before
## Welcome any Rejected ends the join with its reason), the ways a session ends, and that
## client/net/ reads no core/ state. Claims: client_session_claims_test.gd; loading:
## client_session_load_test.gd.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")

var _harness: Harness


func before_test() -> void:
	_harness = Harness.new()


func after_test() -> void:
	_harness.close()


func test_it_sends_hello_with_the_version_and_the_content_fingerprint_on_connected() -> void:
	var hellos := _harness.sent_named(&"Hello")
	assert_int(hellos.size()).is_equal(1)
	assert_int(hellos[0].fields["version"] as int).is_equal(WireSchema.VERSION)
	assert_int(hellos[0].fields["version"] as int).is_equal(JoinRules.PROTOCOL_VERSION)
	var content: int = hellos[0].fields["content"]
	var mode := _harness.mode
	assert_int(content).is_equal(
		ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)
	)
	assert_int(hellos[0].seq).is_equal(0)


func test_intents_go_out_with_a_rising_seq() -> void:
	_harness.welcome()
	assert_int(_harness.session.send_intent(Intents.SET_READY, {"ready": true})).is_equal(1)
	assert_int(_harness.session.send_intent(Intents.USE, {"facing": Vector3.FORWARD})).is_equal(2)
	assert_int(_harness.session.send_intent(Intents.PICK_UP, {"item": 3})).is_equal(3)
	_harness.pump()
	var seqs: Array[int] = []
	for message: WireMessage in _harness.sent:
		if message.name in [Intents.SET_READY, Intents.USE, Intents.PICK_UP]:
			seqs.append(message.seq)
	assert_array(seqs).contains_exactly([1, 2, 3])
	assert_bool(_harness.sent_named(Intents.SET_READY)[0].fields["ready"] as bool).is_true()
	assert_int(_harness.sent_named(Intents.PICK_UP)[0].fields["item"] as int).is_equal(3)


func test_an_intent_the_codec_refuses_is_not_sent_and_uses_no_seq() -> void:
	_harness.welcome()
	# An item id of 0xFFFF is none, which PickUp's item may not be.
	assert_int(_harness.session.send_intent(Intents.PICK_UP, {"item": 0xFFFF})).is_equal(-1)
	assert_int(_harness.session.send_intent(Intents.SET_READY, {"ready": true})).is_equal(1)


func test_voice_up_carries_the_frame_and_a_rising_seq() -> void:
	_harness.welcome()
	assert_int(_harness.session.send_voice(PackedByteArray([1, 2, 3]))).is_equal(OK)
	assert_int(_harness.session.send_voice(PackedByteArray([4]))).is_equal(OK)
	_harness.pump()
	var frames := _harness.sent_named(&"VoiceUp")
	assert_int(frames.size()).is_equal(2)
	assert_int(frames[0].fields["seq"] as int).is_equal(0)
	assert_int(frames[1].fields["seq"] as int).is_equal(1)
	assert_array(frames[0].fields["opus"] as PackedByteArray).is_equal(PackedByteArray([1, 2, 3]))


func test_force_role_names_the_player_and_the_role() -> void:
	_harness.welcome()
	assert_int(_harness.session.force_role(5, "dissident")).is_equal(1)
	assert_int(_harness.session.force_role(5, "")).is_equal(2)
	_harness.pump()
	var forced := _harness.sent_named(&"ForceRole")
	assert_int(forced.size()).is_equal(2)
	assert_int(forced[0].peer).is_equal(5)
	assert_str(forced[0].fields["role"] as String).is_equal("dissident")
	assert_str(forced[1].fields["role"] as String).is_equal("")


func test_a_rejected_before_welcome_ends_the_join_with_its_reason() -> void:
	_harness.send(RejectedEvent.new(_harness.peer, 0, &"wrong_content"))
	_harness.pump()
	assert_array(_harness.endings).contains_exactly([&"wrong_content"])
	assert_str(String(_harness.session.end_reason)).is_equal("wrong_content")
	assert_bool(_harness.session.is_welcomed()).is_false()
	# The Rejected is what it decoded (the leak test's refused bot).
	assert_array(_harness.session.view.event_names()).contains_exactly([&"Rejected"])
	# It left: the host sees it go, and it sends nothing more.
	assert_array(_harness.host.peers()).not_contains([_harness.peer])
	assert_int(_harness.session.send_intent(Intents.SET_READY, {"ready": true})).is_equal(-1)


func test_any_rejected_before_welcome_ends_the_join() -> void:
	# On main a Hello the phase refuses gets not_accepted and no disconnect (§4.3): still the end.
	_harness.send(RejectedEvent.new(_harness.peer, 0, &"not_accepted"))
	_harness.pump()
	assert_array(_harness.endings).contains_exactly([&"not_accepted"])


func test_a_rejected_after_welcome_ends_nothing() -> void:
	_harness.welcome()
	_harness.send(RejectedEvent.new(_harness.peer, 0, &"not_accepted"))
	_harness.send(RejectedEvent.new(_harness.peer, 1, &"unchanged"))
	_harness.pump()
	assert_array(_harness.endings).is_empty()
	assert_array(_harness.session.view.events_named(&"Rejected")).has_size(2)


func test_the_host_leaving_ends_the_session() -> void:
	_harness.welcome()
	_harness.host.close()
	_harness.pump()
	assert_array(_harness.endings).contains_exactly([ClientSession.HOST_LOST])


func test_a_disconnect_after_the_rejected_that_explains_it_ends_with_the_reason() -> void:
	_harness.send(RejectedEvent.new(_harness.peer, 0, &"wrong_version"))
	_harness.host.disconnect_peer(_harness.peer)
	_harness.pump()
	assert_array(_harness.endings).contains_exactly([&"wrong_version"])


func test_a_join_nobody_answers_ends_with_connect_failed() -> void:
	var client := LoopbackTransport.new(_harness.schema.kind_table(), _harness.hub)
	client.join("127.0.0.1", Harness.PORT + 1)
	var session := ClientSession.new(client, _harness.mode, _harness.schema)
	session.step(0)
	assert_str(String(session.end_reason)).is_equal(String(ClientSession.CONNECT_FAILED))


func test_the_welcome_is_recorded_as_core_emitted_it() -> void:
	var welcome := _harness.welcome()
	var events := _harness.session.view.events
	assert_int(events.size()).is_equal(1)
	assert_str(String(events[0].name)).is_equal("Welcome")
	assert_bool(WireSamples.same(events[0].fields, welcome.to_dict())).is_true()
	assert_int(_harness.session.view.peer).is_equal(_harness.peer)
	assert_bool(_harness.session.is_welcomed()).is_true()


func test_no_history_is_kept_unless_asked() -> void:
	_harness.session.keep_history = false
	_harness.welcome()
	assert_array(_harness.session.view.events).is_empty()
	assert_int(_harness.session.model.own_peer).is_equal(_harness.peer)


func test_client_net_reads_no_core_state() -> void:
	# Invariant 2: the client knows only what the host sent it. Its own copy of the game mode
	# (content) and core/'s constants are allowed; Match, its state and view_of are not.
	var forbidden := RegEx.create_from_string(
		(
			"\\b(Match|MatchState|MatchContext|PlayerState|ItemState|StationState|PeerView"
			+ "|Snapshots|HostSession|view_of|snapshot_for|speakers_for)\\b"
		)
	)
	assert_object(forbidden.search("var state: MatchState = session.state")).is_not_null()
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at("res://client/net"):
		if not file.ends_with(".gd"):
			continue
		var path := "res://client/net".path_join(file)
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := lines[i].split("#")[0]
			if forbidden.search(code) != null:
				found.append("%s:%d: %s" % [path, i + 1, lines[i].strip_edges()])
	assert_array(found).is_empty()
	assert_int(DirAccess.get_files_at("res://client/net").size()).is_greater(0)
