extends GdUnitTestSuite
## VoiceGate (E37, D11, the M5 ADR §1.2): nothing in silence, voice activity with its hangover,
## push-to-talk, the pre-roll's order, and may_speak closing the gate and emptying the ring. Each
## chunk's frame here is one byte, its index, so a test reads which chunks were sent.

const LOUD := 0.5
const QUIET := 0.0
## 20 ms at 48 kHz.
const CHUNK := 960


func test_silence_sends_nothing() -> void:
	var gate := VoiceGate.new()
	var sent := PackedInt32Array()
	for i: int in 100:
		sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(i), true, false)))
	assert_array(Array(sent)).is_empty()
	assert_bool(gate.is_open()).is_false()


func test_noise_under_the_threshold_sends_nothing() -> void:
	var gate := VoiceGate.new()
	var sent := PackedInt32Array()
	for i: int in 50:
		var chunk := _chunk(VoiceGate.DEFAULT_THRESHOLD * 0.9)
		sent.append_array(_ids(gate.feed(chunk, _frame(i), true, false)))
	assert_array(Array(sent)).is_empty()


func test_a_sine_opens_voice_activity_with_the_pre_roll_first() -> void:
	var gate := VoiceGate.new()
	assert_int(gate.mode).is_equal(VoiceGate.Mode.VOICE_ACTIVITY)
	for i: int in 5:
		assert_array(gate.feed(_chunk(QUIET), _frame(i), true, false)).is_empty()
	var opening := _ids(gate.feed(_sine(LOUD), _frame(5), true, false))
	assert_array(Array(opening)).contains_exactly([3, 4, 5])
	assert_bool(gate.is_open()).is_true()
	assert_float(gate.last_peak).is_greater(LOUD * 0.99)
	assert_array(Array(_ids(gate.feed(_sine(LOUD), _frame(6), true, false)))).contains_exactly([6])


func test_the_pre_roll_holds_only_what_came_before_when_the_gate_opens_early() -> void:
	var gate := VoiceGate.new()
	gate.feed(_chunk(QUIET), _frame(0), true, false)
	var opening := _ids(gate.feed(_sine(LOUD), _frame(1), true, false))
	assert_array(Array(opening)).contains_exactly([0, 1])


func test_the_hangover_keeps_the_gate_open_for_300_ms_after_the_voice() -> void:
	var gate := VoiceGate.new()
	gate.feed(_sine(LOUD), _frame(0), true, false)
	var tail := PackedInt32Array()
	for i: int in range(1, 30):
		tail.append_array(_ids(gate.feed(_chunk(QUIET), _frame(i), true, false)))
	# 300 ms of 20 ms frames after the last loud one, then closed.
	assert_int(VoiceGate.HANGOVER_FRAMES * VoiceGate.FRAME_MS).is_equal(VoiceGate.HANGOVER_MS)
	assert_array(Array(tail)).contains_exactly(range(1, 1 + VoiceGate.HANGOVER_FRAMES))
	assert_bool(gate.is_open()).is_false()


func test_a_loud_chunk_in_the_hangover_restarts_it() -> void:
	var gate := VoiceGate.new()
	gate.feed(_sine(LOUD), _frame(0), true, false)
	for i: int in range(1, 11):
		gate.feed(_chunk(QUIET), _frame(i), true, false)
	gate.feed(_sine(LOUD), _frame(11), true, false)
	var tail := PackedInt32Array()
	for i: int in range(12, 40):
		tail.append_array(_ids(gate.feed(_chunk(QUIET), _frame(i), true, false)))
	assert_int(tail.size()).is_equal(VoiceGate.HANGOVER_FRAMES)
	assert_int(tail[0]).is_equal(12)


func test_the_gate_reopens_with_a_fresh_pre_roll_after_closing() -> void:
	var gate := VoiceGate.new()
	gate.feed(_sine(LOUD), _frame(0), true, false)
	for i: int in range(1, 1 + VoiceGate.HANGOVER_FRAMES + 5):
		gate.feed(_chunk(QUIET), _frame(i), true, false)
	assert_bool(gate.is_open()).is_false()
	var next := 1 + VoiceGate.HANGOVER_FRAMES + 5
	var opening := _ids(gate.feed(_sine(LOUD), _frame(next), true, false))
	assert_array(Array(opening)).contains_exactly([next - 2, next - 1, next])


