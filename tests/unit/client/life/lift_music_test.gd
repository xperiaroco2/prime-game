extends GdUnitTestSuite
## LiftMusic's placeholder (the M4 ADR's D9): a generated, looping, quiet 16-bit stream, so the
## dead hear something before a CC0 track replaces it.


func test_the_placeholder_is_a_looping_16_bit_stream_of_every_note() -> void:
	var wav := LiftMusic.placeholder_stream()
	assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_bool(wav.stereo).is_false()
	var frames := roundi(LiftMusic.RATE * LiftMusic.NOTE_S) * LiftMusic.NOTES.size()
	assert_int(wav.data.size()).is_equal(frames * 2)
	assert_int(wav.loop_end).is_equal(frames)
	assert_float(wav.get_length()).is_equal_approx(LiftMusic.NOTE_S * LiftMusic.NOTES.size(), 0.01)
	# Never louder than its amplitude, and not silent.
	var loudest := 0
	for at: int in range(0, wav.data.size(), 2):
		loudest = maxi(loudest, absi(wav.data.decode_s16(at)))
	assert_int(loudest).is_greater(1000)
	assert_int(loudest).is_less_equal(roundi(LiftMusic.AMPLITUDE * 32767.0) + 1)


func test_start_plays_once_and_stop_stops() -> void:
	var music := auto_free(LiftMusic.new()) as LiftMusic
	add_child(music)
	music.start()
	assert_bool(music.playing).is_true()
	assert_object(music.stream).is_not_null()
	music.start()
	music.stop()
	assert_bool(music.playing).is_false()
