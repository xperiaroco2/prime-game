extends GdUnitTestSuite
## WireSchema's table (ARCHITECTURE §4.3): kind ranges, lanes and directions, caps against the
## fields at the wire's maxima, the transport's table built from it, the debug rows, the frozen
## rows 1 and 32 byte for byte, and the version.

const CLIENT_TO_HOST := NetKindTable.Direction.CLIENT_TO_HOST
const HOST_TO_CLIENT := NetKindTable.Direction.HOST_TO_CLIENT

## The rows whose content can take them past their cap at the maxima (WireBudget checks the mode).
const OVER_CAP_AT_MAXIMA := [&"ChangeSettings", &"Welcome", &"SettingsChanged"]
## A content-sized row whose cap holds it even at the maxima (32 settings and a 255-byte path).
const UNDER_CAP_AT_MAXIMA := [&"LoadMatch"]


func test_kinds_fall_in_their_ranges_with_their_direction_and_lane() -> void:
	for each: WireRow in WireSchema.game(true).rows():
		var message := "%s (kind %d)" % [each.name, each.kind]
		if each.kind < WireSchema.FIRST_DEBUG:
			assert_int(each.direction).override_failure_message(message).is_equal(CLIENT_TO_HOST)
			assert_bool(each.lane != NetKindTable.Lane.VOICE).is_true()
		elif each.kind < WireSchema.FIRST_EVENT:
			assert_int(each.direction).override_failure_message(message).is_equal(CLIENT_TO_HOST)
			assert_int(each.lane).is_equal(NetKindTable.Lane.RELIABLE)
		elif each.kind < WireSchema.FIRST_STATE:
			# Every event is RELIABLE: SelfStatus too, which is sent only on change.
			assert_int(each.direction).override_failure_message(message).is_equal(HOST_TO_CLIENT)
			assert_int(each.lane).override_failure_message(message).is_equal(
				NetKindTable.Lane.RELIABLE
			)
		elif each.kind < WireSchema.FIRST_VOICE:
			assert_int(each.lane).override_failure_message(message).is_equal(
				NetKindTable.Lane.LATEST
			)
		else:
			assert_int(each.kind).is_less_equal(WireSchema.LAST_VOICE)
			assert_int(each.lane).override_failure_message(message).is_equal(
				NetKindTable.Lane.VOICE
			)


func test_only_move_claim_and_the_snapshot_travel_latest() -> void:
	var latest: Array[StringName] = []
	for each: WireRow in WireSchema.game(true).rows():
		if each.lane == NetKindTable.Lane.LATEST:
			latest.append(each.name)
	assert_array(latest).contains_exactly([&"MoveClaim", &"Snapshot"])


func test_a_fixed_rows_cap_is_its_size_at_the_maxima() -> void:
	for each: WireRow in WireSchema.game(true).rows():
		var message := (
			"%s (kind %d): cap %d, at most %d" % [each.name, each.kind, each.cap, each.max_size()]
		)
		if each.kind == WireSchema.HELLO:
			assert_int(each.cap).is_equal(NetKindTable.MAX_PAYLOAD)
		elif each.name == &"Snapshot":
			# The unreliable cap; 15 avatars take 680 bytes (45 each with the belt item, M4-5).
			assert_int(each.cap).is_equal(NetKindTable.MAX_UNRELIABLE_PAYLOAD)
			assert_int(each.max_size()).is_equal(680)
		elif each.name == &"VoiceBatch":
			# The unreliable cap bounds it first (M5-4b): 113 frames of one byte fit, of more do not.
			assert_int(each.cap).is_equal(NetKindTable.MAX_UNRELIABLE_PAYLOAD)
			assert_int(4 + 1 + WireSchema.MAX_BATCH_FRAMES * 9).is_less_equal(each.cap)
			assert_int(4 + 1 + (WireSchema.MAX_BATCH_FRAMES + 1) * 9).is_greater(each.cap)
			assert_int(each.max_size()).is_greater(each.cap)
		elif each.name in OVER_CAP_AT_MAXIMA:
			assert_bool(each.content_sized).is_true()
			assert_int(each.max_size()).override_failure_message(message).is_greater(each.cap)
		elif each.name in UNDER_CAP_AT_MAXIMA:
			assert_int(each.max_size()).override_failure_message(message).is_less(each.cap)
		else:
			assert_int(each.cap).override_failure_message(message).is_equal(each.max_size())


