extends GdUnitTestSuite
## WireSchema's encoder and decoder (ARCHITECTURE §4.4): a round trip of every row, the decoded
## shapes, what the encoder refuses and what the decoder rejects.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")
## A control character a name never holds.
const BELL := "\u0007"

var _schema: WireSchema
var _errors: EngineErrors


func before_test() -> void:
	_schema = WireSchema.game(true)
	_errors = EngineErrors.new()
	_errors.start()


func after_test() -> void:
	_errors.stop()


func test_every_sample_round_trips_with_its_variant_types() -> void:
	for message: WireMessage in Samples.all_messages():
		var payload := _schema.encode(message)
		assert_int(payload.size()).override_failure_message(str(message.name)).is_greater(0)
		var kind := _schema.kind_of(message.name)
		var decoded := _schema.decode(kind, payload)
		(
			assert_object(decoded)
			. override_failure_message("%s: %s" % [message.name, _schema.explain(kind, payload)])
			. is_not_null()
		)
		if decoded == null:
			continue
		assert_str(str(decoded.name)).is_equal(str(message.name))
		assert_int(decoded.kind).is_equal(kind)
		assert_int(decoded.seq).is_equal(message.seq)
		assert_int(decoded.peer).is_equal(message.peer)
		(
			assert_bool(Samples.same(decoded.fields, message.fields))
			. override_failure_message(
				"%s: %s decoded as %s" % [message.name, message.fields, decoded.fields]
			)
			. is_true()
		)
		assert_bool(decoded.fields == message.fields).is_true()
	assert_int(_errors.count()).is_equal(0)


func test_every_row_has_a_sample() -> void:
	var sampled := {}
	for message: WireMessage in Samples.all_messages():
		sampled[message.name] = true
	for each: WireRow in _schema.rows():
		assert_bool(sampled.has(each.name)).override_failure_message(str(each.name)).is_true()


func test_an_intent_decodes_to_its_command_args_and_seq() -> void:
	var decoded := _round_trip(WireMessage.new(&"PickUp", {"item": 4}, 77))
	assert_dict(decoded.fields).is_equal({"item": 4})
	assert_int(decoded.seq).is_equal(77)
	var claim := _round_trip(WireMessage.new(&"MoveClaim", Samples._claim()))
	assert_bool(claim.fields["sprint"]).is_true()
	assert_bool(claim.fields["moving"]).is_false()
	assert_bool(claim.fields["on_floor"]).is_true()
	assert_int(claim.seq).is_equal(0)


func test_change_settings_holds_a_map_only_when_it_names_one() -> void:
	var without := _round_trip(WireMessage.new(&"ChangeSettings", {"settings": {&"tasks": 2}}, 1))
	assert_bool(without.fields.has("map")).is_false()
	var map := "res://levels/maps/test_map.tscn"
	var with_map := _round_trip(WireMessage.new(&"ChangeSettings", {"settings": {}, "map": map}, 1))
	assert_str(with_map.fields["map"] as String).is_equal(map)
	var sets: Variant = (
		_round_trip(WireMessage.new(&"ChangeSettings", {"settings": {"b": ["x"], "a": 5}}, 1))
		. fields["settings"]
	)
	assert_bool(Samples.same(sets, {&"a": 5, &"b": PackedStringArray(["x"])})).is_true()


func test_force_role_carries_the_player_as_the_peer_and_clears_with_an_empty_role() -> void:
	var forced := _round_trip(WireMessage.new(&"ForceRole", {"role": "crew"}, 5, 9))
	assert_int(forced.peer).is_equal(9)
	assert_int(forced.seq).is_equal(5)
	assert_bool(Samples.same(forced.fields, {"role": "crew"})).is_true()
	var cleared := WireMessage.new(&"ForceRole", {"role": &""}, 6, 9)
	var payload := _schema.encode(cleared)
	assert_int(payload.size()).is_equal(4 + 4 + 1)
	assert_bool(Samples.same(_schema.decode(24, payload).fields, {"role": ""})).is_true()


func test_item_spawned_holds_a_station_only_for_a_package() -> void:
	var knife := _round_trip(
		WireMessage.new(&"ItemSpawned", ItemSpawnedEvent.new(1, &"knife", Vector3.ONE).to_dict())
	)
	assert_array(knife.fields.keys()).contains_exactly_in_any_order(["item", "kind", "position"])
	var partial := {"item": 1, "kind": &"package", "position": Vector3.ONE, "station": 2}
	_assert_refused(WireMessage.new(&"ItemSpawned", partial))


