extends GdUnitTestSuite
## Voices through real players and buses under the Dummy driver, which mixes (the M5 ADR §6): the
## fake codec's sine through VoiceViews, a VoiceSpeaker at the talker's mouth and the Voice bus.
## The Voice bus's peak falls with the distance from the ears, is silent past `max_distance` (D12:
## ATTENUATION_DISABLED fades linearly to silence there), and falls silent within the fade after a
## flush while frames keep arriving; and behind a fixture wall (M5-7, D13 (a)) it is about 8 dB
## lower at 400 Hz and far lower at 3 kHz (the muffled bus's low-pass), so duller, not only
## quieter. The mixer runs in real time, so each measurement listens for a bounded LISTEN_MS of the
## real clock and reads the bus's peak once a frame.

const World := preload("res://tests/integration/client/world/voice_test_world.gd")
const TALKER := World.TALKER
## How long each measurement listens, and how long it lets the playback start first.
const LISTEN_MS := 500
const SETTLE_MS := 250
## The Dummy driver's meter lags the mix: the longest wait for a mixed block to show (a bound
## generous for a loaded machine, not a measured latency).
const MIX_SLACK_MS := 300
## Frames kept ahead of real time, so the queue never runs dry while talking and holds about
## 200 ms when a flush comes (the spike measured 60 to 120 ms queued; more makes a missing flush
## last long enough for the bursty meter to show it).
const AHEAD := 10
## A peak at or below this is silence (Godot reports -200 dB for none).
const SILENT_DB := -100.0
## The muffle's measurement: a wall 1.5 m ahead of the ears, between them and a talker at 3 m.
const EARS := Vector3(0, 1.5, 0)
const WALL_AT := Vector3(0, 1.5, -1.5)
const WALL_SIZE := Vector3(4, 3, 0.2)
## A tone well under the low-pass (D13: near 1 kHz) and one well over it.
const LOW_HZ := 400.0
const HIGH_HZ := 3000.0

var _world: World
var _bus := -1
var _seq := 0
var _start_ms := 0
var _base_tick := 100
## The talker's tone and its phase: a phase carried over frames, so a change of tone does not
## click.
var _hz := LOW_HZ
var _phase := 0.0


func before_test() -> void:
	AudioBuses.ensure()
	_bus = AudioBuses.index_of(AudioBuses.VOICE)
	_world = World.new()
	_world.real_clock = true
	add_child(_world)
	_seq = 0
	_start_ms = Time.get_ticks_msec()


func after_test() -> void:
	_world.free()


func test_the_voice_falls_with_distance_and_is_silent_past_the_cutoff() -> void:
	_world.place({TALKER: Vector3(0, 0, -1.5)})
	await _drawn()
	var near := await _listen(LISTEN_MS)
	assert_float(near).is_greater(-30.0)
	_world.place({TALKER: Vector3(0, 0, -6.0)})
	await _drawn()
	var far := await _listen(LISTEN_MS)
	assert_float(far).is_greater(SILENT_DB)
	# Linear to silence at 8 m: 0.81 of the amplitude at 1.5 m, 0.25 at 6 m (about 10 dB).
	assert_float(near - far).is_greater(6.0)
	_world.place({TALKER: Vector3(0, 0, -9.0)})
	await _drawn()
	var beyond := await _listen(LISTEN_MS)
	assert_float(beyond).is_less_equal(SILENT_DB)


func test_a_player_past_its_max_distance_is_silent_even_fed() -> void:
	# The speaker alone, fed directly at 8.5 m from the ears with an 8 m cutoff: Godot's clamp.
	var speaker: VoiceSpeaker = VoiceSpeaker.new(_world.codec)
	speaker.set_cutoff(8.0)
	speaker.position = Vector3(0, 1.5, -8.5)
	_world.add_child(speaker)
	var loudest := -200.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < LISTEN_MS:
		_feed_speaker(speaker)
		speaker.step(Time.get_ticks_usec())
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 >= SETTLE_MS:
			loudest = maxf(loudest, AudioServer.get_bus_peak_volume_left_db(_bus, 0))
	assert_int(speaker.jitter.starts).is_equal(1)
	assert_float(loudest).is_less_equal(SILENT_DB)
	# Within the cutoff, the same speaker is heard.
	speaker.position = Vector3(0, 1.5, -2.0)
	loudest = -200.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < LISTEN_MS:
		_feed_speaker(speaker)
		speaker.step(Time.get_ticks_usec())
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 >= SETTLE_MS:
			loudest = maxf(loudest, AudioServer.get_bus_peak_volume_left_db(_bus, 0))
	assert_float(loudest).is_greater(-30.0)
	speaker.queue_free()


