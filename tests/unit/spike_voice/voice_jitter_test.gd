extends GdUnitTestSuite
## Spike (#15): the listener's jitter logic with synthetic frames: in order, reordered, lost,
## duplicated, after silence, and the prebuffer gate.

const J := preload("res://spike/voice/voice_jitter.gd")


## A synthetic frame whose first byte is its sequence number.
func _frame(seq: int) -> PackedByteArray:
	return PackedByteArray([seq % 256, 0xAA])


## [first byte, fec] of every popped frame.
func _popped(j: SpikeVoiceJitter) -> Array:
	var out := []
	for f: Array in j.pop():
		out.append([(f[0] as PackedByteArray)[0], f[1]])
	return out


func test_in_order_frames_pass_straight_through() -> void:
	var j := J.new()
	for seq: int in [10, 11, 12]:
		j.push(seq, _frame(seq))
	assert_array(_popped(j)).is_equal([[10, 0], [11, 0], [12, 0]])
	assert_int(j.late + j.lost + j.fec).is_equal(0)


func test_reordered_frames_come_out_in_order() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	assert_array(_popped(j)).is_equal([[1, 0]])
	j.push(3, _frame(3))
	# 2 is missing and only one newer frame is held: wait for it.
	assert_array(_popped(j)).is_empty()
	j.push(2, _frame(2))
	assert_array(_popped(j)).is_equal([[2, 0], [3, 0]])
	assert_int(j.lost + j.fec).is_equal(0)


func test_single_loss_is_decoded_with_fec_from_the_next_frame() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.pop()
	j.push(3, _frame(3))
	j.push(4, _frame(4))
	# 2 never came: decode it from 3's FEC data, then 3 and 4 themselves.
	assert_array(_popped(j)).is_equal([[3, 1], [3, 0], [4, 0]])
	assert_int(j.fec).is_equal(1)
	assert_int(j.lost).is_equal(0)


func test_burst_loss_counts_lost_frames_and_recovers_the_last() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.pop()
	j.push(5, _frame(5))
	j.push(6, _frame(6))
	# 2 and 3 have no next frame here: lost. 4 is decoded with FEC from 5.
	assert_array(_popped(j)).is_equal([[5, 1], [5, 0], [6, 0]])
	assert_int(j.lost).is_equal(2)
	assert_int(j.fec).is_equal(1)


func test_late_and_duplicate_frames_are_dropped() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.push(2, _frame(2))
	j.pop()
	j.push(1, _frame(1))
	j.push(3, _frame(3))
	j.push(3, _frame(3))
	assert_array(_popped(j)).is_equal([[3, 0]])
	assert_int(j.late).is_equal(2)


func test_a_long_gap_starts_afresh() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.pop()
	# The speaker was out of range for a second: no loss is counted, playback just goes on.
	j.push(51, _frame(51))
	assert_array(_popped(j)).is_equal([[51, 0]])
	assert_int(j.resets).is_equal(1)
	assert_int(j.lost).is_equal(0)


func test_a_burst_of_in_order_frames_is_kept_whole() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.pop()
	# The listener stalled for 0.6 s: 30 frames arrive in one poll. No jump, nothing is lost.
	for seq in range(2, 32):
		j.push(seq, _frame(seq))
	assert_int(j.pop().size()).is_equal(30)
	assert_int(j.resets).is_equal(0)
	assert_int(j.lost + j.late).is_equal(0)


func test_reset_needs_a_jump_of_reset_gap_past_the_newest_frame() -> void:
	var j := J.new()
	j.push(10, _frame(10))
	j.pop()
	j.push(10 + J.RESET_GAP - 1, _frame(10 + J.RESET_GAP - 1))
	assert_int(j.resets).is_equal(0)
	var far := 10 + J.RESET_GAP - 1 + J.RESET_GAP
	j.push(far, _frame(far))
	assert_int(j.resets).is_equal(1)
	assert_array(_popped(j)).is_equal([[far % 256, 0]])


func test_a_frame_arriving_after_it_was_given_up_is_late() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.pop()
	j.push(3, _frame(3))
	j.push(4, _frame(4))
	j.pop()  # 2 is decoded with FEC from 3
	j.push(2, _frame(2))
	assert_int(j.late).is_equal(1)
	assert_array(_popped(j)).is_empty()


func test_silence_then_nothing_pending() -> void:
	var j := J.new()
	assert_array(_popped(j)).is_empty()
	assert_int(j.gate(0)).is_equal(SpikeVoiceJitter.Gate.KEEP)


func test_gate_waits_for_the_prebuffer_and_refills_after_running_dry() -> void:
	var j := J.new()
	assert_int(j.gate(J.PREBUFFER_FRAMES - 1)).is_equal(SpikeVoiceJitter.Gate.KEEP)
	assert_int(j.gate(J.PREBUFFER_FRAMES)).is_equal(SpikeVoiceJitter.Gate.START)
	assert_int(j.gate(960)).is_equal(SpikeVoiceJitter.Gate.KEEP)
	assert_int(j.gate(0)).is_equal(SpikeVoiceJitter.Gate.STOP)
	assert_int(j.underruns).is_equal(1)
	assert_int(j.gate(960)).is_equal(SpikeVoiceJitter.Gate.KEEP)
	assert_int(j.gate(J.PREBUFFER_FRAMES)).is_equal(SpikeVoiceJitter.Gate.START)


func test_pop_names_the_frame_each_entry_decodes() -> void:
	var j := J.new()
	j.push(1, _frame(1))
	j.pop()
	j.push(3, _frame(3))
	j.push(4, _frame(4))
	# 2 is decoded from 3's packet but is still frame 2: the latency log follows seq, not the packet.
	var seqs: Array[int] = []
	for f: Array in j.pop():
		seqs.append(f[2] as int)
	assert_array(seqs).is_equal([2, 3, 4])
