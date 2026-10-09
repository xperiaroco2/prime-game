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


func test_the_version_lines_name_the_hosts_then_the_own_only_for_found_s_mismatch() -> void:
	# #494's fail-version: "<protocol> (<first six hex digits of the content hash>)".
	var own := SignalCodec.content_text(2).left(6)
	var host := SignalCodec.content_text(1).left(6)
	assert_array(P.found_versions(&"wrong_version", 6, 2, 7, 2)).is_equal(
		PackedStringArray(["6 (%s)" % own, "7 (%s)" % own])
	)
	assert_array(P.found_versions(&"wrong_content", 7, 1, 7, 2)).is_equal(
		PackedStringArray(["7 (%s)" % host, "7 (%s)" % own])
	)
	# Not found's own mismatch (a Rejected Hello, no found yet, another reason): no lines.
	assert_array(P.found_versions(&"wrong_content", 6, 1, 7, 2)).is_empty()
	assert_array(P.found_versions(&"wrong_version", -1, 0, 7, 2)).is_empty()
	assert_array(P.found_versions(&"full", 7, 1, 7, 2)).is_empty()
	assert_array(P.found_versions(&"", 7, 2, 7, 2)).is_empty()
	assert_str(P.version_text(12, 0)).is_equal("12 (000000)")


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
	assert_str(P.CODE_GONE).contains("Host Direct")
	assert_str(P.code_text("", false, true)).is_equal(P.CODE_WAITING)


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


func test_a_join_with_no_service_found_names_no_versions() -> void:
	# A host's own end, a Direct join (ENet) and no transport have no `found`: nothing to add.
	var kinds := WireSchema.game(OS.is_debug_build()).kind_table()
	var transports: Array[NetTransport] = [
		null, EnetTransport.new(kinds), LoopbackTransport.new(kinds)
	]
	for transport: NetTransport in transports:
		assert_str(JoinProgress.detail_of(&"wrong_version", transport, 7)).is_empty()
		assert_array(JoinProgress.versions_of(&"wrong_version", transport, 7)).is_empty()
