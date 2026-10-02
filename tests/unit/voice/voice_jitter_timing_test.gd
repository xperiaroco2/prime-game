extends GdUnitTestSuite
## VoiceJitter's timing (E39, the M5 ADR §1.4): the adaptive prebuffer under 0, 30 and 80 ms of
## arrival jitter, its cap, its 2 s window, talk spurts with gaps of 0.1 to 5 s, the spurt
## boundary's two rules, and a burst after the listener stalls. Order and loss:
## voice_jitter_test.gd.
##
## The talk is 10 spurts of 1.5 s, 0.5 s apart, arriving after 30 ms plus a uniform 0 to J ms. The
## client stamps arrivals at its polls, 16.7 ms apart at 60 fps, which widens the spread by up to a
## poll: the prebuffer lies near J + 20 ms plus about 8 ms. Underruns come only while the window
## has not yet seen the jitter (the first spurt starts at the smallest prebuffer); the bound the
## tests pin is none after the first 4 s and at most UNDERRUN_BOUND in all. The jitter's own
## underrun count must agree with the playback model's.

const Sim := preload("res://tests/unit/voice/voice_jitter_sim.gd")
const LATENCY := 30000
const SPURTS := 10
const SPURT_FRAMES := 75
const SPURT_EVERY := 2000000
## The adaptation's settling time: starts and underruns after it are judged.
const SETTLED := 4000000
## Underruns allowed over the whole talk, all in its first spurts (measured: at most 8 with seeds
## 1 to 6 at 30 and 80 ms).
const UNDERRUN_BOUND := 10


func test_no_jitter_keeps_the_smallest_prebuffer_and_never_underruns() -> void:
	for seed_value: int in [1, 2, 3]:
		var sim := _talk(0, seed_value)
		_assert_all_smallest(sim.start_prebuffers)
		assert_int(sim.jitter.starts).is_equal(SPURTS)
		assert_int(sim.dry).is_equal(0)
		assert_int(sim.jitter.underruns).is_equal(0)
		assert_array(Array(sim.concealed_slots())).is_empty()


func test_30_ms_of_jitter_gives_a_prebuffer_near_50_ms() -> void:
	for seed_value: int in [1, 2, 3]:
		var sim := _talk(30000, seed_value)
		assert_float(sim.mean_prebuffer_after(SETTLED)).is_between(45000.0, 65000.0)
		_assert_underruns_bounded(sim)


func test_80_ms_of_jitter_gives_a_prebuffer_near_100_ms() -> void:
	for seed_value: int in [1, 2, 3]:
		var sim := _talk(80000, seed_value)
		assert_float(sim.mean_prebuffer_after(SETTLED)).is_between(90000.0, 115000.0)
		_assert_underruns_bounded(sim)


func test_the_prebuffer_stops_at_its_cap() -> void:
	var sim := _talk(200000, 1)
	for i: int in sim.start_times.size():
		if sim.start_times[i] >= SETTLED:
			assert_int(sim.start_prebuffers[i]).is_equal(VoiceJitter.MAX_PREBUFFER_USEC)


func test_the_prebuffer_falls_back_once_the_jitter_leaves_the_window() -> void:
	# A spurt with 80 ms of jitter, then spurts of 0.5 s with none, a second apart from 2 s on.
	# The start at 2 s still sees the jitter; from 4 s on the window holds only calm arrivals.
	var sim := Sim.new()
	var rng := _rng(2)
	var deliveries := sim.spurt(0, 0, SPURT_FRAMES, LATENCY, 80000, rng)
	for s: int in 4:
		var first := SPURT_FRAMES + s * 25
		deliveries.append_array(sim.spurt(first, 2000000 + s * 1000000, 25, LATENCY, 0, rng))
	sim.run(deliveries, 6500000)
	var early := 0
	var late_starts := 0
	for i: int in sim.start_times.size():
		var at := sim.start_times[i]
		if at >= 2000000 and at < 2500000:
			early += 1
			assert_int(sim.start_prebuffers[i]).is_greater(VoiceJitter.MIN_PREBUFFER_USEC)
		elif at >= 4000000:
			late_starts += 1
			assert_int(sim.start_prebuffers[i]).is_equal(VoiceJitter.MIN_PREBUFFER_USEC)
	assert_int(early).is_equal(1)
	assert_int(late_starts).is_equal(2)


func test_spurts_with_gaps_of_a_tenth_to_5_seconds_each_start_afresh() -> void:
	var sim := Sim.new()
	var rng := _rng(4)
	var deliveries: Array[FixtureVoiceDelivery] = []
	var start := 0
	var first := 0
	for gap: int in [100000, 300000, 1000000, 5000000, 0]:
		deliveries.append_array(sim.spurt(first, start, 50, LATENCY, 10000, rng))
		start += 50 * Sim.FRAME_USEC + gap
		first += 50
	sim.run(deliveries, start + 1000000)
	assert_int(sim.jitter.spurts).is_equal(5)
	assert_int(sim.jitter.starts).is_equal(5)
	assert_int(sim.stops).is_equal(5)
	assert_int(sim.jitter.underruns).is_equal(0)
	assert_int(sim.dry).is_equal(0)
	assert_array(Array(sim.frames_played())).is_equal(range(250))
	assert_array(Array(sim.concealed_slots())).is_empty()