func test_a_flushed_speaker_is_silent_within_the_fade_while_frames_keep_coming() -> void:
	_world.place({TALKER: Vector3(0, 0, -2.0)})
	await _drawn()
	assert_float(await _listen(LISTEN_MS)).is_greater(-30.0)
	_world.event(&"KnockedDown", {"peer": TALKER, "position": Vector3(0, 0, -2.0)})
	# The fade takes 50 ms; the Dummy driver's meter then reports the next mixed block, which
	# comes in bursts (up to about 100 ms apart, later under load). So: silent within the fade and
	# MIX_SLACK_MS, and silent from then on, though frames keep arriving.
	var speaker := _world.voices.speaker_of(TALKER)
	assert_int(speaker.queued_usec()).is_greater(VoiceJitter.FADE_USEC)
	var flushed_at := Time.get_ticks_msec()
	var silent_at := -1
	var loud_after := 0
	var faded := false
	while Time.get_ticks_msec() - flushed_at < LISTEN_MS + MIX_SLACK_MS:
		_feed_views()
		await get_tree().process_frame
		if not faded and not speaker.fading():
			# The fade ended in a flush: nothing of the queue is left to play.
			faded = true
			assert_int(speaker.queued_usec()).is_equal(0)
		var peak := AudioServer.get_bus_peak_volume_left_db(_bus, 0)
		if peak <= SILENT_DB and silent_at < 0:
			silent_at = Time.get_ticks_msec() - flushed_at
		elif peak > SILENT_DB and silent_at >= 0:
			loud_after += 1
	assert_int(silent_at).is_between(0, roundi(VoiceJitter.FADE_USEC / 1000.0) + MIX_SLACK_MS)
	assert_int(loud_after).is_equal(0)
	assert_bool(faded).is_true()
	assert_bool(_world.voices.speaker_of(TALKER).is_active()).is_false()


func test_a_wall_makes_the_voice_quieter_and_duller() -> void:
	_world.ears_at = EARS
	_world.place({TALKER: Vector3(0, 0, -3.0)})
	await _drawn()
	# After each change (the tone, the wall) the queued audio, the 100 ms ease and the meter's lag
	# pass before the peak counts.
	var settle := SETTLE_MS + MIX_SLACK_MS
	var open_low := await _listen(LISTEN_MS + settle, settle)
	_hz = HIGH_HZ
	var open_high := await _listen(LISTEN_MS + settle, settle)
	_world.add_box(WALL_AT, WALL_SIZE)
	var walled_high := await _listen(LISTEN_MS + settle, settle)
	_hz = LOW_HZ
	var walled_low := await _listen(LISTEN_MS + settle, settle)
	assert_float(_world.voices.muffle_of(TALKER).amount).is_equal(1.0)
	var low_drop := open_low - walled_low
	var high_drop := open_high - walled_high
	print(
		(
			"muffle: 400 Hz %.1f -> %.1f dB (%.1f), 3 kHz %.1f -> %.1f dB (%.1f)"
			% [open_low, walled_low, low_drop, open_high, walled_high, high_drop]
		)
	)
	assert_float(walled_low).is_greater(SILENT_DB)
	# Quieter: D13's 8 dB, with the low-pass's own bit at 400 Hz (measured about 9 in all).
	assert_float(low_drop).is_between(6.0, 14.0)
	# Duller: the highs lose far more than the lows (measured 36 against 9 dB). Without the muffled
	# bus's low-pass, Godot's own distance shelf on the quieter player still gives the highs about
	# 8 dB more (measured 15.8 against 7.9), so the bound sits above that.
	assert_float(high_drop - low_drop).is_greater(12.0)


## Feeds TALKER's frames in real time through VoiceViews for `ms`, and returns the Voice bus's
## loudest peak after `settle` ms.
func _listen(ms: int, settle := SETTLE_MS) -> float:
	var loudest := -200.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		_feed_views()
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 >= settle:
			loudest = maxf(loudest, AudioServer.get_bus_peak_volume_left_db(_bus, 0))
	return loudest


## The frames due by now, AHEAD of real time, as VoiceDowns of TALKER.
func _feed_views() -> void:
	while _seq <= _due():
		_world.voices.on_voice(TALKER, _seq & 0xFFFF, _tick(), _tone())
		_seq += 1


## The next fake-codec frame of the talker's tone (`_hz`), its phase carried on.
func _tone() -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(FakeVoiceCodec.FRAME_SAMPLES)
	for i: int in FakeVoiceCodec.FRAME_SAMPLES:
		frame[i] = FakeMuLaw.encode_sample(0.5 * sin(_phase))
		_phase = fmod(_phase + TAU * _hz / FakeVoiceCodec.RATE, TAU)
	return frame


func _feed_speaker(speaker: VoiceSpeaker) -> void:
	while _seq <= _due():
		speaker.push(_seq & 0xFFFF, _tick(), World.sine(_seq, 0.5), Time.get_ticks_usec())
		_seq += 1


func _due() -> int:
	return int(float(Time.get_ticks_msec() - _start_ms) / 20.0) + AHEAD


## The host tick of the next frame: 20 ms frames, 50 ms ticks, after every snapshot's tick.
func _tick() -> int:
	return _base_tick + int(_seq * 20.0 / 50.0)


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