func test_a_gate_closed_for_one_chunk_then_reopened_sends_no_frame_twice() -> void:
	# The ADR §1.2's case: the hangover ends on a chunk, the next is loud. The ring holds only
	# the chunk never sent, not the frames sent during the hangover.
	# The gate first opens with a full pre-roll, so a ring left holding it would show too.
	var gate := VoiceGate.new()
	var sent := PackedInt32Array()
	for i: int in 2:
		sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(i), true, false)))
	sent.append_array(_ids(gate.feed(_sine(LOUD), _frame(2), true, false)))
	var closing := 3 + VoiceGate.HANGOVER_FRAMES
	for i: int in range(3, closing + 1):
		sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(i), true, false)))
	assert_bool(gate.is_open()).is_false()
	sent.append_array(_ids(gate.feed(_sine(LOUD), _frame(closing + 1), true, false)))
	assert_array(Array(sent)).is_equal(range(closing + 2))


func test_a_quick_release_and_press_of_the_talk_key_sends_no_frame_twice() -> void:
	var gate := VoiceGate.new()
	gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	var sent := PackedInt32Array()
	for i: int in 6:
		sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(i), true, i >= 2)))
	sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(6), true, false)))
	sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(7), true, true)))
	assert_array(Array(sent)).is_equal(range(8))


func test_an_empty_frame_is_never_sent_nor_kept_for_the_pre_roll() -> void:
	# VoiceEncoder.encode returns an empty frame on failure. Its chunk still counts for the
	# gate and the hangover; the frame itself never leaves and never enters the ring.
	var gate := VoiceGate.new()
	var empty := PackedByteArray()
	gate.feed(_chunk(QUIET), _frame(0), true, false)
	gate.feed(_chunk(QUIET), _frame(1), true, false)
	assert_array(gate.feed(_chunk(QUIET), empty, true, false)).is_empty()
	# A loud chunk with an empty frame opens nothing yet: the pre-roll waits for a real frame.
	assert_array(gate.feed(_sine(LOUD), empty, true, false)).is_empty()
	assert_array(Array(_ids(gate.feed(_sine(LOUD), _frame(4), true, false)))).contains_exactly(
		[0, 1, 4]
	)
	assert_array(gate.feed(_sine(LOUD), empty, true, false)).is_empty()
	assert_bool(gate.is_open()).is_true()
	# An empty frame in the hangover uses up its chunk of it.
	var tail := PackedInt32Array()
	for i: int in range(6, 6 + VoiceGate.HANGOVER_FRAMES + 2):
		var frame := empty if i == 6 else _frame(i)
		tail.append_array(_ids(gate.feed(_chunk(QUIET), frame, true, false)))
	assert_array(Array(tail)).contains_exactly(range(7, 6 + VoiceGate.HANGOVER_FRAMES))
	# Push-to-talk alike.
	gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	assert_array(gate.feed(_chunk(QUIET), empty, true, true)).is_empty()
	assert_array(Array(_ids(gate.feed(_chunk(QUIET), _frame(30), true, true)))).contains_exactly(
		[21, 22, 30]
	)


func test_push_to_talk_sends_only_while_the_key_is_held() -> void:
	var gate := VoiceGate.new()
	gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	var sent := PackedInt32Array()
	# Loud but the key up: nothing.
	for i: int in 4:
		sent.append_array(_ids(gate.feed(_sine(LOUD), _frame(i), true, false)))
	assert_array(Array(sent)).is_empty()
	# The key down, even in silence: the pre-roll, then every frame.
	sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(4), true, true)))
	sent.append_array(_ids(gate.feed(_chunk(QUIET), _frame(5), true, true)))
	assert_array(Array(sent)).contains_exactly([2, 3, 4, 5])
	# The key up: closed at once, no hangover.
	assert_array(gate.feed(_sine(LOUD), _frame(6), true, false)).is_empty()
	assert_bool(gate.is_open()).is_false()


func test_may_speak_false_sends_nothing_with_the_key_held() -> void:
	var gate := VoiceGate.new()
	gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	var sent := PackedInt32Array()
	for i: int in 20:
		sent.append_array(_ids(gate.feed(_sine(LOUD), _frame(i), false, true)))
	assert_array(Array(sent)).is_empty()
	assert_bool(gate.is_open()).is_false()