func test_optional_ticks_and_items_are_minus_one_when_none() -> void:
	var phase := _round_trip(WireMessage.new(&"PhaseChanged", {"phase": &"end", "end_tick": -1}))
	assert_int(phase.fields["end_tick"] as int).is_equal(-1)
	var payload := _schema.encode(WireMessage.new(&"PhaseChanged", {"phase": &"a", "end_tick": -1}))
	assert_array(Array(payload.slice(2))).is_equal([0xFF, 0xFF, 0xFF, 0xFF])
	_assert_refused(WireMessage.new(&"RoundStarted", {"start_tick": -1}))
	_assert_refused(WireMessage.new(&"PickUp", {"item": -1}, 1))
	_assert_refused(WireMessage.new(&"PickUp", {"item": 0xFFFF}, 1))


func test_the_encoder_refuses_what_the_decoder_would_reject() -> void:
	_assert_refused(WireMessage.new(&"NoSuchRow", {}))
	_assert_refused(WireMessage.new(&"PlayerLeft", {}))
	_assert_refused(WireMessage.new(&"PlayerLeft", {"peer": 2, "extra": 1}))
	_assert_refused(WireMessage.new(&"PlayerLeft", {"peer": 0}))
	_assert_refused(WireMessage.new(&"PlayerLeft", {"peer": 0x80000000}))
	_assert_refused(WireMessage.new(&"PlayerLeft", {"peer": 2.0}))
	_assert_refused(WireMessage.new(&"SetReady", {"ready": 1}, 1))
	_assert_refused(WireMessage.new(&"SetReady", {"ready": true}, -1))
	_assert_refused(WireMessage.new(&"RoleAssigned", {"role": &"Crew"}))
	_assert_refused(WireMessage.new(&"RoleAssigned", {"role": &""}))
	_assert_refused(WireMessage.new(&"RoleAssigned", {"role": Samples.ID_32 + "x"}))
	_assert_refused(WireMessage.new(&"Swung", {"peer": 2, "facing": Vector3(NAN, 0, 0)}))
	_assert_refused(WireMessage.new(&"Swung", {"peer": 2, "facing": Vector3(INF, 0, 0)}))
	_assert_refused(WireMessage.new(&"Damaged", {"amount": 0x80000000, "health": 0}))
	_assert_refused(WireMessage.new(&"TaskProgress", {"done": 0x10000, "total": 1}))
	# A name (#550, #214) is UTF-8 of at most 80 bytes, not characters, and holds no control.
	for bad_name: String in ["x".repeat(WireField.NAME_MAX_BYTES + 1), "é".repeat(41), "a" + BELL]:
		_assert_refused(
			WireMessage.new(&"PlayerJoined", {"peer": 2, "name": bad_name, "spot": Vector3.ZERO})
		)
	_assert_refused(WireMessage.new(&"PlayerJoined", {"peer": 2, "name": 7, "spot": Vector3.ZERO}))
	_assert_refused(WireMessage.new(&"MoveClaim", _claim_with("sprint", 1)))
	_assert_refused(WireMessage.new(&"VoiceUp", {"seq": 1, "opus": PackedByteArray()}))
	var frame := PackedByteArray()
	frame.resize(WireSchema.MAX_OPUS + 1)
	_assert_refused(WireMessage.new(&"VoiceUp", {"seq": 1, "opus": frame}))
	# A VoiceBatch's frames (M5-4b): 1 to MAX_OPUS bytes each, at most MAX_BATCH_FRAMES, the cap.
	for opus: PackedByteArray in [PackedByteArray(), frame]:
		var one: Array[Dictionary] = [{"speaker": 2, "seq": 0, "opus": opus}]
		_assert_refused(WireMessage.new(&"VoiceBatch", {"tick": 1, "frames": one}))
	var many: Array[Dictionary] = []
	for i: int in WireSchema.MAX_BATCH_FRAMES + 1:
		many.append({"speaker": 2, "seq": i, "opus": PackedByteArray([1])})
	_assert_refused(WireMessage.new(&"VoiceBatch", {"tick": 1, "frames": many}))
	var big: Array[Dictionary] = []
	for i: int in 3:
		big.append({"speaker": 2, "seq": i, "opus": frame.slice(0, WireSchema.MAX_OPUS)})
	_assert_refused(WireMessage.new(&"VoiceBatch", {"tick": 1, "frames": big}))


