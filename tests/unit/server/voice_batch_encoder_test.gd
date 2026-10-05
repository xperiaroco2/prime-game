extends GdUnitTestSuite
## VoiceBatchEncoder (ARCHITECTURE §4.5 "Voice relay", #245, M5-4b #374): a relayed frame's record
## encoded once, each listener's copy with its stream's seq written at the offset the schema gives,
## and a listener's records packed into as few VoiceBatches as the cap and the most frames allow,
## each byte for byte what WireSchema.encode gives for the VoiceBatch of its frames.

const SPEAKERS: Array[int] = [1, 2, 300, 0x7FFFFFFF]
const SEQS: Array[int] = [0, 1, 0xFF, 0x100, 0x1234, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF]
const TICKS: Array[int] = [0, 41, 0xFFFFFFFE]

var _schema := WireSchema.game(true)


func test_the_game_schema_lets_the_seq_be_patched_in_place() -> void:
	var encoder := VoiceBatchEncoder.new(_schema)
	var row := _schema.row_named(&"VoiceBatch")
	assert_int(encoder.kind).is_equal(row.kind)
	assert_int(encoder.cap).is_equal(NetKindTable.MAX_UNRELIABLE_PAYLOAD)
	assert_int(encoder.max_frames).is_equal(WireSchema.MAX_BATCH_FRAMES)
	# Behind the speaker, whatever its size: a row change that loses the fast path fails here.
	var frame := row.field_named("frames").element
	assert_int(encoder.seq_offset).is_equal(frame.fixed_offset("seq"))
	assert_int(encoder.seq_offset).is_equal(4)
	# The tick (4 bytes), then the count.
	assert_int(encoder.count_at).is_equal(4)


func test_every_record_is_the_codec_s_bytes_for_its_seq() -> void:
	var encoder := VoiceBatchEncoder.new(_schema)
	var compared := 0
	for speaker: int in SPEAKERS:
		for tick: int in TICKS:
			for size: int in [1, 45, WireSchema.MAX_OPUS]:
				var opus := _opus(size, speaker + tick)
				var down := _down(speaker, SEQS[0], tick, opus)
				var encoded := encoder.record(down)
				assert_bool(encoded.is_empty()).is_false()
				for seq: int in SEQS:
					var copy := encoder.with_seq(encoded, down, seq)
					var payloads := encoder.payloads(tick, [copy] as Array[PackedByteArray])
					assert_int(payloads.size()).is_equal(1)
					assert_str(payloads[0].hex_encode()).is_equal(
						_codec(tick, [_frame(speaker, seq, opus)])
					)
					compared += 1
				# The encoded record and the message are left as they were.
				var again := encoder.payloads(tick, [encoded] as Array[PackedByteArray])
				assert_str(again[0].hex_encode()).is_equal(
					_codec(tick, [_frame(speaker, SEQS[0], opus)])
				)
				assert_int(down.fields["seq"] as int).is_equal(SEQS[0])
	assert_int(compared).is_equal(SPEAKERS.size() * TICKS.size() * 3 * SEQS.size())


func test_without_an_offset_every_copy_is_encoded_in_full() -> void:
	var encoder := VoiceBatchEncoder.new(_schema)
	var fast := VoiceBatchEncoder.new(_schema)
	encoder.seq_offset = -1
	var opus := _opus(45, 3)
	var down := _down(2, 0, 7, opus)
	var encoded := encoder.record(down)
	for seq: int in SEQS:
		var copy := encoder.with_seq(encoded, down, seq)
		assert_str(copy.hex_encode()).is_equal(fast.with_seq(encoded, down, seq).hex_encode())
		var one := encoder.payloads(7, [copy] as Array[PackedByteArray])
		assert_str(one[0].hex_encode()).is_equal(_codec(7, [_frame(2, seq, opus)]))
	assert_int(down.fields["seq"] as int).is_equal(0)
	# add_frame takes the same slow path: a whole record per frame, never a patch at -1.
	var batches := encoder.start(7)
	for seq: int in SEQS:
		batches.add_frame(encoded, down, seq)
	var frames: Array[Dictionary] = []
	for seq: int in SEQS:
		frames.append(_frame(2, seq, opus))
	assert_str(batches.finish()[0].hex_encode()).is_equal(_codec(7, frames))