func test_may_speak_false_sends_nothing_in_voice_activity() -> void:
	var gate := VoiceGate.new()
	var sent := PackedInt32Array()
	for i: int in 20:
		sent.append_array(_ids(gate.feed(_sine(LOUD), _frame(i), false, false)))
	assert_array(Array(sent)).is_empty()


func test_may_speak_turning_false_closes_an_open_gate_at_once() -> void:
	var gate := VoiceGate.new()
	gate.feed(_sine(LOUD), _frame(0), true, false)
	assert_bool(gate.is_open()).is_true()
	# Knocked down mid-word: the hangover does not carry the next frames out.
	assert_array(gate.feed(_sine(LOUD), _frame(1), false, false)).is_empty()
	assert_array(gate.feed(_chunk(QUIET), _frame(2), true, false)).is_empty()


func test_no_frame_captured_before_may_speak_turns_true_is_sent_with_the_key_held() -> void:
	# The ADR's case: frames captured while the player could be heard sit in the ring (the key
	# up), then the player goes down and whispers with the key held while being raised; when the
	# revive lands (may_speak true again) only frames captured from then on go out.
	var gate := VoiceGate.new()
	gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	gate.feed(_sine(LOUD), _frame(0), true, false)
	gate.feed(_sine(LOUD), _frame(1), true, false)
	gate.feed(_sine(LOUD), _frame(2), false, true)
	gate.feed(_sine(LOUD), _frame(3), false, true)
	var revived := _ids(gate.feed(_sine(LOUD), _frame(4), true, true))
	assert_array(Array(revived)).contains_exactly([4])


func test_no_frame_captured_before_may_speak_turns_true_opens_voice_activity() -> void:
	var gate := VoiceGate.new()
	gate.feed(_chunk(QUIET), _frame(0), true, false)
	gate.feed(_chunk(QUIET), _frame(1), true, false)
	gate.feed(_chunk(QUIET), _frame(2), false, false)
	var opening := _ids(gate.feed(_sine(LOUD), _frame(3), true, false))
	assert_array(Array(opening)).contains_exactly([3])


func test_switching_the_mode_closes_the_gate_and_ends_the_hangover() -> void:
	var gate := VoiceGate.new()
	gate.feed(_sine(LOUD), _frame(0), true, false)
	gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	gate.set_mode(VoiceGate.Mode.VOICE_ACTIVITY)
	assert_bool(gate.is_open()).is_false()
	assert_array(gate.feed(_chunk(QUIET), _frame(1), true, false)).is_empty()


func test_the_threshold_is_settable() -> void:
	var gate := VoiceGate.new()
	gate.threshold = 0.6
	assert_array(gate.feed(_sine(LOUD), _frame(0), true, false)).is_empty()
	gate.threshold = 0.4
	assert_array(Array(_ids(gate.feed(_sine(LOUD), _frame(1), true, false)))).contains_exactly(
		[0, 1]
	)


func test_the_level_is_the_peak_of_either_channel() -> void:
	var chunk := PackedVector2Array([Vector2(0.1, -0.2), Vector2(-0.7, 0.3), Vector2(0.0, 0.0)])
	assert_float(VoiceGate.peak_of(chunk)).is_equal_approx(0.7, 0.0001)
	assert_float(VoiceGate.peak_of(PackedVector2Array())).is_equal(0.0)


func _chunk(level: float) -> PackedVector2Array:
	var chunk := PackedVector2Array()
	chunk.resize(CHUNK)
	chunk.fill(Vector2(level, level))
	return chunk


func _sine(amplitude: float) -> PackedVector2Array:
	var chunk := PackedVector2Array()
	chunk.resize(CHUNK)
	for i: int in CHUNK:
		var v := amplitude * sin(TAU * 440.0 * i / 48000.0)
		chunk[i] = Vector2(v, v)
	return chunk


func _frame(index: int) -> PackedByteArray:
	return PackedByteArray([index])


func _ids(frames: Array[PackedByteArray]) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for frame: PackedByteArray in frames:
		ids.append(frame[0])
	return ids
