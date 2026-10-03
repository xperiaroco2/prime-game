extends GdUnitTestSuite
## VoiceDownEncoder (ARCHITECTURE §4.5 "Voice relay", #245): a relayed frame's VoiceDown encoded
## once, each listener's copy with its stream's seq written at the offset the schema gives, byte
## for byte what WireSchema.encode gives for that listener's VoiceDown.

const SPEAKERS: Array[int] = [1, 2, 300, 0x7FFFFFFF]
const SEQS: Array[int] = [0, 1, 0xFF, 0x100, 0x1234, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF]
const TICKS: Array[int] = [0, 41, 0xFFFFFFFE]

var _schema := WireSchema.game(true)


func test_the_game_schema_lets_the_seq_be_patched_in_place() -> void:
	var encoder := VoiceDownEncoder.new(_schema)
	assert_int(encoder.kind).is_equal(_schema.kind_of(&"VoiceDown"))
	# Behind the speaker, whatever its size: a row change that loses the fast path fails here.
	assert_int(encoder.seq_offset).is_equal(_schema.row_named(&"VoiceDown").fixed_offset("seq"))
	assert_int(encoder.seq_offset).is_greater_equal(0)


func test_every_copy_is_the_codec_s_bytes_for_its_seq() -> void:
	var encoder := VoiceDownEncoder.new(_schema)
	var compared := 0
	for speaker: int in SPEAKERS:
		for tick: int in TICKS:
			for size: int in [1, 45, WireSchema.MAX_OPUS]:
				var opus := _opus(size, speaker + tick)
				var message := _down(speaker, SEQS[0], tick, opus)
				var encoded := encoder.encode(message)
				assert_bool(encoded.is_empty()).is_false()
				for seq: int in SEQS:
					var copy := encoder.with_seq(encoded, message, seq)
					assert_str(copy.hex_encode()).is_equal(_codec(speaker, seq, tick, opus))
					compared += 1
				# The encoded frame and the message are left as they were.
				assert_str(encoded.hex_encode()).is_equal(_codec(speaker, SEQS[0], tick, opus))
				assert_int(message.fields["seq"] as int).is_equal(SEQS[0])
	assert_int(compared).is_equal(SPEAKERS.size() * TICKS.size() * 3 * SEQS.size())


func test_without_an_offset_every_copy_is_encoded_in_full() -> void:
	var encoder := VoiceDownEncoder.new(_schema)
	encoder.seq_offset = -1
	var opus := _opus(45, 3)
	var message := _down(2, 0, 7, opus)
	var encoded := encoder.encode(message)
	for seq: int in SEQS:
		assert_str(encoder.with_seq(encoded, message, seq).hex_encode()).is_equal(
			_codec(2, seq, 7, opus)
		)
	assert_int(message.fields["seq"] as int).is_equal(0)


func test_the_relay_s_frames_reach_each_listener_as_the_codec_would_write_them() -> void:
	# Several speakers and listeners through VoiceRelay, each stream across the u16 wrap.
	var encoder := VoiceDownEncoder.new(_schema)
	var relay := VoiceRelay.new()
	var table: Dictionary[int, PackedInt32Array] = {
		1: PackedInt32Array([2, 3]),
		2: PackedInt32Array([1, 3, 4]),
		3: PackedInt32Array([1, 2]),
		4: PackedInt32Array([2]),
	}
	relay.refresh(table, {})
	# Up to 4 seqs before the wrap; the speaker's own seq only orders one poll's frames.
	for i in VoiceRelay.SEQ_MODULO - 4:
		relay.hold(2, i % VoiceRelay.SEQ_MODULO, PackedByteArray([1]))
		relay.flush(1)
	relay.hold(1, 0, PackedByteArray([1]))
	relay.flush(1)
	var seen: Dictionary[Vector2i, Array] = {}
	for poll in 3:
		for speaker: int in [1, 2, 3]:
			for frame in 3:
				relay.hold(speaker, poll * 3 + frame, _opus(10 + frame, speaker * 7 + poll))
		for out: VoiceRelay.Outgoing in relay.flush(100 + poll):
			var encoded := encoder.encode(out.message)
			var fields := out.message.fields
			for i in out.listeners.size():
				var seq := out.seqs[i]
				var copy := encoder.with_seq(encoded, out.message, seq)
				var expected := _codec(
					fields["speaker"] as int, seq, 100 + poll, fields["opus"] as PackedByteArray
				)
				assert_str(copy.hex_encode()).is_equal(expected)
				var key := Vector2i(fields["speaker"] as int, out.listeners[i])
				if not seen.has(key):
					seen[key] = []
				seen[key].append(seq)
	# Speaker 2's streams (to 1, 3 and 4) had 65532 frames before: 65532 to 65535, then 0 to 4.
	var wrapped := [0xFFFC, 0xFFFD, 0xFFFE, 0xFFFF, 0, 1, 2, 3, 4]
	for listener: int in [1, 3, 4]:
		assert_array(seen[Vector2i(2, listener)]).is_equal(wrapped)
	# Speaker 1's (to 2 and 3) had one frame; speaker 3's (to 1 and 2) none.
	for listener: int in [2, 3]:
		assert_array(seen[Vector2i(1, listener)]).is_equal([1, 2, 3, 4, 5, 6, 7, 8, 9])
	for listener: int in [1, 2]:
		assert_array(seen[Vector2i(3, listener)]).is_equal([0, 1, 2, 3, 4, 5, 6, 7, 8])
	assert_int(seen.size()).is_equal(7)


func _down(speaker: int, seq: int, tick: int, opus: PackedByteArray) -> WireMessage:
	return WireMessage.new(
		&"VoiceDown", {"speaker": speaker, "seq": seq, "tick": tick, "opus": opus}
	)


func _codec(speaker: int, seq: int, tick: int, opus: PackedByteArray) -> String:
	return _schema.encode(_down(speaker, seq, tick, opus)).hex_encode()


func _opus(size: int, salt: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	for i in size:
		bytes[i] = (i * 31 + salt) & 0xFF
	return bytes
