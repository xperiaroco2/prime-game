extends GdUnitTestSuite
## SignalCodec (ARCHITECTURE §4.8): every type round-trips on its side, a type of another side is
## "not allowed", fields are checked and rebuilt, codes use the 31 characters that cannot be
## misread, and any "v" but 1 is "update the game".

const Samples := preload("res://tests/unit/net/signal/signal_samples.gd")
const Transcripts := preload("res://tests/unit/net/signal/signal_transcripts.gd")


func test_every_sample_round_trips() -> void:
	for sample: Array in Samples.all():
		var side: int = sample[0]
		var type: String = sample[1]
		var fields: Dictionary = sample[2]
		var text := SignalCodec.encode(side, type, fields)
		var decoded := SignalCodec.decode(text.to_ascii_buffer(), side)
		assert_str(decoded.why).override_failure_message(text).is_equal("")
		assert_str(decoded.type).is_equal(type)
		var expected: Dictionary = {"t": type, "v": 1}
		expected.merge(fields)
		var got := SignalCodec.as_message(decoded)
		assert_str(Transcripts.canonical(got)).is_equal(Transcripts.canonical(expected))


func test_a_type_of_another_side_is_not_allowed() -> void:
	var offer := '{"t": "offer", "v": 1, "to": 2, "id": 2, "sdp": "x"}'.to_ascii_buffer()
	assert_str(SignalCodec.decode(offer, SignalCodec.Side.JOINER).why).is_equal(
		SignalCodec.WHY_NOT_ALLOWED
	)
	assert_str(SignalCodec.decode(offer, SignalCodec.Side.UNSET).why).is_equal(
		SignalCodec.WHY_NOT_ALLOWED
	)
	assert_bool(SignalCodec.decode(offer, SignalCodec.Side.HOST).ok()).is_true()
	var close := '{"t": "close", "v": 1}'.to_ascii_buffer()
	assert_str(SignalCodec.decode(close, SignalCodec.Side.JOINER).why).is_equal(
		SignalCodec.WHY_NOT_ALLOWED
	)


func test_an_unknown_type_is_a_bad_message() -> void:
	var text := '{"t": "teleport", "v": 1}'.to_ascii_buffer()
	assert_str(SignalCodec.decode(text, SignalCodec.Side.HOST).why).is_equal(SignalCodec.WHY_BAD)


func test_any_version_but_1_is_update_the_game() -> void:
	for version: String in ['"v": 2', '"v": 0', '"v": "1"', '"v": 1.5', '"v": null', '"x": 1']:
		var text := ('{"t": "join", %s, "code": "ABCDEF"}' % version).to_ascii_buffer()
		assert_str(SignalCodec.decode(text, SignalCodec.Side.UNSET).why).is_equal(
			SignalCodec.WHY_VERSION
		)
	var one := '{"t": "join", "v": 1.0, "code": "ABCDEF"}'.to_ascii_buffer()
	assert_bool(SignalCodec.decode(one, SignalCodec.Side.UNSET).ok()).is_true()


func test_unknown_fields_are_dropped() -> void:
	var text := '{"t": "candidate", "v": 1, "to": 2, "mid": "0", "index": 0, "cand": "c", "x": 1}'
	var decoded := SignalCodec.decode(text.to_ascii_buffer(), SignalCodec.Side.JOINER)
	assert_bool(decoded.ok()).is_true()
	assert_array(decoded.fields.keys()).contains_exactly_in_any_order(["mid", "index", "cand"])


func test_ice_servers_are_rebuilt_from_known_keys() -> void:
	var text := (
		'{"t": "room", "v": 1, "code": "ABCDEF", "ice_servers": [{"urls": ["stun:a:1"],'
		+ ' "username": "u", "extra": "x"}]}'
	)
	var decoded := SignalCodec.decode(text.to_ascii_buffer(), SignalCodec.Side.TO_HOST)
	assert_bool(decoded.ok()).is_true()
	assert_str(Transcripts.canonical(decoded.fields["ice_servers"])).is_equal(
		Transcripts.canonical([{"urls": ["stun:a:1"], "username": "u"}])
	)
	for bad: String in [
		'[{"urls": ["http://a"]}]', '[{"urls": []}]', '[{"urls": "stun:a"}]', "[1]"
	]:
		var refused := '{"t": "room", "v": 1, "code": "ABCDEF", "ice_servers": %s}' % bad
		(
			assert_str(SignalCodec.decode(refused.to_ascii_buffer(), SignalCodec.Side.TO_HOST).why)
			. is_equal(SignalCodec.WHY_BAD)
		)