func test_a_field_s_fixed_offset_counts_the_fixed_sizes_before_it() -> void:
	var schema := WireSchema.game(true)
	var batch := schema.row_named(&"VoiceBatch")
	# The tick (4 bytes), then the frames, whose size varies.
	assert_int(batch.fixed_offset("tick")).is_equal(0)
	assert_int(batch.fixed_offset("frames")).is_equal(-1)
	assert_object(batch.field_named("listener")).is_null()
	# Inside each frame's record: speaker (a peer, 4 bytes), seq (u16), then the sized Opus bytes.
	var frame := batch.field_named("frames").element
	assert_int(frame.fixed_offset("speaker")).is_equal(0)
	assert_int(frame.fixed_offset("seq")).is_equal(4)
	assert_int(frame.fixed_offset("opus")).is_equal(-1)
	assert_int(frame.fixed_offset("listener")).is_equal(-1)
	assert_int(frame.parts[1].type).is_equal(WireField.Type.U16)
	assert_int(frame.parts[2].type).is_equal(WireField.Type.SIZED_OPUS)
	# Only a record has parts to place.
	assert_int(batch.field_named("tick").fixed_offset("tick")).is_equal(-1)
	assert_object(schema.row_named(&"VoiceDown")).is_null()
	# A wire-only slot takes its bytes but is no payload field: Raise is seq (u32), then target.
	var raise := schema.row_named(&"Raise")
	assert_int(raise.fixed_offset("target")).is_equal(4)
	assert_int(raise.fixed_offset("seq")).is_equal(-1)
	assert_object(raise.field_named("seq")).is_null()
	# Behind a field whose size varies, no offset holds for every payload.
	var probe := WireRow.new(
		200,
		&"Probe",
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.RELIABLE,
		64,
		[WireField.id("name"), WireField.of("count", WireField.Type.U16)]
	)
	assert_int(probe.fixed_offset("count")).is_equal(-1)


func test_content_sized_rows_are_the_ones_wire_budget_checks() -> void:
	var sized: Array[StringName] = []
	for each: WireRow in WireSchema.game(true).rows():
		if each.content_sized:
			sized.append(each.name)
	(
		assert_array(sized)
		. contains_exactly_in_any_order(
			[
				&"ChangeSettings",
				&"Welcome",
				&"SettingsChanged",
				&"PlayersPlaced",
				&"LoadMatch",
				&"Teammates",
				&"StationPlaced",
				&"ItemSpawned",
			]
		)
	)


func test_the_game_kind_table_is_built_from_the_rows() -> void:
	var table := NetKindTable.game()
	var schema := WireSchema.game(OS.is_debug_build())
	for kind: int in range(NetKindTable.MIN_KIND, NetKindTable.MAX_KIND + 1):
		var each := schema.row(kind)
		assert_bool(table.has(kind)).override_failure_message(str(kind)).is_equal(each != null)
		if each == null:
			continue
		assert_int(table.lane_of(kind)).is_equal(each.lane)
		assert_int(table.payload_cap(kind)).is_equal(each.cap)
		assert_bool(table.allows(kind, true)).is_equal(each.direction == HOST_TO_CLIENT)
		assert_bool(table.allows(kind, false)).is_equal(each.direction == CLIENT_TO_HOST)


func test_debug_commands_exist_only_in_a_debug_builds_table() -> void:
	var release := WireSchema.game(false)
	var debug := WireSchema.game(true)
	for kind: int in range(WireSchema.FIRST_DEBUG, WireSchema.FIRST_EVENT):
		assert_object(release.row(kind)).is_null()
		assert_bool(release.kind_table().has(kind)).is_false()
	assert_str(str(debug.row(24).name)).is_equal("ForceRole")
	assert_str(str(debug.row(25).name)).is_equal("ForceClock")
	assert_int(debug.rows().size()).is_equal(release.rows().size() + 2)
	for each: WireRow in release.rows():
		var twin := debug.row(each.kind)
		assert_str(str(twin.name)).is_equal(str(each.name))
		assert_int(twin.cap).is_equal(each.cap)
		assert_int(twin.lane).is_equal(each.lane)
		assert_int(twin.direction).is_equal(each.direction)