func test_a_refusal_names_a_byte_array_by_its_size_and_cuts_a_long_value() -> void:
	var frame := PackedByteArray()
	frame.resize(WireSchema.MAX_OPUS + 1)
	var voice := _schema.write(WireMessage.new(&"VoiceUp", {"seq": 1, "opus": frame}))
	assert_str(voice.problem).is_equal("opus: %d bytes is not an opus" % frame.size())
	var role := _schema.write(WireMessage.new(&"RoleAssigned", {"role": &"Crew"}))
	assert_str(role.problem).is_equal('role: &"Crew" is not an id')
	var long_name := "x".repeat(WireField.NAME_MAX_BYTES + 1)
	var joined := _schema.write(
		WireMessage.new(&"PlayerJoined", {"peer": 2, "name": long_name, "spot": Vector3.ZERO})
	)
	assert_int(joined.problem.length()).is_less(100)
	assert_str(joined.problem).ends_with("... is not a name")


func test_the_encoder_refuses_bad_paths() -> void:
	for path: String in [
		"", "levels/a.tscn", "user://a.tscn", "res://../a.tscn", "res://a b.tscn", "res://a:b"
	]:
		_assert_refused(WireMessage.new(&"LoadMatch", {"match_id": 1, "map": path, "settings": {}}))
	var longest := "res://" + "a".repeat(WireField.PATH_MAX - 6)
	var fits := WireMessage.new(&"LoadMatch", {"match_id": 1, "map": longest, "settings": {}})
	assert_int(_schema.encode(fits).size()).is_equal(4 + 1 + 255 + 1)
	_assert_refused(
		WireMessage.new(&"LoadMatch", {"match_id": 1, "map": longest + "a", "settings": {}})
	)


func test_the_encoder_refuses_counts_over_their_maxima_and_payloads_over_the_cap() -> void:
	var peers := PackedInt32Array()
	for peer: int in range(1, WireSchema.MAX_PLAYERS + 2):
		peers.append(peer)
	_assert_refused(WireMessage.new(&"Teammates", {"role": &"dissident", "peers": peers}))
	peers.resize(WireSchema.MAX_PLAYERS)
	(
		assert_int(
			_schema.encode(WireMessage.new(&"Teammates", {"role": &"x", "peers": peers})).size()
		)
		. is_equal(2 + 1 + 64)
	)
	var notes := PackedStringArray()
	for i: int in WireSchema.MAX_SHORTFALLS:
		notes.append("n".repeat(WireField.NOTE_MAX))
	var fields := _settings_changed_fields()
	fields["shortfalls"] = notes
	var encoded := _schema.write(WireMessage.new(&"SettingsChanged", fields))
	assert_str(encoded.problem).contains("over its cap of 8192")
	_assert_refused(WireMessage.new(&"SettingsChanged", fields))


func test_map_keys_are_written_in_ascending_order() -> void:
	var spots: Dictionary[int, Vector3] = {300: Vector3.ZERO, 2: Vector3.ZERO, 17: Vector3.ZERO}
	var payload := _schema.encode(WireMessage.new(&"PlayersPlaced", {"spots": spots}))
	assert_int(payload.decode_u32(1)).is_equal(2)
	assert_int(payload.decode_u32(17)).is_equal(17)
	assert_int(payload.decode_u32(33)).is_equal(300)
	var numbers := {&"b": 1, &"a_b": 2, &"a": 3, &"a0": 4}
	var loaded := _schema.encode(
		WireMessage.new(&"LoadMatch", {"match_id": 1, "map": "res://m.tscn", "settings": numbers})
	)
	var reader := WireReader.new(loaded.slice(4 + 1 + 12 + 1))
	var order: Array[String] = []
	for i: int in 4:
		order.append(reader.raw(reader.u8()).get_string_from_ascii())
		reader.s32()
	assert_array(order).is_equal(["a", "a0", "a_b", "b"])


func test_the_decoder_rejects_broken_payloads() -> void:
	var ready_payload := _schema.encode(WireMessage.new(&"SetReady", {"ready": true}, 1))
	ready_payload[4] = 2
	_assert_rejected(2, ready_payload, "not a bool")
	var claim := _schema.encode(WireMessage.new(&"MoveClaim", Samples._claim()))
	claim[44] = 0x08
	_assert_rejected(5, claim, "unknown flag bits")
	var joined := _schema.encode(
		WireMessage.new(&"PlayerJoined", {"peer": 2, "name": "P", "spot": Vector3.ZERO})
	)
	joined[5] = 0x7F
	_assert_rejected(34, joined, "byte")
	var role := _schema.encode(WireMessage.new(&"RoleAssigned", {"role": &"crew"}))
	role[1] = 0x43  # "C"
	_assert_rejected(44, role, "not an id")
	var swung := _schema.encode(WireMessage.new(&"Swung", {"peer": 2, "facing": Vector3.ZERO}))
	swung.encode_float(4, NAN)
	_assert_rejected(52, swung, "not finite")
	var left := _schema.encode(WireMessage.new(&"PlayerLeft", {"peer": 2}))
	left.append(0)
	_assert_rejected(35, left, "after the last field")
	left.encode_u32(0, 0)
	_assert_rejected(35, left.slice(0, 4), "not a peer")
	_assert_rejected(200, PackedByteArray([1]), "no row")