func test_a_frame_missing_across_a_stop_is_skipped_not_concealed() -> void:
	var sim := Sim.new()
	var deliveries := sim.spurt(0, 0, 50, LATENCY, 0, _rng(1))
	deliveries.append_array(sim.spurt(50, 1500000, 50, LATENCY, 0, _rng(1)))
	# The last frame of the first spurt is lost.
	deliveries.remove_at(49)
	sim.run(deliveries, 3000000)
	assert_array(Array(sim.concealed_slots())).is_empty()
	var want := range(49)
	want.append_array(range(50, 100))
	assert_array(Array(sim.slots())).is_equal(want)
	assert_int(sim.jitter.starts).is_equal(2)


func test_a_new_spurt_starts_on_a_late_arrival_or_a_tick_jump() -> void:
	var jitter := VoiceJitter.new()
	var f := Sim.FRAME_USEC
	for seq: int in 5:
		jitter.push(seq, int(float(seq * f) / Sim.TICK_USEC), Sim.frame_of(seq), seq * f)
	assert_int(jitter.spurts).is_equal(1)
	# On time, but its host tick is 3 past the newest frame's (1): a new spurt.
	jitter.push(5, 4, Sim.frame_of(5), 5 * f)
	assert_int(jitter.spurts).is_equal(2)
	# Its tick 2 past, and on time: the same spurt.
	jitter.push(6, 6, Sim.frame_of(6), 6 * f)
	assert_int(jitter.spurts).is_equal(2)
	# The same tick, but past its due time by just the limit: the same spurt.
	jitter.push(7, 6, Sim.frame_of(7), 7 * f + VoiceJitter.LATE_SPURT_USEC)
	assert_int(jitter.spurts).is_equal(2)
	# Later than that: a new spurt.
	jitter.push(8, 6, Sim.frame_of(8), 8 * f + VoiceJitter.LATE_SPURT_USEC + 1)
	assert_int(jitter.spurts).is_equal(3)
	# An older frame arriving late starts nothing.
	jitter.push(4, 1, Sim.frame_of(4), 20 * f)
	assert_int(jitter.spurts).is_equal(3)


func test_a_silence_between_spurts_is_not_jitter() -> void:
	# Spurts 0.3 s apart with no jitter: each arrives far past the last's due time, yet the
	# prebuffer stays the smallest.
	var sim := Sim.new()
	var deliveries: Array[FixtureVoiceDelivery] = []
	for s: int in 6:
		deliveries.append_array(sim.spurt(s * 25, s * 800000, 25, LATENCY, 0, _rng(1)))
	sim.run(deliveries, 6000000)
	assert_int(sim.jitter.spurts).is_equal(6)
	_assert_all_smallest(sim.start_prebuffers)


func test_a_burst_after_the_listener_stalls_plays_every_frame_in_order() -> void:
	var sim := Sim.new()
	var deliveries := sim.spurt(0, 0, 150, LATENCY, 10000, _rng(9))
	# The listener's process freezes for 300 ms: 15 frames arrive at the next poll at once.
	sim.stall_from = 1000000
	sim.stall_to = 1300000
	sim.run(deliveries, 4000000)
	assert_array(Array(sim.frames_played())).is_equal(range(150))
	assert_array(Array(sim.concealed_slots())).is_empty()
	# It ran dry once, and went on with the burst rather than stopping.
	assert_int(sim.dry).is_equal(1)
	assert_int(sim.jitter.underruns).is_equal(1)
	assert_int(sim.jitter.starts).is_equal(1)
	assert_int(sim.jitter.late).is_equal(0)


func _talk(jitter_usec: int, seed_value: int) -> Sim:
	var sim := Sim.new()
	var rng := _rng(seed_value)
	var deliveries: Array[FixtureVoiceDelivery] = []
	for s: int in SPURTS:
		deliveries.append_array(
			sim.spurt(s * SPURT_FRAMES, s * SPURT_EVERY, SPURT_FRAMES, LATENCY, jitter_usec, rng)
		)
	sim.run(deliveries, SPURTS * SPURT_EVERY + 1000000)
	return sim


func _assert_underruns_bounded(sim: Sim) -> void:
	assert_int(sim.dry_after(SETTLED)).is_equal(0)
	assert_int(sim.dry).is_less_equal(UNDERRUN_BOUND)
	assert_int(sim.jitter.underruns).is_equal(sim.dry)


func _assert_all_smallest(prebuffers: PackedInt64Array) -> void:
	assert_int(prebuffers.size()).is_greater(0)
	for prebuffer: int in prebuffers:
		assert_int(prebuffer).is_equal(VoiceJitter.MIN_PREBUFFER_USEC)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
