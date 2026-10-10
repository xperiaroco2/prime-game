extends GdUnitTestSuite
## The launch options (client/app/launch_options.gd, ARCHITECTURE §4.7): --host [--local],
## --join=, --port= and the runner's files, read alike by the game and the headless session. The
## game alone may start with neither (its main menu).


func test_host_arguments() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--host", "--port=24999"]))
	assert_str(options.problem).is_empty()
	assert_bool(options.hosting).is_true()
	assert_int(options.port).is_equal(24999)
	assert_str(options.bind).is_equal(LaunchOptions.EVERY_INTERFACE)
	var local := LaunchOptions.parse(PackedStringArray(["--host", "--local", "--stop-file=x"]))
	assert_str(local.problem).is_empty()
	assert_str(local.bind).is_equal(LaunchOptions.LOCALHOST)
	assert_int(local.port).is_equal(LaunchOptions.DEFAULT_PORT)
	assert_str(local.stop_file).is_equal("x")
	assert_str(local.alive_file).is_empty()
	assert_bool(local.replay).is_true()
	var runner := LaunchOptions.parse(
		PackedStringArray(["--host", "--no-replay", "--alive-file=x.alive"])
	)
	assert_str(runner.problem).is_empty()
	assert_str(runner.alive_file).is_equal("x.alive")
	assert_bool(runner.replay).is_false()


func test_join_arguments() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--join=192.168.0.195"]))
	assert_str(options.problem).is_empty()
	assert_bool(options.hosting).is_false()
	assert_str(options.address).is_equal("192.168.0.195")
	assert_int(options.port).is_equal(LaunchOptions.DEFAULT_PORT)


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
		assert_str(LaunchOptions.parse(cases[expected]).problem).contains(expected)


func test_the_game_may_start_with_neither_but_the_headless_session_may_not() -> void:
	var menu := LaunchOptions.parse(PackedStringArray([]), true)
	assert_str(menu.problem).is_empty()
	assert_bool(menu.hosting or menu.joining).is_false()
	assert_str(LaunchOptions.parse(PackedStringArray([])).problem).contains("either")
	var both := LaunchOptions.parse(PackedStringArray(["--host", "--join=1.2.3.4"]), true)
	assert_str(both.problem).contains("not both")


func test_tutorial_arguments_and_whether_any_was_given() -> void:
	# #601: --tutorial is the game window's alone, and any argument keeps the first launch's
	# tutorial off (E70), a wrong one too.
	var tutorial := LaunchOptions.parse(PackedStringArray(["--tutorial", "--stop-file=x"]), true)
	assert_str(tutorial.problem).is_empty()
	assert_bool(tutorial.tutorial).is_true()
	assert_bool(tutorial.given).is_true()
	assert_bool(tutorial.hosting or tutorial.joining).is_false()
	var none := LaunchOptions.parse(PackedStringArray([]), true)
	assert_bool(none.given or none.tutorial).is_false()
	assert_bool(LaunchOptions.parse(PackedStringArray(["--port=24999"]), true).given).is_true()
	assert_bool(LaunchOptions.parse(PackedStringArray(["--nonsense"]), true).given).is_true()
	var cases: Dictionary[String, PackedStringArray] = {
		"give either --tutorial": PackedStringArray(["--tutorial", "--host"]),
		"not both": PackedStringArray(["--tutorial", "--join=1.2.3.4"]),
		"for the host only": PackedStringArray(["--tutorial", "--local"]),
		"--code and --room= are for the host only": PackedStringArray(["--tutorial", "--code"]),
	}
	for expected: String in cases:
		var options := LaunchOptions.parse(cases[expected], true)
		assert_str(options.problem).override_failure_message(expected).contains(expected)
	var headless := LaunchOptions.parse(PackedStringArray(["--tutorial"]))
	assert_str(headless.problem).contains("not the headless session")


func test_the_runners_files() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--host"]))
	assert_bool(options.stop_requested()).is_false()
	assert_bool(options.runner_gone()).is_false()
	var missing := LaunchOptions.parse(
		PackedStringArray(["--host", "--stop-file=user://no_such_stop", "--alive-file=user://none"])
	)
	assert_bool(missing.stop_requested()).is_false()
	assert_bool(missing.runner_gone()).is_true()


func test_code_arguments() -> void:
	var host := LaunchOptions.parse(
		PackedStringArray(["--host", "--code", "--signal=lan", "--room=k7m2qx"])
	)
	assert_str(host.problem).is_empty()
	assert_bool(host.by_code).is_true()
	assert_str(host.signal_url).is_equal(LaunchOptions.LAN_SIGNAL)
	assert_str(host.room).is_equal("K7M2QX")
	var joiner := LaunchOptions.parse(
		PackedStringArray(["--join=K7M2QX", "--signal=ws://127.0.0.1:24600"])
	)
	assert_str(joiner.problem).is_empty()
	assert_bool(joiner.target.is_code()).is_true()
	assert_str(joiner.target.service_url).is_equal("ws://127.0.0.1:24600")
	# No --signal: the deployed Worker (#513).
	var deployed := LaunchOptions.parse(PackedStringArray(["--join=K7M2QX"]))
	assert_str(deployed.problem).is_empty()
	assert_str(deployed.target.service_url).starts_with("wss://")
	assert_str(deployed.target.service_url).is_equal(JoinTarget.SERVICE_URL)
	var direct := LaunchOptions.parse(PackedStringArray(["--join=example.playit.gg:41234"]))
	assert_str(direct.problem).is_empty()
	assert_bool(direct.target.is_code()).is_false()
	assert_int(direct.target.port).is_equal(41234)
	var cases: Dictionary[String, PackedStringArray] = {
		"for the host only": PackedStringArray(["--join=K7M2QX", "--code"]),
		"takes a code": PackedStringArray(["--host", "--code", "--room=K7M2QX"]),
		"1 to 65535": PackedStringArray(["--join=host:0"]),
		"for a --code host only": PackedStringArray(["--join=K7M2QX", "--signal=lan"]),
	}
	for expected: String in cases:
		var options := LaunchOptions.parse(cases[expected])
		assert_str(options.problem).override_failure_message(expected).contains(expected)