func test_the_reader_fails_on_a_negative_length() -> void:
	var reader := WireReader.new(PackedByteArray([1, 2, 3]))
	assert_int(reader.raw(-1).size()).is_equal(0)
	assert_bool(reader.failed).is_true()
	assert_str(reader.problem).contains("negative length")
	assert_int(reader.u8()).is_equal(0)


func test_the_decoder_rejects_map_keys_out_of_order_or_repeated() -> void:
	var spots: Dictionary[int, Vector3] = {1: Vector3.ZERO, 2: Vector3.ONE}
	var payload := _schema.encode(WireMessage.new(&"PlayersPlaced", {"spots": spots}))
	var swapped := payload.duplicate()
	swapped.encode_u32(1, 2)
	swapped.encode_u32(17, 1)
	_assert_rejected(40, swapped, "out of order")
	var repeated := payload.duplicate()
	repeated.encode_u32(17, 1)
	_assert_rejected(40, repeated, "out of order")


func test_a_release_table_neither_encodes_nor_decodes_debug_commands() -> void:
	var release := WireSchema.game(false)
	var forced := WireMessage.new(&"ForceRole", {"role": "crew"}, 1, 2)
	assert_str(release.write(forced).problem).contains("no row")
	assert_object(release.decode(24, _schema.encode(forced))).is_null()


## A name (#550) round-trips as UTF-8: empty, ASCII, Cyrillic, four-byte characters, 80 bytes.
func test_a_name_round_trips_in_utf8() -> void:
	var emoji := String.chr(0x1F600)
	for each: String in [
		"", "Dima", "Діма 2", emoji.repeat(20), "é".repeat(40), "x".repeat(WireField.NAME_MAX_BYTES)
	]:
		var hello := {"version": WireSchema.VERSION, "content": 1, "name": each}
		var decoded := _round_trip(WireMessage.new(&"Hello", hello))
		if decoded != null:
			assert_str(decoded.fields["name"]).is_equal(each)
	assert_array(Array(_errors.snapshot())).is_empty()


## The lobby's name (#214) is the `name` type on ChangeSettings (behind its flag, absent when not
## sent), Welcome and SettingsChanged: 20 four-byte characters fit, one byte more or a control
## does not.
func test_the_lobby_name_is_a_name_on_three_rows() -> void:
	var widest := String.chr(0x1F600).repeat(20)
	var sent := WireMessage.new(&"ChangeSettings", {"settings": {}, "lobby_name": widest}, 3)
	assert_str(_round_trip(sent).fields["lobby_name"]).is_equal(widest)
	var without := _round_trip(WireMessage.new(&"ChangeSettings", {"settings": {}}, 4))
	assert_bool(without.fields.has("lobby_name")).is_false()
	var changed := _settings_changed_fields()
	changed["lobby_name"] = widest
	var decoded := _round_trip(WireMessage.new(&"SettingsChanged", changed))
	assert_str(decoded.fields["lobby_name"]).is_equal(widest)
	for bad: String in ["é".repeat(41), "Den" + BELL, "x".repeat(WireField.NAME_MAX_BYTES + 1)]:
		_assert_refused(WireMessage.new(&"ChangeSettings", {"settings": {}, "lobby_name": bad}, 5))
		changed["lobby_name"] = bad
		_assert_refused(WireMessage.new(&"SettingsChanged", changed))
	assert_array(Array(_errors.snapshot())).is_empty()