func test_records_fill_each_batch_up_to_the_cap_in_order() -> void:
	var encoder := VoiceBatchEncoder.new(_schema)
	# 9 speakers by 5 frames of 67 bytes (the spike's peak): 75 bytes a record, 13 to a batch.
	var records: Array[PackedByteArray] = []
	var frames: Array[Dictionary] = []
	for speaker in range(2, 11):
		for seq in 5:
			var opus := _opus(67, speaker * 5 + seq)
			records.append(encoder.record(_down(speaker, seq, 9, opus)))
			frames.append(_frame(speaker, seq, opus))
	var payloads := encoder.payloads(9, records)
	assert_int(payloads.size()).is_equal(4)
	var at := 0
	for payload: PackedByteArray in payloads:
		assert_int(payload.size()).is_less_equal(NetKindTable.MAX_UNRELIABLE_PAYLOAD)
		var count := payload[encoder.count_at]
		# Full but the last: one more record would pass the cap.
		if at + count < frames.size():
			assert_int(payload.size() + 75).is_greater(NetKindTable.MAX_UNRELIABLE_PAYLOAD)
		assert_str(payload.hex_encode()).is_equal(_codec(9, frames.slice(at, at + count)))
		at += count
	assert_int(at).is_equal(frames.size())
	assert_array(encoder.payloads(9, [] as Array[PackedByteArray])).is_empty()
	# The host's path across the same payload boundaries: the shared record of each frame, a
	# listener's own seq (not the record's) patched in place.
	var batches := encoder.start(9)
	var patched: Array[Dictionary] = []
	var i := 0
	for speaker in range(2, 11):
		for seq in 5:
			var opus := _opus(67, speaker * 5 + seq)
			batches.add_frame(records[i], _down(speaker, seq, 9, opus), 0xFF00 + i)
			patched.append(_frame(speaker, 0xFF00 + i, opus))
			i += 1
	at = 0
	var in_place := batches.finish()
	assert_int(in_place.size()).is_equal(4)
	for payload: PackedByteArray in in_place:
		var count := payload[encoder.count_at]
		assert_str(payload.hex_encode()).is_equal(_codec(9, patched.slice(at, at + count)))
		at += count
	assert_int(at).is_equal(patched.size())


func test_a_batch_holds_at_most_its_row_s_most_frames() -> void:
	var encoder := VoiceBatchEncoder.new(_schema)
	var records: Array[PackedByteArray] = []
	var frames: Array[Dictionary] = []
	for seq in WireSchema.MAX_BATCH_FRAMES + 1:
		var opus := PackedByteArray([seq & 0xFF])
		records.append(encoder.record(_down(3, seq, 1, opus)))
		frames.append(_frame(3, seq, opus))
	var payloads := encoder.payloads(1, records)
	assert_int(payloads.size()).is_equal(2)
	assert_int(payloads[0].size()).is_less_equal(NetKindTable.MAX_UNRELIABLE_PAYLOAD)
	assert_str(payloads[0].hex_encode()).is_equal(
		_codec(1, frames.slice(0, WireSchema.MAX_BATCH_FRAMES))
	)
	assert_str(payloads[1].hex_encode()).is_equal(
		_codec(1, frames.slice(WireSchema.MAX_BATCH_FRAMES))
	)


func test_the_relay_s_frames_reach_each_listener_as_the_codec_would_write_them() -> void:
	# Several speakers and listeners through VoiceRelay, each stream across the u16 wrap.
	var encoder := VoiceBatchEncoder.new(_schema)
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
		var records: Dictionary[int, Array] = {}
		# The host's path: each listener's batches take the shared record, the seq patched in place.
		var in_place: Dictionary[int, VoiceBatchEncoder.Batches] = {}
		var expected: Dictionary[int, Array] = {}
		for out: VoiceRelay.Outgoing in relay.flush(100 + poll):
			var encoded := encoder.record(out.message)
			var fields := out.message.fields
			for i in out.listeners.size():
				var listener := out.listeners[i]
				var seq := out.seqs[i]
				if not records.has(listener):
					records[listener] = []
					in_place[listener] = encoder.start(100 + poll)
					expected[listener] = []
				records[listener].append(encoder.with_seq(encoded, out.message, seq))
				in_place[listener].add_frame(encoded, out.message, seq)
				var speaker := fields["speaker"] as int
				expected[listener].append(_frame(speaker, seq, fields["opus"] as PackedByteArray))
				var key := Vector2i(speaker, listener)
				if not seen.has(key):
					seen[key] = []
				seen[key].append(seq)
		for listener: int in records:
			var each: Array[PackedByteArray] = []
			each.assign(records[listener])
			var payloads := encoder.payloads(100 + poll, each)
			assert_int(payloads.size()).is_equal(1)
			var frames: Array[Dictionary] = []
			frames.assign(expected[listener])
			assert_str(payloads[0].hex_encode()).is_equal(_codec(100 + poll, frames))
			var patched := in_place[listener].finish()
			assert_int(patched.size()).is_equal(1)
			assert_str(patched[0].hex_encode()).is_equal(_codec(100 + poll, frames))
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


func _frame(speaker: int, seq: int, opus: PackedByteArray) -> Dictionary:
	return {"speaker": speaker, "seq": seq, "opus": opus}


func _codec(tick: int, frames: Array[Dictionary]) -> String:
	var batch := WireMessage.new(&"VoiceBatch", {"tick": tick, "frames": frames})
	var encoded := _schema.encode(batch)
	assert_bool(encoded.is_empty()).is_false()
	return encoded.hex_encode()


func _opus(size: int, salt: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	for i in size:
		bytes[i] = (i * 31 + salt) & 0xFF
	return bytes
