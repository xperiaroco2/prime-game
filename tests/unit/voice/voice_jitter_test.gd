extends GdUnitTestSuite
## VoiceJitter's order and loss (E39, the M5 ADR §1.4): silence, a sine through the fake codec,
## 3% loss, reordering, duplicates, the seq's wrap, a stale frame, flush and fade. Timing (the
## adaptive prebuffer, spurts, a stall): voice_jitter_timing_test.gd.

const Sim := preload("res://tests/unit/voice/voice_jitter_sim.gd")
const LATENCY := 30000


func test_silence_decodes_nothing_and_never_starts() -> void:
	var sim := Sim.new()
	sim.run([], 2000000)
	assert_array(sim.decoded).is_empty()
	assert_int(sim.jitter.starts).is_equal(0)
	assert_bool(sim.running).is_false()


func test_a_sine_through_the_fake_codec_comes_out_whole_and_in_order() -> void:
	var encoder := FakeVoiceCodec.new().new_encoder()
	assert_str(encoder.start(48000, true)).is_empty()
	var sim := Sim.new()
	var rng := _rng(1)
	var deliveries: Array[FixtureVoiceDelivery] = []
	var sent := PackedByteArray()
	for k: int in 50:
		var chunk := PackedVector2Array()
		chunk.resize(encoder.chunk_frames())
		for i: int in chunk.size():
			var v := 0.5 * sin(TAU * 440.0 * (k * chunk.size() + i) / 48000.0)
			chunk[i] = Vector2(v, v)
		var frame := encoder.encode(chunk)
		assert_int(frame.size()).is_equal(FakeVoiceCodec.FRAME_SAMPLES)
		sent.append_array(frame)
		var at := k * Sim.FRAME_USEC
		deliveries.append(
			FixtureVoiceDelivery.new(
				k, int(float(at) / Sim.TICK_USEC), frame, at + rng.randi_range(0, 30000)
			)
		)
	sim.run(deliveries, 2000000)
	assert_array(Array(sim.slots())).is_equal(range(50))
	assert_array(Array(sim.concealed_slots())).is_empty()
	var played := PackedByteArray()
	for decode: VoiceJitter.Decode in sim.decoded:
		played.append_array(decode.frame)
	assert_bool(played == sent).is_true()
	# Decoded, it is the sine at 8 kHz within µ-law's error.
	var worst := 0.0
	for n: int in played.size():
		var want := 0.5 * sin(TAU * 440.0 * (n * 6) / 48000.0)
		worst = maxf(worst, absf(FakeMuLaw.decode_sample(played[n]) - want))
	assert_float(worst).is_less(0.02)


func test_three_percent_loss_conceals_each_single_loss_once_and_skips_longer_runs() -> void:
	var sim := Sim.new()
	var rng := _rng(7)
	var all := sim.spurt(0, 0, 500, LATENCY, 20000, rng)
	var kept: Array[FixtureVoiceDelivery] = []
	var dropped: Dictionary[int, bool] = {}
	var loss := _rng(3)
	for d: FixtureVoiceDelivery in all:
		# The first and last frames always arrive: a loss there is outside a run (a stop's edge).
		if d.seq >= 5 and d.seq < 495 and loss.randf() < 0.03:
			dropped[d.seq] = true
		else:
			kept.append(d)
	sim.run(kept, 11000000)
	assert_int(dropped.size()).is_greater(8)
	var runs := 0
	for seq: int in dropped:
		if not dropped.has(seq - 1):
			runs += 1
	# Every frame that arrived plays once, in order; every slot is filled in order.
	var arrived := PackedInt64Array()
	for d: FixtureVoiceDelivery in kept:
		arrived.append(d.seq)
	assert_array(Array(sim.frames_played())).is_equal(Array(arrived))
	assert_int(sim.jitter.concealed).is_equal(runs)
	assert_int(sim.jitter.lost).is_equal(dropped.size() - runs)
	for slot: int in sim.concealed_slots():
		assert_bool(dropped.has(slot)).is_true()
		assert_bool(dropped.has(slot - 1)).is_false()
	_assert_increasing(sim.slots())


func test_a_concealed_frame_is_decoded_from_the_next_packet() -> void:
	var sim := Sim.new()
	var deliveries := sim.spurt(0, 0, 20, LATENCY, 0, _rng(1))
	deliveries.remove_at(10)
	sim.run(deliveries, 1000000)
	var concealing: Array[VoiceJitter.Decode] = []
	for decode: VoiceJitter.Decode in sim.decoded:
		if decode.conceal:
			concealing.append(decode)
	assert_int(concealing.size()).is_equal(1)
	assert_int(concealing[0].seq).is_equal(10)
	assert_int(concealing[0].frame.decode_u16(0)).is_equal(11)
	assert_array(Array(sim.slots())).is_equal(range(20))


