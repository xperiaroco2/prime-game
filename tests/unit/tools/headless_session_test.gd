extends GdUnitTestSuite
## The host and join launcher (tools/run/headless_session.gd, 3i): the roster line it prints, the
## reasons a join ends with and its exit codes. Its arguments are LaunchOptions'
## (tests/unit/client/app/launch_options_test.gd). The runs themselves:
## tools/runner/tests/test_hostjoin.py.

const Launcher := preload("res://tools/run/headless_session.gd")


func test_the_roster_line_lists_the_players_by_name_with_their_peer_and_ready_flag() -> void:
	var model := ClientModel.new(GameMode.new())
	assert_str(Launcher.roster_text(model)).is_equal(Launcher.NOBODY)
	for entry: Array in [[70, "Player10", false], [1, "Player1", true], [5, "Player2", false]]:
		var member := ClientModel.Member.new()
		member.name = entry[1]
		member.ready = entry[2]
		model.roster[entry[0] as int] = member
	assert_str(Launcher.roster_text(model)).is_equal(
		"Player1 [1] ready, Player2 [5], Player10 [70]"
	)


func test_a_refused_join_says_why_in_words() -> void:
	for reason: StringName in [&"wrong_version", &"wrong_content", &"joins_closed", &"full"]:
		var text := Launcher.ended_text(reason)
		assert_str(text).starts_with(String(reason) + " (")
		assert_str(text).is_equal("%s (%s)" % [reason, EndReasons.WORDS[reason]])
	assert_str(Launcher.ended_text(ClientSession.CONNECT_FAILED)).contains("firewall")
	assert_str(Launcher.ended_text(ClientSession.HOST_LOST)).contains("host closed")
	assert_str(Launcher.ended_text(&"unknown_map")).starts_with("unknown_map (")
	assert_str(Launcher.ended_text(&"load_deadline")).contains("too long to load")
	assert_str(Launcher.ended_text(&"no_such_reason")).is_equal("no_such_reason")


func test_the_exit_code_fails_a_client_that_never_got_in_or_ended_for_an_error() -> void:
	const YES := Launcher.EXIT_OK
	const NO := Launcher.EXIT_FAILED
	const STOP := Launcher.STOPPED
	# [hosting, welcomed, reason, exit code, how the last line starts]
	var cases: Array[Array] = [
		[true, true, STOP, YES, "stopped"],
		[true, false, STOP, YES, "stopped"],
		[false, true, STOP, YES, "stopped"],
		[false, false, STOP, NO, "stopped before the host welcomed it"],
		[false, true, ClientSession.HOST_LOST, YES, "the session ended: host_lost"],
		[false, true, ClientSession.LEFT, YES, "the session ended: left"],
		[false, true, ClientSession.LOAD_FAILED, NO, "the session ended: load_failed"],
		[false, true, ClientSession.UNKNOWN_MAP, NO, "the session ended: unknown_map"],
		[false, false, &"full", NO, "could not join: full ("],
		[false, false, ClientSession.CONNECT_FAILED, NO, "could not join: connect_failed"],
		[true, true, ClientSession.LOAD_FAILED, NO, "the host's own client ended"],
	]
	for entry in cases:
		var hosting: bool = entry[0]
		var welcomed: bool = entry[1]
		var reason: StringName = entry[2]
		var code := Launcher.exit_code(hosting, welcomed, reason)
		assert_int(code).override_failure_message("%s" % [entry]).is_equal(entry[3] as int)
		assert_str(Launcher.end_text(hosting, welcomed, reason)).starts_with(entry[4] as String)
