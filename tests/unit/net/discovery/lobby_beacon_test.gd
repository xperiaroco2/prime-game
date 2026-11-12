extends GdUnitTestSuite
## The lobbies nearby's datagrams (#1316, LobbyBeacon, ARCHITECTURE §4.9): a query and an answer
## round-trip, and the decoder refuses everything else cleanly (truncations, single-byte changes,
## random bytes, names over their caps or not wire names, codes off the alphabet).

const SEED := 1316


func _answer() -> LobbyBeacon.Answer:
	var answer := LobbyBeacon.Answer.new()
	answer.query = 77
	answer.host = 123456
	answer.protocol = WireSchema.VERSION
	answer.port = 24600
	answer.players = 6
	answer.most = 10
	answer.lobby_name = "Ґлорпова хата"
	answer.host_name = "Ґлорп"
	answer.code = ""
	return answer


func test_a_query_round_trips() -> void:
	var bytes := LobbyBeacon.query(4242)
	assert_int(bytes.size()).is_equal(LobbyBeacon.QUERY_SIZE)
	assert_int(LobbyBeacon.query_number(bytes)).is_equal(4242)
	# An answer is no query, and a query no answer.
	assert_int(LobbyBeacon.query_number(LobbyBeacon.answer(_answer()))).is_equal(-1)
	assert_object(LobbyBeacon.read_answer(bytes)).is_null()


func test_an_answer_round_trips_with_and_without_a_code() -> void:
	for code: String in ["", "K7Q2XR"]:
		var sent := _answer()
		sent.code = code
		sent.port = 0 if not code.is_empty() else 24600
		var got := LobbyBeacon.read_answer(LobbyBeacon.answer(sent))
		assert_object(got).is_not_null()
		assert_int(got.query).is_equal(sent.query)
		assert_int(got.host).is_equal(sent.host)
		assert_int(got.protocol).is_equal(sent.protocol)
		assert_int(got.port).is_equal(sent.port)
		assert_int(got.players).is_equal(6)
		assert_int(got.most).is_equal(10)
		assert_str(got.lobby_name).is_equal(sent.lobby_name)
		assert_str(got.host_name).is_equal(sent.host_name)
		assert_str(got.code).is_equal(code)
		assert_bool(got.has_room()).is_true()


func test_names_at_their_caps_fit_and_the_caps_are_cores() -> void:
	assert_int(LobbyBeacon.LOBBY_CHARS).is_equal(LobbyName.MAX_CHARS)
	assert_int(LobbyBeacon.HOST_CHARS).is_equal(PlayerNames.MAX_CHARS)
	var sent := _answer()
	sent.lobby_name = "𝔊".repeat(LobbyBeacon.LOBBY_CHARS)
	sent.host_name = "𝔊".repeat(LobbyBeacon.HOST_CHARS)
	sent.code = "K7Q2XR"
	var bytes := LobbyBeacon.answer(sent)
	assert_int(bytes.size()).is_less_equal(LobbyBeacon.ANSWER_MAX)
	var got := LobbyBeacon.read_answer(bytes)
	assert_str(got.lobby_name).is_equal(sent.lobby_name)
	# The encoder refuses what the decoder would (net/CLAUDE.md): a name over its cap or not a
	# wire name, a code off the alphabet, more players than the most, a most of 0, a port too big.
	assert_str(LobbyBeacon.answer_problem(sent)).is_empty()
	var refused: Array[LobbyBeacon.Answer] = []
	for i: int in 6:
		refused.append(_answer())
	refused[0].lobby_name = "x".repeat(LobbyBeacon.LOBBY_CHARS + 1)
	refused[1].host_name = "a" + char(0x200B) + "b"
	refused[2].code = "K7Q2XO"
	refused[3].players = 11
	refused[4].most = 0
	refused[4].players = 0
	refused[5].port = 0x10000
	for each: LobbyBeacon.Answer in refused:
		assert_str(LobbyBeacon.answer_problem(each)).is_not_empty()


func test_a_full_lobby_has_no_room() -> void:
	var sent := _answer()
	sent.players = 10
	assert_bool(LobbyBeacon.read_answer(LobbyBeacon.answer(sent)).has_room()).is_false()


func test_the_decoder_refuses_what_is_not_an_answer() -> void:
	var good := LobbyBeacon.answer(_answer())
	# Every truncation, and one byte more.
	for size: int in good.size():
		assert_object(LobbyBeacon.read_answer(good.slice(0, size))).is_null()
	var longer := good.duplicate()
	longer.append(0)
	assert_object(LobbyBeacon.read_answer(longer)).is_null()
	# The magic, the version, the kind.
	for at: int in [0, 4, 5]:
		var changed := good.duplicate()
		changed[at] = changed[at] ^ 0xFF
		assert_object(LobbyBeacon.read_answer(changed)).is_null()
	# More players than the most, and a most of 0 (the players byte at 18, the most at 19).
	var crowded := good.duplicate()
	crowded[18] = 11
	assert_object(LobbyBeacon.read_answer(crowded)).is_null()
	var empty := good.duplicate()
	empty[18] = 0
	empty[19] = 0
	assert_object(LobbyBeacon.read_answer(empty)).is_null()


func test_a_name_that_is_no_wire_name_or_a_code_off_the_alphabet_is_refused() -> void:
	var sent := _answer()
	sent.lobby_name = "ab"
	sent.code = "K7Q2XR"
	var good := LobbyBeacon.answer(sent)
	var name_at := 20 + 1
	# "ab" -> a lone continuation byte, then a C0 control.
	for bad: int in [0x80, 0x01]:
		var changed := good.duplicate()
		changed[name_at] = bad
		assert_object(LobbyBeacon.read_answer(changed)).is_null()
	# The code's last character an O (not in the alphabet), then a NUL.
	for bad: int in [0x4F, 0x00]:
		var changed := good.duplicate()
		changed[changed.size() - 1] = bad
		assert_object(LobbyBeacon.read_answer(changed)).is_null()


func test_random_bytes_and_single_byte_changes_decode_cleanly() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	var good := LobbyBeacon.answer(_answer())
	for i: int in 500:
		var changed := good.duplicate()
		changed[random.randi_range(0, changed.size() - 1)] = random.randi_range(0, 255)
		var got := LobbyBeacon.read_answer(changed)
		if got != null:
			assert_bool(got.players <= got.most).is_true()
		var noise := PackedByteArray()
		noise.resize(random.randi_range(0, LobbyBeacon.ANSWER_MAX + 8))
		for at: int in noise.size():
			noise[at] = random.randi_range(0, 255)
		LobbyBeacon.read_answer(noise)
		LobbyBeacon.query_number(noise)