func test_a_run_of_three_missing_is_concealed_once_and_the_rest_skipped() -> void:
	# Driven by hand, so the queue holds enough to wait out the gap instead of stopping.
	var jitter := VoiceJitter.new()
	for seq: int in 5:
		jitter.push(seq, 0, Sim.frame_of(seq), 0)
	assert_int(jitter.update(0, 0).size()).is_equal(5)
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.START)
	# 5, 6 and 7 never arrive.
	jitter.push(8, 1, Sim.frame_of(8), 20000)
	assert_array(jitter.update(100000, 20000)).is_empty()
	var out := jitter.update(20000, 100000)
	assert_int(out.size()).is_equal(2)
	assert_bool(out[0].conceal).is_true()
	assert_int(out[0].seq).is_equal(5)
	assert_int(out[0].frame.decode_u16(0)).is_equal(8)
	assert_bool(out[1].conceal).is_false()
	assert_int(out[1].seq).is_equal(8)
	assert_int(jitter.concealed).is_equal(1)
	assert_int(jitter.lost).is_equal(2)
	assert_int(jitter.underruns).is_equal(0)


func test_reordering_by_up_to_two_frames_conceals_nothing_once_the_prebuffer_adapted() -> void:
	# Five spurts of 1 s, 0.5 s apart. Every 5th frame arrives after the 2 behind it, every 7th
	# after the one behind it. The first spurt starts under the smallest prebuffer, before any
	# arrival was seen, so its late frames are concealed (or, its first, skipped); every later
	# start is adapted to the spread, and nothing is concealed or late any more.
	var sim := Sim.new()
	var deliveries: Array[FixtureVoiceDelivery] = []
	for s: int in 5:
		deliveries.append_array(sim.spurt(s * 50, s * 1500000, 50, LATENCY, 0, _rng(1)))
	for d: FixtureVoiceDelivery in deliveries:
		if d.seq % 5 == 0:
			d.arrival += 2 * Sim.FRAME_USEC + 1000
		elif d.seq % 7 == 0:
			d.arrival += Sim.FRAME_USEC + 1000
	sim.run(deliveries, 8000000)
	assert_int(sim.jitter.starts).is_equal(5)
	_assert_increasing(sim.slots())
	var after_first := PackedInt64Array()
	for seq: int in sim.frames_played():
		if seq >= 50:
			after_first.append(seq)
	assert_array(Array(after_first)).is_equal(range(50, 250))
	for slot: int in sim.concealed_slots():
		assert_int(slot).is_less(50)
	var first_spurt_losses := sim.jitter.concealed + (50 - _count_below(sim.slots(), 50))
	assert_int(sim.jitter.late).is_equal(first_spurt_losses)
	# The spread of 41 ms, stamped at polls 16.7 ms apart, plus a frame.
	assert_float(sim.mean_prebuffer_after(1000000)).is_between(55000.0, 85000.0)


func test_duplicates_play_once() -> void:
	var sim := Sim.new()
	var deliveries := sim.spurt(0, 0, 100, LATENCY, 10000, _rng(2))
	var doubled: Array[FixtureVoiceDelivery] = []
	for d: FixtureVoiceDelivery in deliveries:
		doubled.append(d)
		doubled.append(FixtureVoiceDelivery.new(d.seq, d.tick, d.frame, d.arrival + 15000))
	sim.run(doubled, 3000000)
	assert_array(Array(sim.frames_played())).is_equal(range(100))
	assert_int(sim.jitter.late).is_equal(100)
	assert_int(sim.jitter.received).is_equal(200)


func test_a_frame_older_than_the_next_due_is_dropped_as_late() -> void:
	var sim := Sim.new()
	var deliveries := sim.spurt(0, 0, 50, LATENCY, 0, _rng(1))
	# Frame 20 arrives half a second late, long after its slot was concealed.
	deliveries[20].arrival += 500000
	sim.run(deliveries, 2000000)
	assert_array(Array(sim.concealed_slots())).contains_exactly([20])
	assert_int(sim.jitter.late).is_equal(1)
	assert_array(Array(sim.slots())).is_equal(range(50))


func test_the_seq_wraps_at_sixteen_bits() -> void:
	var sim := Sim.new()
	var first := 0x10000 - 10
	var deliveries := sim.spurt(first, 0, 30, LATENCY, 20000, _rng(5))
	sim.run(deliveries, 2000000)
	assert_array(Array(sim.slots())).is_equal(range(first, first + 30))
	assert_int(sim.jitter.late).is_equal(0)
	assert_array(Array(sim.concealed_slots())).is_empty()


func test_a_stale_held_frame_is_discarded_before_the_next_spurt() -> void:
	var jitter := VoiceJitter.new()
	# A lone frame, short of the prebuffer: it never starts.
	jitter.push(0, 0, Sim.frame_of(0), 0)
	assert_array(jitter.update(0, 0)).is_empty()
	assert_array(jitter.update(0, VoiceJitter.STALE_USEC)).is_empty()
	assert_int(jitter.pending_frames()).is_equal(1)
	assert_array(jitter.update(0, VoiceJitter.STALE_USEC + 1)).is_empty()
	assert_int(jitter.stale).is_equal(1)
	assert_int(jitter.pending_frames()).is_equal(0)
	# The next spurt starts with its own first frame, not the old one.
	var at := 3000000
	jitter.push(1, 60, Sim.frame_of(1), at)
	jitter.push(2, 60, Sim.frame_of(2), at)
	var out := jitter.update(0, at)
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.START)
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].seq).is_equal(1)
	assert_bool(out[0].conceal).is_false()


