extends GdUnitTestSuite
## The ship engine's placeholder synthesis (#1501, tools/sfx/engine_synth.gd): each of the six
## sounds renders the same samples every time, scaled to its peak with no DC offset, starting at
## once and as long as sfx-check's task band allows; its WAV is mono 44.1 kHz 16-bit PCM; and
## each has its rendered file in assets/audio/prime_engine/ (in CI an LFS pointer, which is still
## a file).

const Synth := preload("res://tools/sfx/engine_synth.gd")
const FOLDER := "res://assets/audio/prime_engine/"
## sfx-check's task band (tools/sfx/categories.json), the category `engine*` files fall in.
const MIN_SECONDS := 0.1
const MAX_SECONDS := 3.0


func test_each_sound_is_scaled_to_its_peak_with_no_dc_offset() -> void:
	for sound_name: StringName in Synth.NAMES:
		var values: PackedFloat32Array = Synth.samples(sound_name)
		var top := 0.0
		var sum := 0.0
		for value: float in values:
			top = maxf(top, absf(value))
			sum += value
		var label := String(sound_name)
		var peak: float = Synth.PEAKS[sound_name]
		assert_float(top).override_failure_message(label).is_equal_approx(peak, 0.0001)
		assert_float(absf(sum / values.size())).override_failure_message(label).is_less(0.001)


func test_each_sound_starts_at_once_and_fits_the_task_band() -> void:
	for sound_name: StringName in Synth.NAMES:
		var values: PackedFloat32Array = Synth.samples(sound_name)
		var seconds := float(values.size()) / Synth.RATE
		var label := String(sound_name)
		assert_float(seconds).override_failure_message(label).is_between(MIN_SECONDS, MAX_SECONDS)
		# Heard within sfx-check's 50 ms of leading silence (-50 dBFS).
		var first := -1
		for i in values.size():
			if absf(values[i]) > 0.0032:
				first = i
				break
		assert_int(first).override_failure_message(label).is_between(0, int(0.05 * Synth.RATE))


func test_a_render_is_the_same_every_time() -> void:
	for sound_name: StringName in Synth.NAMES:
		assert_that(Synth.samples(sound_name)).is_equal(Synth.samples(sound_name))
	assert_int(Synth.samples(&"door_open").size()).is_equal(0)


func test_its_wav_is_mono_44_1_khz_16_bit_pcm() -> void:
	var values := PackedFloat32Array([0.0, 0.5, -1.0, 1.0])
	var wav: PackedByteArray = Synth.wav_bytes(values)
	assert_int(wav.size()).is_equal(44 + 8)
	assert_str(wav.slice(0, 4).get_string_from_ascii()).is_equal("RIFF")
	assert_str(wav.slice(8, 16).get_string_from_ascii()).is_equal("WAVEfmt ")
	assert_int(wav.decode_u16(20)).is_equal(1)
	assert_int(wav.decode_u16(22)).is_equal(1)
	assert_int(wav.decode_u32(24)).is_equal(44100)
	assert_int(wav.decode_u16(34)).is_equal(16)
	assert_int(wav.decode_u32(40)).is_equal(8)
	assert_int(wav.decode_s16(46)).is_equal(16384)
	assert_int(wav.decode_s16(48)).is_equal(-32767)
	assert_int(wav.decode_s16(50)).is_equal(32767)


func test_each_sound_has_its_rendered_file() -> void:
	for sound_name: StringName in Synth.NAMES:
		var path := FOLDER + String(sound_name) + ".wav"
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
