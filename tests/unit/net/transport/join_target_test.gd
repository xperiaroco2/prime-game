extends GdUnitTestSuite
## JoinTarget (net/transport/join_target.gd; the M6 design §2.3, E51): what a player typed, a
## room's code or a host's address[:port], and the transport each makes.


func test_a_code_is_read_in_any_case_with_spaces_and_dashes() -> void:
	for typed: String in ["K7M2QX", "k7m2qx", " k7m-2qx ", "K7M 2QX"]:
		var target := JoinTarget.of_code(typed, "wss://service.example/")
		assert_str(target.problem).override_failure_message(typed).is_empty()
		assert_bool(target.is_code()).is_true()
		assert_str(target.code).is_equal("K7M2QX")
		assert_str(target.label()).is_equal("K7M2QX")
		assert_str(target.join_address()).is_equal("K7M2QX")


func test_a_wrong_code_says_why() -> void:
	assert_str(JoinTarget.of_code("  ", "x").problem).contains("type the code")
	for typed: String in ["K7M2Q", "K7M2QXX", "K7M2Q0", "K7M2QI", "K7M2QL", "K7M2Q1", "K7M2QO"]:
		assert_str(JoinTarget.of_code(typed, "x").problem).override_failure_message(typed).contains(
			"without 0, O, 1, I or L"
		)


func test_an_address_with_and_without_a_port() -> void:
	var plain := JoinTarget.of_direct("192.168.0.195", 24600)
	assert_str(plain.problem).is_empty()
	assert_bool(plain.is_code()).is_false()
	assert_str(plain.address).is_equal("192.168.0.195")
	assert_int(plain.port).is_equal(24600)
	assert_str(plain.label()).is_equal("192.168.0.195:24600")
	var ported := JoinTarget.of_direct(" example.playit.gg:41234 ", 24600)
	assert_str(ported.problem).is_empty()
	assert_str(ported.address).is_equal("example.playit.gg")
	assert_int(ported.port).is_equal(41234)
	var v6 := JoinTarget.of_direct("[::1]:7000", 24600)
	assert_str(v6.problem).is_empty()
	assert_str(v6.address).is_equal("::1")
	assert_int(v6.port).is_equal(7000)
	assert_str(v6.label()).is_equal("[::1]:7000")
	var bare_v6 := JoinTarget.of_direct("fe80::1", 24600)
	assert_str(bare_v6.problem).is_empty()
	assert_str(bare_v6.address).is_equal("fe80::1")
	assert_int(bare_v6.port).is_equal(24600)


func test_a_wrong_address_says_why() -> void:
	assert_str(JoinTarget.of_direct("", 1).problem).contains("type the host's address")
	assert_str(JoinTarget.of_direct("host:0", 1).problem).contains("1 to 65535")
	assert_str(JoinTarget.of_direct("host:70000", 1).problem).contains("1 to 65535")
	assert_str(JoinTarget.of_direct("host:abc", 1).problem).contains("1 to 65535")
	assert_str(JoinTarget.of_direct("[::1", 1).problem).contains("closing ]")
	assert_str(JoinTarget.of_direct("[::1]x", 1).problem).contains(":port")
	assert_str(JoinTarget.of_direct("bad host!", 1).problem).contains("neither an address")


func test_the_command_line_reads_a_code_or_an_address() -> void:
	var code := JoinTarget.parse("k7m2qx", 24600, "ws://127.0.0.1:9")
	assert_bool(code.is_code()).is_true()
	assert_str(code.service_url).is_equal("ws://127.0.0.1:9")
	var address := JoinTarget.parse("127.0.0.1", 24600)
	assert_bool(address.is_code()).is_false()
	# A host name that reads as a code is forced to an address by its port.
	var named := JoinTarget.parse("server:24600", 1)
	assert_bool(named.is_code()).is_false()
	assert_str(named.address).is_equal("server")


func test_each_target_makes_its_transport() -> void:
	var kinds := NetKindTable.game()
	var code := JoinTarget.of_code("K7M2QX", "ws://127.0.0.1:9").transport(kinds)
	assert_object(code).is_instanceof(WebRtcTransport)
	assert_str((code as WebRtcTransport).signal_url).is_equal("ws://127.0.0.1:9")
	assert_bool((code as WebRtcTransport).local_candidates).is_true()
	var remote := JoinTarget.of_code("K7M2QX", "wss://service.example/").transport(kinds)
	assert_bool((remote as WebRtcTransport).local_candidates).is_false()
	var direct := JoinTarget.of_direct("127.0.0.1", 9).transport(kinds)
	assert_object(direct).is_instanceof(EnetTransport)
	code.close()
	remote.close()
	direct.close()