func test_every_row_has_a_field_and_no_field_names_a_seed() -> void:
	for each: WireRow in WireSchema.game(true).rows():
		assert_bool(each.fields.is_empty()).is_false()
		for field_name: String in _every_name(each.fields):
			(
				assert_bool(field_name.to_lower().contains("seed"))
				. override_failure_message("%s.%s" % [each.name, field_name])
				. is_false()
			)


func test_the_hello_row_is_frozen_byte_for_byte() -> void:
	var schema := WireSchema.game(false)
	var hello := schema.row(WireSchema.HELLO)
	assert_str(str(hello.name)).is_equal("Hello")
	assert_int(hello.direction).is_equal(CLIENT_TO_HOST)
	assert_int(hello.lane).is_equal(NetKindTable.Lane.RELIABLE)
	assert_int(hello.cap).is_equal(8192)
	var payload := schema.encode(
		WireMessage.new(&"Hello", {"version": 0x0102, "content": 0x1122334455667788})
	)
	assert_array(Array(payload)).is_equal(
		[0x02, 0x01, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11]
	)


func test_the_rejected_row_is_frozen_byte_for_byte() -> void:
	var schema := WireSchema.game(false)
	var rejected := schema.row(WireSchema.REJECTED)
	assert_str(str(rejected.name)).is_equal("Rejected")
	assert_int(rejected.direction).is_equal(HOST_TO_CLIENT)
	assert_int(rejected.lane).is_equal(NetKindTable.Lane.RELIABLE)
	assert_int(rejected.cap).is_equal(37)
	var payload := schema.encode(
		WireMessage.new(&"Rejected", {"seq": 0x01020304, "reason": &"wrong_version"})
	)
	var expected := [0x04, 0x03, 0x02, 0x01, 13]
	expected.append_array(Array("wrong_version".to_ascii_buffer()))
	assert_array(Array(payload)).is_equal(expected)


func test_a_hello_of_another_version_decodes_to_its_version_alone() -> void:
	var schema := WireSchema.game(false)
	var longer := PackedByteArray()
	longer.resize(2)
	longer.encode_u16(0, WireSchema.VERSION + 1)
	for i: int in 300:
		longer.append(i % 256)
	var decoded := schema.decode(WireSchema.HELLO, longer)
	assert_object(decoded).is_not_null()
	assert_dict(decoded.fields).is_equal({"version": WireSchema.VERSION + 1})
	var bare := schema.decode(WireSchema.HELLO, longer.slice(0, 2))
	assert_dict(bare.fields).is_equal({"version": WireSchema.VERSION + 1})
	assert_object(schema.decode(WireSchema.HELLO, longer.slice(0, 1))).is_null()


func test_a_hello_of_this_version_is_decoded_strictly() -> void:
	var schema := WireSchema.game(false)
	var payload := schema.encode(
		WireMessage.new(&"Hello", {"version": WireSchema.VERSION, "content": 5})
	)
	assert_dict(schema.decode(WireSchema.HELLO, payload).fields).is_equal(
		{"version": WireSchema.VERSION, "content": 5}
	)
	assert_object(schema.decode(WireSchema.HELLO, payload.slice(0, 9))).is_null()
	payload.append(0)
	assert_object(schema.decode(WireSchema.HELLO, payload)).is_null()


func test_the_version_is_cores_protocol_version() -> void:
	assert_int(WireSchema.VERSION).is_equal(JoinRules.PROTOCOL_VERSION)


func _every_name(fields: Array[WireField]) -> PackedStringArray:
	var found := PackedStringArray()
	for field: WireField in fields:
		found.append(field.name)
		found.append_array(field.flags)
		found.append_array(_every_name(field.parts))
		for inner: WireField in [field.element, field.key]:
			if inner != null:
				found.append_array(_every_name([inner]))
	return found
