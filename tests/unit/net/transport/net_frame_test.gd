extends GdUnitTestSuite
## NetFrame: the 3-byte header and the defensive decode of every received packet.

const EVENT := 10  # host -> client, reliable, up to 16 bytes
const INTENT := 11  # client -> host, reliable
const STATE := 12  # host -> client, latest
const VOICE := 13  # both ways, voice lane
const RELIABLE := MultiplayerPeer.TRANSFER_MODE_RELIABLE
const ORDERED := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
const UNORDERED := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE

var _kinds: NetKindTable


func before_test() -> void:
	_kinds = NetKindTable.new()
	_kinds.add(EVENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.HOST_TO_CLIENT, 16)
	_kinds.add(INTENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, 16)
	_kinds.add(STATE, NetKindTable.Lane.LATEST, NetKindTable.Direction.HOST_TO_CLIENT, 16)
	_kinds.add(VOICE, NetKindTable.Lane.VOICE, NetKindTable.Direction.BOTH, 16)


func test_encode_is_kind_then_little_endian_size_then_payload() -> void:
	var bytes := NetFrame.encode(EVENT, PackedByteArray([7, 8, 9]))
	assert_array(Array(bytes)).is_equal([EVENT, 3, 0, 7, 8, 9])


func test_round_trip() -> void:
	var payload := PackedByteArray([1, 2, 3, 4])
	var frame := _from_host(NetFrame.encode(EVENT, payload))
	assert_int(frame.reject).is_equal(NetRejects.Reason.NONE)
	assert_int(frame.kind).is_equal(EVENT)
	assert_array(Array(frame.payload)).is_equal(Array(payload))


func test_empty_payload_round_trips() -> void:
	var frame := _from_host(NetFrame.encode(EVENT, PackedByteArray()))
	assert_int(frame.reject).is_equal(NetRejects.Reason.NONE)
	assert_int(frame.payload.size()).is_equal(0)


func test_each_lane_round_trips_on_its_channel_and_mode() -> void:
	var state := NetFrame.decode(
		NetFrame.encode(STATE, PackedByteArray([1])), _kinds, true, 0, ORDERED
	)
	var voice := NetFrame.decode(
		NetFrame.encode(VOICE, PackedByteArray([1])), _kinds, false, 1, UNORDERED
	)
	assert_int(state.reject).is_equal(NetRejects.Reason.NONE)
	assert_int(voice.reject).is_equal(NetRejects.Reason.NONE)


func test_shorter_than_the_header_is_rejected() -> void:
	for size: int in [0, 1, 2]:
		var bytes := PackedByteArray()
		bytes.resize(size)
		assert_int(_from_host(bytes).reject).is_equal(NetRejects.Reason.TOO_SHORT)


func test_over_the_packet_cap_is_rejected_before_anything_else() -> void:
	var bytes := PackedByteArray()
	bytes.resize(NetFrame.MAX_PACKET_BYTES + 1)
	bytes.encode_u8(0, EVENT)
	assert_int(_from_host(bytes).reject).is_equal(NetRejects.Reason.TOO_LARGE)


func test_unknown_kind_is_rejected() -> void:
	var bytes := NetFrame.encode(99, PackedByteArray())
	assert_int(_from_host(bytes).reject).is_equal(NetRejects.Reason.UNKNOWN_KIND)


func test_kind_zero_is_never_valid() -> void:
	assert_int(_kinds.add(0, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.BOTH, 4)).is_equal(
		ERR_INVALID_PARAMETER
	)
	var zeroed := PackedByteArray([0, 0, 0])
	assert_int(_from_host(zeroed).reject).is_equal(NetRejects.Reason.UNKNOWN_KIND)


func test_wrong_direction_is_rejected() -> void:
	# A client may not send an event, and the host may not send an intent.
	var event_from_client := NetFrame.decode(
		NetFrame.encode(EVENT, PackedByteArray()), _kinds, false, 0, RELIABLE
	)
	var intent_from_host := _from_host(NetFrame.encode(INTENT, PackedByteArray()))
	assert_int(event_from_client.reject).is_equal(NetRejects.Reason.WRONG_DIRECTION)
	assert_int(intent_from_host.reject).is_equal(NetRejects.Reason.WRONG_DIRECTION)


func test_wrong_channel_or_mode_is_rejected() -> void:
	var bytes := NetFrame.encode(EVENT, PackedByteArray())
	var wrong_channel := NetFrame.decode(bytes, _kinds, true, 1, RELIABLE)
	var wrong_mode := NetFrame.decode(bytes, _kinds, true, 0, ORDERED)
	assert_int(wrong_channel.reject).is_equal(NetRejects.Reason.WRONG_LANE)
	assert_int(wrong_mode.reject).is_equal(NetRejects.Reason.WRONG_LANE)


func test_declared_payload_over_the_kind_cap_is_rejected() -> void:
	var payload := PackedByteArray()
	payload.resize(17)
	var bytes := NetFrame.encode(EVENT, payload)
	assert_int(_from_host(bytes).reject).is_equal(NetRejects.Reason.PAYLOAD_TOO_LARGE)


func test_truncated_packet_is_rejected() -> void:
	var bytes := NetFrame.encode(EVENT, PackedByteArray([1, 2, 3]))
	bytes.resize(bytes.size() - 1)
	assert_int(_from_host(bytes).reject).is_equal(NetRejects.Reason.TRUNCATED)


func test_trailing_bytes_are_rejected() -> void:
	var bytes := NetFrame.encode(EVENT, PackedByteArray([1, 2, 3]))
	bytes.append(0)
	assert_int(_from_host(bytes).reject).is_equal(NetRejects.Reason.TRAILING_BYTES)


func test_a_rejected_frame_carries_no_message() -> void:
	var bytes := NetFrame.encode(EVENT, PackedByteArray([1, 2, 3]))
	bytes.append(0)
	var frame := _from_host(bytes)
	assert_int(frame.kind).is_equal(0)
	assert_int(frame.payload.size()).is_equal(0)


func _from_host(bytes: PackedByteArray) -> NetFrame:
	return NetFrame.decode(bytes, _kinds, true, 0, RELIABLE)
