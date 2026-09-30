extends GdUnitTestSuite
## NetKindTable: the one table of kinds, lanes, directions and payload caps.

const RELIABLE := NetKindTable.Lane.RELIABLE
const LATEST := NetKindTable.Lane.LATEST
const VOICE := NetKindTable.Lane.VOICE
const BOTH := NetKindTable.Direction.BOTH


func test_lanes_map_to_channel_and_mode() -> void:
	assert_int(NetKindTable.channel_of(RELIABLE)).is_equal(0)
	assert_int(NetKindTable.channel_of(LATEST)).is_equal(0)
	assert_int(NetKindTable.channel_of(VOICE)).is_equal(1)
	assert_int(NetKindTable.mode_of(RELIABLE)).is_equal(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_int(NetKindTable.mode_of(LATEST)).is_equal(
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	# Voice is unordered: an ordered lane drops reordered frames before the jitter buffer.
	assert_int(NetKindTable.mode_of(VOICE)).is_equal(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)


func test_every_lane_channel_is_one_a_client_asks_for() -> void:
	for lane: NetKindTable.Lane in [RELIABLE, LATEST, VOICE]:
		assert_int(NetKindTable.channel_of(lane)).is_less_equal(NetKindTable.CHANNEL_COUNT)


func test_add_and_look_up() -> void:
	var table := NetKindTable.new()
	assert_int(table.add(5, LATEST, NetKindTable.Direction.HOST_TO_CLIENT, 100)).is_equal(OK)
	assert_bool(table.has(5)).is_true()
	assert_int(table.lane_of(5)).is_equal(LATEST)
	assert_int(table.payload_cap(5)).is_equal(100)
	assert_bool(table.allows(5, true)).is_true()
	assert_bool(table.allows(5, false)).is_false()


func test_unknown_kind() -> void:
	var table := NetKindTable.new()
	assert_bool(table.has(5)).is_false()
	assert_bool(table.allows(5, true)).is_false()
	assert_int(table.payload_cap(5)).is_equal(-1)


func test_directions() -> void:
	var table := NetKindTable.new()
	table.add(1, RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, 1)
	table.add(2, RELIABLE, BOTH, 1)
	assert_bool(table.allows(1, false)).is_true()
	assert_bool(table.allows(1, true)).is_false()
	assert_bool(table.allows(2, false)).is_true()
	assert_bool(table.allows(2, true)).is_true()


func test_kind_range() -> void:
	var table := NetKindTable.new()
	assert_int(table.add(0, RELIABLE, BOTH, 1)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(table.add(256, RELIABLE, BOTH, 1)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(table.add(1, RELIABLE, BOTH, 1)).is_equal(OK)
	assert_int(table.add(255, RELIABLE, BOTH, 1)).is_equal(OK)


func test_duplicate_kind_is_refused() -> void:
	var table := NetKindTable.new()
	table.add(3, RELIABLE, BOTH, 1)
	assert_int(table.add(3, LATEST, BOTH, 1)).is_equal(ERR_ALREADY_EXISTS)
	assert_int(table.lane_of(3)).is_equal(RELIABLE)


func test_payload_caps() -> void:
	var table := NetKindTable.new()
	assert_int(table.add(1, RELIABLE, BOTH, NetKindTable.MAX_PAYLOAD)).is_equal(OK)
	assert_int(table.add(2, RELIABLE, BOTH, NetKindTable.MAX_PAYLOAD + 1)).is_equal(
		ERR_INVALID_PARAMETER
	)
	assert_int(table.add(3, RELIABLE, BOTH, -1)).is_equal(ERR_INVALID_PARAMETER)


func test_unreliable_payloads_fit_one_enet_packet() -> void:
	var table := NetKindTable.new()
	var cap := NetKindTable.MAX_UNRELIABLE_PAYLOAD
	assert_int(table.add(1, LATEST, BOTH, cap)).is_equal(OK)
	assert_int(table.add(2, VOICE, BOTH, cap)).is_equal(OK)
	assert_int(table.add(3, LATEST, BOTH, cap + 1)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(table.add(4, VOICE, BOTH, cap + 1)).is_equal(ERR_INVALID_PARAMETER)


func test_the_game_table_holds_the_message_schemas_rows() -> void:
	# Built from WireSchema (3d); tests/unit/net/messages/ checks it row by row.
	var table := NetKindTable.game()
	assert_bool(table.has(WireSchema.HELLO)).is_true()
	assert_int(table.payload_cap(WireSchema.HELLO)).is_equal(NetKindTable.MAX_PAYLOAD)
	assert_bool(table.has(WireSchema.REJECTED)).is_true()
	assert_bool(table.has(0)).is_false()
