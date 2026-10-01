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


func test_the_runners_files() -> void:
	var options := LaunchOptions.parse(PackedStringArray(["--host"]))
	assert_bool(options.stop_requested()).is_false()
	assert_bool(options.runner_gone()).is_false()
	var missing := LaunchOptions.parse(
		PackedStringArray(["--host", "--stop-file=user://no_such_stop", "--alive-file=user://none"])
	)
	assert_bool(missing.stop_requested()).is_false()
	assert_bool(missing.runner_gone()).is_true()
