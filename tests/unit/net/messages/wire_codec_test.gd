extends GdUnitTestSuite
## WireSchema's encoder and decoder (ARCHITECTURE §4.4): a round trip of every row, the decoded
## shapes, what the encoder refuses and what the decoder rejects.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")

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
	_assert_refused(
		WireMessage.new(&"PlayerJoined", {"peer": 2, "name": "é", "spot": Vector3.ZERO})
	)
	var long_name := "x".repeat(WireField.TEXT_MAX + 1)
	_assert_refused(
		WireMessage.new(&"PlayerJoined", {"peer": 2, "name": long_name, "spot": Vector3.ZERO})
	)
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
	var long_name := "x".repeat(WireField.TEXT_MAX + 1)
	var joined := _schema.write(
		WireMessage.new(&"PlayerJoined", {"peer": 2, "name": long_name, "spot": Vector3.ZERO})
	)
	assert_int(joined.problem.length()).is_less(100)
	assert_str(joined.problem).ends_with("... is not a text")


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
