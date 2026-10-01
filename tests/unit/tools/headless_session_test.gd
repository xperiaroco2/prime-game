extends GdUnitTestSuite
## The host and join launcher (tools/run/headless_session.gd, 3i): its arguments, the roster line
## it prints and the reasons a join ends with. The runs themselves:
## tools/runner/tests/test_hostjoin.py.

const Launcher := preload("res://tools/run/headless_session.gd")


func test_host_arguments() -> void:
	var options := Launcher.Options.parse(PackedStringArray(["--host", "--port=24999"]))
	assert_str(options.problem).is_empty()
	assert_bool(options.hosting).is_true()
	assert_int(options.port).is_equal(24999)
	assert_str(options.bind).is_equal(Launcher.EVERY_INTERFACE)
	var local := Launcher.Options.parse(PackedStringArray(["--host", "--local", "--stop-file=x"]))
	assert_str(local.problem).is_empty()
	assert_str(local.bind).is_equal(Launcher.LOCALHOST)
	assert_int(local.port).is_equal(Launcher.DEFAULT_PORT)
	assert_str(local.stop_file).is_equal("x")
	assert_str(local.alive_file).is_empty()
	assert_bool(local.replay).is_true()
	var runner := Launcher.Options.parse(
		PackedStringArray(["--host", "--no-replay", "--alive-file=x.alive"])
	)
	assert_str(runner.problem).is_empty()
	assert_str(runner.alive_file).is_equal("x.alive")
	assert_bool(runner.replay).is_false()


func test_join_arguments() -> void:
	var options := Launcher.Options.parse(PackedStringArray(["--join=192.168.0.195"]))
	assert_str(options.problem).is_empty()
	assert_bool(options.hosting).is_false()
	assert_str(options.address).is_equal("192.168.0.195")
	assert_int(options.port).is_equal(Launcher.DEFAULT_PORT)


func test_wrong_arguments_say_what_is_wrong() -> void:
	var cases: Dictionary[String, PackedStringArray] = {
		"either": PackedStringArray([]),
		"either --host": PackedStringArray(["--host", "--join=1.2.3.4"]),
		"needs the host's address": PackedStringArray(["--join="]),
		"between 1 and 65535": PackedStringArray(["--host", "--port=70000"]),
		"between 1 and 65535, got 'x'": PackedStringArray(["--host", "--port=x"]),
		"for the host only": PackedStringArray(["--join=1.2.3.4", "--local"]),
		"unknown argument '--clients=2'": PackedStringArray(["--host", "--clients=2"]),
	}
	for expected: String in cases:
		assert_str(Launcher.Options.parse(cases[expected]).problem).contains(expected)


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
		assert_str(text).is_equal("%s (%s)" % [reason, Launcher.REFUSALS[reason]])
	assert_str(Launcher.ended_text(ClientSession.CONNECT_FAILED)).contains("firewall")
	assert_str(Launcher.ended_text(ClientSession.HOST_LOST)).contains("host closed")
	assert_str(Launcher.ended_text(&"unknown_map")).is_equal("unknown_map")


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
