extends GdUnitTestSuite
## Spike (#15): the voice messages decode their own output and reject malformed bytes.

const M := preload("res://spike/voice/voice_messages.gd")
const OPUS := [0xF8, 0xFF, 0xFE, 0x01, 0x02]


func test_up_round_trips() -> void:
	var opus := PackedByteArray(OPUS)
	assert_array(M.decode(M.encode_up(7, opus))).is_equal([M.KIND_VOICE_UP, 7, opus])


func test_down_round_trips() -> void:
	var opus := PackedByteArray(OPUS)
	var msg := M.decode(M.encode_down(1234, 7, opus))
	assert_array(msg).is_equal([M.KIND_VOICE_DOWN, 1234, 7, opus])


func test_rejects_trailing_bytes() -> void:
	var bytes := M.encode_up(1, PackedByteArray(OPUS))
	bytes.append_array(PackedByteArray([0, 0, 0, 0]))
	assert_array(M.decode(bytes)).is_empty()


func test_rejects_empty_and_oversized_opus() -> void:
	assert_array(M.decode(M.encode_up(1, PackedByteArray()))).is_empty()
	var big := PackedByteArray()
	big.resize(M.MAX_OPUS_BYTES + 1)
	assert_array(M.decode(M.encode_up(1, big))).is_empty()
	big.resize(M.MAX_OPUS_BYTES)
	assert_array(M.decode(M.encode_up(1, big))).is_not_empty()


func test_rejects_wrong_shapes() -> void:
	var opus := PackedByteArray(OPUS)
	assert_array(M.decode(var_to_bytes([M.KIND_VOICE_UP, -1, opus]))).is_empty()
	assert_array(M.decode(var_to_bytes([M.KIND_VOICE_UP, 1.0, opus]))).is_empty()
	assert_array(M.decode(var_to_bytes([M.KIND_VOICE_UP, 1, [1, 2, 3]]))).is_empty()
	assert_array(M.decode(var_to_bytes([M.KIND_VOICE_DOWN, 1, opus]))).is_empty()
	assert_array(M.decode(var_to_bytes([M.KIND_VOICE_DOWN, "2", 1, opus]))).is_empty()
	assert_array(M.decode(var_to_bytes([99, 1, opus]))).is_empty()
	assert_array(M.decode(PackedByteArray())).is_empty()


func test_does_not_decode_walk_messages() -> void:
	var move := SpikeWalkMessages.encode_move(1, Vector3.ZERO, 0.0)
	assert_array(M.decode(move)).is_empty()
	assert_array(SpikeWalkMessages.decode(M.encode_up(1, PackedByteArray(OPUS)))).is_empty()