func test_integers_have_no_fraction_and_stay_in_range() -> void:
	for to: String in ["1.5", "0", "-1", "2147483648", "1e400", '"1"', "true", "null"]:
		var text := '{"t": "offer", "v": 1, "to": %s, "id": 2, "sdp": "x"}' % to
		assert_str(SignalCodec.decode(text.to_ascii_buffer(), SignalCodec.Side.HOST).why).is_equal(
			SignalCodec.WHY_BAD
		)


func test_text_fields_are_printable_ascii() -> void:
	for cand: String in ['"a\\u00e9"', '"a\\u0000"', '"a\\nb"']:
		var text := '{"t": "candidate", "v": 1, "mid": "0", "index": 0, "cand": %s}' % cand
		(
			assert_str(SignalCodec.decode(text.to_ascii_buffer(), SignalCodec.Side.JOINER).why)
			. is_equal(SignalCodec.WHY_BAD)
		)
	var raw := PackedByteArray([0x7B, 0xC3, 0xA9, 0x7D])
	assert_str(SignalCodec.decode(raw, SignalCodec.Side.JOINER).why).is_equal(SignalCodec.WHY_BAD)


func test_codes_use_31_characters_that_cannot_be_misread() -> void:
	assert_int(SignalCodec.CODE_ALPHABET.length()).is_equal(31)
	for misread: String in ["0", "O", "1", "I", "L"]:
		assert_bool(SignalCodec.CODE_ALPHABET.contains(misread)).is_false()
	var random := RandomNumberGenerator.new()
	random.seed = 366
	var seen := {}
	for i: int in 2000:
		var code := SignalCodec.random_code(random)
		assert_bool(SignalCodec.is_code(code)).is_true()
		for character: String in code:
			seen[character] = true
	assert_int(seen.size()).is_equal(31)
	for bad: String in ["ABCDE", "ABCDEFG", "abcdef", "ABCDE0", "ABCDEO"]:
		assert_bool(SignalCodec.is_code(bad)).is_false()


func test_the_content_hash_travels_as_16_hex_digits() -> void:
	for fingerprint: int in [0, 1, -1, -9223372036854775808, 9223372036854775807, 0x1234abcd]:
		var text := SignalCodec.content_text(fingerprint)
		assert_int(text.length()).is_equal(16)
		assert_int(SignalCodec.content_hash(text)).is_equal(fingerprint)
		var open := {"protocol": 7, "content": text, "max": 9}
		assert_str(SignalCodec.encode(SignalCodec.Side.UNSET, "open", open)).is_not_empty()


func test_the_size_cap_counts_bytes() -> void:
	var text := '{"t": "answer", "v": 1, "sdp": "x"}'
	var at_cap := (
		(text + " ".repeat(SignalCodec.MAX_MESSAGE_BYTES - text.length())).to_ascii_buffer()
	)
	assert_bool(SignalCodec.decode(at_cap, SignalCodec.Side.JOINER).ok()).is_true()
	at_cap.append(0x20)
	assert_str(SignalCodec.decode(at_cap, SignalCodec.Side.JOINER).why).is_equal(
		SignalCodec.WHY_TOO_LARGE
	)


## The decoding cases recorded from Godot (tests/fixtures/signal/decode/), which the Worker's codec
## replays too (tools/signal/test/codec.test.js): a change to the rules shows in both.
func test_every_decoding_case_gives_its_recorded_result() -> void:
	var json := JSON.new()
	var path := Transcripts.FOLDER + "decode/decode_cases.json"
	assert_int(json.parse(FileAccess.get_file_as_string(path))).is_equal(OK)
	var data: Dictionary = json.data
	var cases: Array = data["cases"]
	assert_int(cases.size()).is_greater(100)
	var sides := {
		"UNSET": SignalCodec.Side.UNSET,
		"HOST": SignalCodec.Side.HOST,
		"JOINER": SignalCodec.Side.JOINER,
		"TO_HOST": SignalCodec.Side.TO_HOST,
		"TO_JOINER": SignalCodec.Side.TO_JOINER,
	}
	var failures := PackedStringArray()
	for index: int in cases.size():
		var each: Dictionary = cases[index]
		var text: String = each["raw"]
		if each.has("pad_to"):
			var pad_to: float = each["pad_to"]
			text += " ".repeat(int(pad_to) - text.length())
		var side: int = sides[each["side"]]
		var decoded := SignalCodec.decode(text.to_ascii_buffer(), side)
		var got := {"why": decoded.why}
		if decoded.ok():
			got = {"msg": SignalCodec.as_message(decoded)}
		if Transcripts.canonical(got) != Transcripts.canonical(each["expect"]):
			failures.append("case %d: got %s" % [index, Transcripts.canonical(got)])
	assert_array(Array(failures)).is_empty()
