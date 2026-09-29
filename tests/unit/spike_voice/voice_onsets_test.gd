extends GdUnitTestSuite
## Spike (#16): the acoustic latency detector with synthetic microphone samples: a click in noise,
## its echo, the echo coming round again, and noise onsets that must not move the delay.

const O := preload("res://spike/voice/voice_onsets.gd")
const RATE := 48000

var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 16


## `seconds` of quiet room noise with 20 ms bursts at the given amplitudes, starting at the given
## sample indices (each burst starts sharply, as a click does).
func _samples(seconds: float, bursts: Dictionary[int, float]) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(roundi(seconds * RATE))
	for i in frames.size():
		var v := _rng.randf_range(-0.002, 0.002)
		frames[i] = Vector2(v, v)
	for start: int in bursts:
		for k in roundi(0.02 * RATE):
			var v := bursts[start] * sin(TAU * 1000.0 * k / RATE + 0.3)
			frames[start + k] += Vector2(v, v)
	return frames


## Every onset index feed() finds, fed in 20 ms chunks as the microphone delivers them.
func _onsets(o: SpikeVoiceOnsets, frames: PackedVector2Array) -> Array[int]:
	var found: Array[int] = []
	var chunk := 960
	for first in range(0, frames.size(), chunk):
		for onset: Array in o.feed(frames.slice(first, first + chunk)):
			found.append(onset[0] as int)
	return found


func test_a_click_is_found_within_a_block_of_its_start() -> void:
	var o := O.new(RATE)
	var found := _onsets(o, _samples(1.0, {30000: 0.5}))
	assert_int(found.size()).is_equal(1)
	# The first sample above the threshold: within a few samples of the burst's start.
	assert_int(found[0]).is_between(30000, 30010)


func test_room_noise_alone_finds_nothing() -> void:
	var o := O.new(RATE)
	assert_array(_onsets(o, _samples(2.0, {}))).is_empty()
	assert_float(o.floor_level).is_less(0.003)


func test_loud_room_noise_raises_the_floor_instead_of_firing_every_block() -> void:
	# Noise louder than MIN_LEVEL all the time (a fan, a laptop microphone), clicks well above it.
	var o := O.new(RATE)
	var frames := PackedVector2Array()
	frames.resize(roundi(4.0 * RATE))
	for i in frames.size():
		var v := _rng.randf_range(-0.02, 0.02)
		frames[i] = Vector2(v, v)
	var clicks: Array[int] = [roundi(1.5 * RATE), roundi(3.0 * RATE)]
	for start in clicks:
		for k in roundi(0.02 * RATE):
			var v := 0.4 * sin(TAU * 1000.0 * k / RATE + 0.3)
			frames[start + k] += Vector2(v, v)
	var late: Array[int] = []
	for index in _onsets(o, frames):
		if index >= roundi(0.5 * RATE):  # the floor may take a moment to settle
			late.append(index)
	assert_int(late.size()).is_equal(2)
	assert_int(late[0]).is_between(clicks[0], clicks[0] + 48)
	assert_int(late[1]).is_between(clicks[1], clicks[1] + 48)


func test_a_long_sound_fires_once_not_every_refractory_period() -> void:
	# Someone speaks for a second (a steady tone here): one onset at its start, then the floor
	# follows it.
	var o := O.new(RATE)
	var frames := _samples(2.0, {})
	for i in range(roundi(0.5 * RATE), roundi(1.5 * RATE)):
		var v := 0.1 * sin(TAU * 300.0 * i / RATE)
		frames[i] += Vector2(v, v)
	assert_int(_onsets(o, frames).size()).is_less_equal(2)


func test_reverb_right_after_a_click_is_not_an_onset() -> void:
	var o := O.new(RATE)
	# A second burst 40 ms after the first is inside the refractory time: the same click.
	var found := _onsets(o, _samples(1.0, {20000: 0.5, 20000 + roundi(0.04 * RATE): 0.4}))
	assert_int(found.size()).is_equal(1)


func test_clicks_and_their_echoes_are_found_in_samples_and_paired() -> void:
	var o := O.new(RATE)
	var gap := roundi(0.375 * RATE)
	var bursts: Dictionary[int, float] = {}
	for k in 4:
		bursts[10000 + k * roundi(2.5 * RATE)] = 0.3
		bursts[10000 + k * roundi(2.5 * RATE) + gap] = 0.05
	var pairs := O.echo_pairs(_onsets(o, _samples(10.5, bursts)), RATE)
	assert_int(pairs.size()).is_equal(4)
	for p: Array in pairs:
		assert_int((p[1] as int) - (p[0] as int)).is_between(gap - 10, gap + 10)


func test_noise_onsets_do_not_move_the_common_delay() -> void:
	# Ten clicks 2.5 s apart with echoes 375 ms (+-4 ms) later, and 40 noise onsets at random.
	var indices: Array[int] = []
	var clicks: Array[int] = []
	for k in 10:
		var click := 5000 + k * roundi(2.5 * RATE)
		clicks.append(click)
		indices.append(click)
		indices.append(click + roundi(0.375 * RATE) + _rng.randi_range(-192, 192))
	for k in 40:
		indices.append(_rng.randi_range(0, roundi(25.0 * RATE)))
	indices.sort()
	var pairs := O.echo_pairs(indices, RATE)
	var found: Array[int] = []
	for p: Array in pairs:
		var ms := ((p[1] as int) - (p[0] as int)) * 1000.0 / RATE
		assert_float(ms).is_between(345.0, 405.0)
		if clicks.has(p[0] as int):
			found.append(p[0] as int)
	# Every click is paired; a noise onset that happens to sit near the delay adds a pair, rarely.
	assert_int(found.size()).is_equal(10)
	assert_int(pairs.size()).is_less_equal(12)


func test_an_echo_is_not_also_a_click() -> void:
	# The echo came round once more: click, echo, echo of the echo; then the next click.
	var gap := roundi(0.3 * RATE)
	var indices: Array[int] = [1000, 1000 + gap, 1000 + 2 * gap, 200000, 200000 + gap]
	var pairs := O.echo_pairs(indices, RATE)
	assert_array(pairs).is_equal([[1000, 1000 + gap], [200000, 200000 + gap]])


func test_the_tail_of_a_long_click_and_of_its_echo_make_no_second_pair() -> void:
	# A click long enough to set the detector off again 80 ms later, and its echo just the same.
	var gap := roundi(0.365 * RATE)
	var tail := roundi(0.08 * RATE)
	var indices: Array[int] = []
	for click: int in [1000, 150000]:
		indices.append_array([click, click + tail, click + gap, click + gap + tail])
	var pairs := O.echo_pairs(indices, RATE)
	assert_array(pairs).is_equal([[1000, 1000 + gap], [150000, 150000 + gap]])


func test_no_onsets_or_no_gaps_give_no_pairs() -> void:
	var empty: Array[int] = []
	assert_array(O.echo_pairs(empty, RATE)).is_empty()
	var lone: Array[int] = [1000, 1000 + RATE]  # a second apart: beyond MAX_DELAY_S
	assert_array(O.echo_pairs(lone, RATE)).is_empty()