func test_a_spurt_held_behind_a_long_run_is_not_stale_at_the_restart() -> void:
	# The manager's review of PR #234: the next spurt's first frame waits while a burst-filled
	# queue drains for longer than STALE_USEC; its staleness counts from the stop, not from its
	# arrival, so the first syllable still plays.
	var jitter := VoiceJitter.new()
	# A spurt arriving on time, so the prebuffer stays at its minimum.
	for seq: int in 5:
		jitter.push(seq, 0, Sim.frame_of(seq), seq * Sim.FRAME_USEC)
	assert_int(jitter.update(0, 80000).size()).is_equal(5)
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.START)
	jitter.push(5, 10, Sim.frame_of(5), 90000)
	var at := 90000
	while at <= 90000 + 2 * VoiceJitter.STALE_USEC:
		assert_array(jitter.update(300000, at)).is_empty()
		at += Sim.STEP_USEC
	assert_array(jitter.update(0, at)).is_empty()
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.STOP)
	jitter.push(6, 10, Sim.frame_of(6), at)
	jitter.push(7, 10, Sim.frame_of(7), at)
	var out := jitter.update(0, at + Sim.STEP_USEC)
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.START)
	var seqs: Array[int] = []
	for decode: VoiceJitter.Decode in out:
		seqs.append(decode.seq)
	assert_array(seqs).contains_exactly([5, 6, 7])
	assert_int(jitter.stale).is_equal(0)


func test_flush_empties_the_held_frames_and_leaves_the_old_seqs_behind() -> void:
	var jitter := VoiceJitter.new()
	for seq: int in 3:
		jitter.push(seq, 0, Sim.frame_of(seq), seq * Sim.FRAME_USEC)
	assert_int(jitter.update(0, 60000).size()).is_equal(3)
	jitter.push(4, 0, Sim.frame_of(4), 80000)
	jitter.flush()
	assert_bool(jitter.running).is_false()
	assert_int(jitter.pending_frames()).is_equal(0)
	# Frame 3, sent before the flush, arrives after it: dropped.
	jitter.push(3, 0, Sim.frame_of(3), 90000)
	assert_int(jitter.late).is_equal(1)
	# The next run starts at the first newer frame, with no concealment for the gap.
	jitter.push(6, 10, Sim.frame_of(6), 500000)
	jitter.push(7, 10, Sim.frame_of(7), 500000)
	var out := jitter.update(0, 500000)
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].seq).is_equal(6)
	assert_bool(out[0].conceal).is_false()


func test_fade_out_lowers_the_gain_then_says_flush() -> void:
	var sim := Sim.new()
	var deliveries := sim.spurt(0, 0, 100, LATENCY, 0, _rng(1))
	sim.run(deliveries, 500000)
	assert_bool(sim.running).is_true()
	var jitter := sim.jitter
	var at := 500000
	jitter.fade_out(at)
	assert_float(jitter.gain(at)).is_equal(1.0)
	assert_float(jitter.gain(at + 25000)).is_equal_approx(0.5, 0.001)
	assert_float(jitter.gain(at + VoiceJitter.FADE_USEC)).is_equal(0.0)
	assert_int(jitter.pending_frames()).is_equal(0)
	# Nothing more is decoded, and frames arriving meanwhile are dropped.
	jitter.push(60, 12, Sim.frame_of(60), at + 10000)
	assert_array(jitter.update(80000, at + 20000)).is_empty()
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.NONE)
	assert_array(jitter.update(60000, at + VoiceJitter.FADE_USEC)).is_empty()
	assert_int(jitter.command()).is_equal(VoiceJitter.Command.FLUSH)
	assert_bool(jitter.running).is_false()
	assert_float(jitter.gain(at + VoiceJitter.FADE_USEC)).is_equal(1.0)


func test_playback_stops_when_the_queue_runs_dry_with_nothing_held() -> void:
	var sim := Sim.new()
	sim.run(sim.spurt(0, 0, 25, LATENCY, 0, _rng(1)), 1500000)
	assert_int(sim.jitter.starts).is_equal(1)
	assert_int(sim.stops).is_equal(1)
	assert_bool(sim.running).is_false()
	assert_int(sim.dry).is_equal(0)
	assert_int(sim.jitter.underruns).is_equal(0)


func _count_below(values: PackedInt64Array, bound: int) -> int:
	var count := 0
	for value: int in values:
		if value < bound:
			count += 1
	return count


func _assert_increasing(values: PackedInt64Array) -> void:
	for i: int in range(1, values.size()):
		assert_int(values[i]).is_greater(values[i - 1])


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
