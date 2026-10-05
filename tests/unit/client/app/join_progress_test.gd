extends GdUnitTestSuite
## JoinProgress (client/app/join_progress.gd; the M6 design §2.3, §2.5, §3): the connecting
## screen's steps, the version check against the service's `found`, the lobby's code line, and
## each join failure's words (EndReasons).

const P := preload("res://client/app/join_progress.gd")


func test_the_steps_of_a_code_join_and_a_direct_one() -> void:
	assert_int(P.step(true, -1, false)).is_equal(P.Step.FINDING)
	assert_int(P.step(true, 7, false)).is_equal(P.Step.CONNECTING)
	assert_int(P.step(true, 7, true)).is_equal(P.Step.JOINED)
	assert_int(P.step(false, -1, false)).is_equal(P.Step.CONNECTING)
	assert_int(P.step(false, -1, true)).is_equal(P.Step.JOINED)
	assert_str(P.step_text(true, -1, false)).is_equal("Finding the game")
	assert_str(P.step_text(false, -1, false)).is_equal("Connecting")
	assert_str(P.step_text(true, 3, true)).contains("Joined")


func test_the_connecting_screen_names_what_the_player_typed() -> void:
	assert_str(P.target_text(JoinTarget.of_code("k7m2qx"))).is_equal(
		"Joining the game with code K7M2QX"
	)
	assert_str(P.target_text(JoinTarget.of_direct("10.0.0.2", 24600))).is_equal(
		"Joining 10.0.0.2:24600"
	)


func test_the_version_check_waits_for_found_then_compares_protocol_then_content() -> void:
	assert_str(String(P.found_mismatch(-1, 5, 7, 9))).is_empty()
	assert_str(String(P.found_mismatch(7, 9, 7, 9))).is_empty()
	assert_str(String(P.found_mismatch(6, 9, 7, 9))).is_equal("wrong_version")
	assert_str(String(P.found_mismatch(6, 1, 7, 9))).is_equal("wrong_version")
	assert_str(String(P.found_mismatch(7, 1, 7, 9))).is_equal("wrong_content")
	# The ids are the host's own refusals, so the menu words them alike.
	assert_str(String(P.found_mismatch(6, 9, 7, 9))).is_equal(String(RejectReasons.WRONG_VERSION))
	assert_str(String(P.found_mismatch(7, 1, 7, 9))).is_equal(String(RejectReasons.WRONG_CONTENT))


func test_another_version_names_the_hosts_and_the_own() -> void:
	var version := P.found_detail(&"wrong_version", 6, 0, 7, 0)
	assert_str(version).is_equal("the host runs protocol 6, this game 7")
	var content := P.found_detail(&"wrong_content", 7, 1, 7, 2)
	assert_str(content).contains("another build")
	assert_str(content).contains(SignalCodec.content_text(1))
	assert_str(content).contains(SignalCodec.content_text(2))
	assert_str(P.found_detail(&"full", 7, 1, 7, 2)).is_empty()


func test_the_lobby_code_line() -> void:
	assert_str(P.code_text("K7M2QX", false)).is_equal("Code: K7M2QX")
	assert_str(P.code_text("", false)).is_empty()
	assert_str(P.code_text("", true)).is_equal(P.CODE_GONE)
	assert_str(P.CODE_GONE).contains("gone")


func test_each_join_failure_in_plain_words() -> void:
	var words: Dictionary[StringName, String] = {
		NetTransport.JOIN_NO_ROOM: "no game has that code",
		NetTransport.JOIN_STARTED: "under way",
		&"wrong_version": "another protocol version",
		&"wrong_content": "another build",
		NetTransport.JOIN_SERVICE_UNREACHABLE: "Direct (LAN or VPN)",
		NetTransport.JOIN_FULL: "full",
	}
	for reason: StringName in words:
		assert_str(EndReasons.words(reason)).override_failure_message(reason).contains(
			words[reason]
		)
	# A full host answers a joiner nothing: the join times out as host_unreachable, so its words
	# name both the full lobby and the unreachable host, and the fallback.
	var unreachable := EndReasons.words(NetTransport.JOIN_UNREACHABLE)
	for part: String in ["full", "could not reach the host directly", "playit.gg", "Direct"]:
		assert_str(unreachable).contains(part)
