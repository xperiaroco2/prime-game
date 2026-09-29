extends GdUnitTestSuite
## Spike (#15): the host relays a voice frame only to listeners within the cutoff, never to the
## speaker, and drops frames from unplaced or flooding speakers.

const Relay := preload("res://spike/voice/voice_relay.gd")
const OPUS := [1, 2, 3]


func _positions() -> Dictionary[int, Vector3]:
	return {2: Vector3(0, 1, 0), 3: Vector3(6, 1, 0), 4: Vector3(0, 1, 10)}


func _targets(sends: Array[Array]) -> Array:
	return sends.map(func(item: Array) -> int: return item[0])


func test_relays_to_listeners_in_range_only() -> void:
	var r := Relay.new()
	var sends := r.relay(2, 1, PackedByteArray(OPUS), _positions())
	assert_array(_targets(sends)).is_equal([3])
	var msg := SpikeVoiceMessages.decode(sends[0][1] as PackedByteArray)
	assert_array(msg).is_equal([SpikeVoiceMessages.KIND_VOICE_DOWN, 2, 1, PackedByteArray(OPUS)])
	assert_dict(r.delivered).is_equal({"2>3": 1})
	assert_dict(r.culled).is_equal({"2>4": 1})
	assert_float(r.max_delivered_distance).is_equal_approx(6.0, 0.001)
	assert_float(r.min_culled_distance).is_equal_approx(10.0, 0.001)


func test_unplaced_speaker_is_dropped() -> void:
	var r := Relay.new()
	assert_array(r.relay(9, 1, PackedByteArray(OPUS), _positions())).is_empty()
	assert_int(r.dropped_unplaced).is_equal(1)


func test_a_flood_is_cut_to_the_budget_and_refills() -> void:
	var r := Relay.new()
	var positions := _positions()
	var sent := 0
	for seq in 200:
		sent += r.relay(2, seq, PackedByteArray(OPUS), positions).size()
	assert_int(sent).is_equal(int(Relay.MAX_FRAMES_PER_SECOND))
	assert_int(r.dropped_flood).is_equal(200 - int(Relay.MAX_FRAMES_PER_SECOND))
	r.advance(0.1)
	var more := 0
	for seq in 20:
		more += r.relay(2, 200 + seq, PackedByteArray(OPUS), positions).size()
	assert_int(more).is_equal(7)  # 0.1 s x 75 frames/s, whole frames only


func test_steady_speech_is_never_dropped() -> void:
	var r := Relay.new()
	var positions := _positions()
	for seq in 500:  # 10 s of 20 ms frames, one per 20 ms frame of the host
		r.advance(0.02)
		r.relay(2, seq, PackedByteArray(OPUS), positions)
	assert_int(r.dropped_flood).is_equal(0)
	assert_int(r.delivered["2>3"]).is_equal(500)