## The decoder checks a name's bytes by hand before any decode: malformed UTF-8 is a clean reject,
## with no engine error a peer could repeat (get_string_from_utf8 prints one), and so are the
## characters a name never holds.
func test_a_malformed_name_is_rejected_without_an_engine_error() -> void:
	var bad: Array[PackedByteArray] = [
		PackedByteArray([0xC3]),  # a lead byte without its continuation
		PackedByteArray([0x41, 0xE2, 0x82]),  # cut short
		PackedByteArray([0x80]),  # a continuation byte alone
		PackedByteArray([0xC3, 0x41]),  # a lead byte followed by no continuation
		PackedByteArray([0xC0, 0x80]),  # overlong NUL
		PackedByteArray([0xE0, 0x80, 0x80]),  # overlong
		PackedByteArray([0xF0, 0x80, 0x80, 0x80]),  # overlong
		PackedByteArray([0xED, 0xA0, 0x80]),  # a surrogate
		PackedByteArray([0xF4, 0x90, 0x80, 0x80]),  # above U+10FFFF
		PackedByteArray([0xF8, 0x88, 0x80, 0x80, 0x80]),  # five bytes
		PackedByteArray([0xFF]),
		PackedByteArray([0xEF, 0xBB, 0xBF, 0x41]),  # a byte-order mark
		PackedByteArray([0x41, 0x00]),  # NUL
		PackedByteArray([0x41, 0x0A]),  # a control
		PackedByteArray([0x7F]),  # DEL
		PackedByteArray([0xC2, 0x9F]),  # a C1 control
	]
	for name_bytes: PackedByteArray in bad:
		var payload := _hello_with_name_bytes(name_bytes)
		(
			assert_object(_schema.decode(WireSchema.HELLO, payload))
			. override_failure_message(str(Array(name_bytes)))
			. is_null()
		)
	var long := PackedByteArray()
	long.resize(WireField.NAME_MAX_BYTES + 1)
	long.fill(0x41)
	_assert_rejected(WireSchema.HELLO, _hello_with_name_bytes(long), "a length of 81")
	_assert_rejected(WireSchema.HELLO, _hello_with_name_bytes(bad[4]), "not UTF-8 at byte 0")
	assert_array(Array(_errors.snapshot())).is_empty()


## Pins net/'s name characters to core/'s (net/ names no core/ class): every name the host makes
## (PlayerNames) encodes, and the wire takes no character PlayerNames drops.
func test_the_wire_takes_exactly_the_characters_player_names_keeps() -> void:
	var differ := PackedInt32Array()
	for code: int in range(0, 0x11000):
		if WireField.is_name_char(code) == PlayerNames.is_dropped(code):
			differ.append(code)
	for code: int in [0x1F600, 0x10FFFF, 0x110000, 0x7FFFFFFF]:
		if WireField.is_name_char(code) == PlayerNames.is_dropped(code):
			differ.append(code)
	assert_array(Array(differ)).is_empty()


## Every character a name may hold (is_name_char: noncharacters, the private-use planes and all)
## encodes and decodes back to itself, 16 to a name, with no engine error: a character Godot's
## UTF-8 decoder changes on the way (it drops U+FEFF) would make a good client's Hello fail
## silently.
func test_every_name_character_round_trips() -> void:
	var batch := ""
	var failed := PackedInt32Array()
	for code: int in range(0, 0x110000):
		if WireField.is_name_char(code):
			batch += String.chr(code)
		if batch.length() == PlayerNames.MAX_CHARS or (code == 0x10FFFF and not batch.is_empty()):
			var hello := {"version": WireSchema.VERSION, "content": 1, "name": batch}
			var message := WireMessage.new(&"Hello", hello)
			var decoded := _schema.decode(WireSchema.HELLO, _schema.encode(message))
			if decoded == null or decoded.fields["name"] != batch:
				failed.append(code)
			batch = ""
	assert_array(Array(failed)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


## A Hello of this version whose name is `name_bytes`, written by hand.
func _hello_with_name_bytes(name_bytes: PackedByteArray) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u16(0, WireSchema.VERSION)
	payload.encode_s64(2, 1)
	payload.append(name_bytes.size())
	payload.append_array(name_bytes)
	return payload


func _round_trip(message: WireMessage) -> WireMessage:
	var kind := _schema.kind_of(message.name)
	var payload := _schema.encode(message)
	var decoded := _schema.decode(kind, payload)
	assert_object(decoded).override_failure_message(_schema.explain(kind, payload)).is_not_null()
	return decoded


func _assert_refused(message: WireMessage) -> void:
	var logged := _errors.count()
	(
		assert_int(_schema.encode(message).size())
		. override_failure_message("%s %s was encoded" % [message.name, message.fields])
		. is_equal(0)
	)
	assert_int(_errors.count()).is_equal(logged + 1)
	_errors.clear()


func _assert_rejected(kind: int, payload: PackedByteArray, why: String) -> void:
	assert_object(_schema.decode(kind, payload)).is_null()
	assert_str(_schema.explain(kind, payload)).contains(why)


func _claim_with(field: String, value: Variant) -> Dictionary:
	var claim := Samples._claim()
	claim[field] = value
	return claim


func _settings_changed_fields() -> Dictionary:
	return Samples._settings_changed().to_dict()
