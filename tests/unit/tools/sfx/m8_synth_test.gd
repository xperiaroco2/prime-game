extends GdUnitTestSuite
## The M8 sounds (#1674, tools/sfx/m8_synth.gd): each of the engineer's 27 picks has its take,
## renders the same samples every time, scaled to its peak with no DC offset, starting at once and
## within sfx-check's band of its category; each has its rendered file in assets/audio/prime_m8/
## (in CI an LFS pointer, which is still a file) that SfxSet plays under the same id; the charger's
## loop is imported looping.

const Synth := preload("res://tools/sfx/m8_synth.gd")
## sfx-check's widest band of the categories the files fall in (tools/sfx/categories.json): item,
## task, life, lobby and timer.
const MIN_SECONDS := 0.05
const MAX_SECONDS := 3.0


func test_every_pick_has_its_take_and_its_peak() -> void:
	assert_int(Synth.PICKS.size()).is_equal(27)
	assert_array(Synth.PEAKS.keys()).contains_exactly_in_any_order(Synth.PICKS.keys())
	for sound: StringName in Synth.PICKS:
		var values: PackedFloat32Array = Synth.samples(sound)
		var label := String(sound)
		assert_int(values.size()).override_failure_message(label).is_greater(0)
		var top := 0.0
		var sum := 0.0
		for value: float in values:
			top = maxf(top, absf(value))
			sum += value
		var peak: float = Synth.PEAKS[sound]
		assert_float(top).override_failure_message(label).is_equal_approx(peak, 0.0001)
		assert_float(absf(sum / values.size())).override_failure_message(label).is_less(0.001)
	assert_int(Synth.samples(&"door_open").size()).is_equal(0)


func test_each_sound_starts_at_once_and_fits_its_band() -> void:
	for sound: StringName in Synth.PICKS:
		var values: PackedFloat32Array = Synth.samples(sound)
		var seconds := float(values.size()) / Synth.EngineSynth.RATE
		var label := String(sound)
		assert_float(seconds).override_failure_message(label).is_between(MIN_SECONDS, MAX_SECONDS)
		# Heard within sfx-check's 50 ms of leading silence (-50 dBFS).
		var first := -1
		for i in values.size():
			if absf(values[i]) > 0.0032:
				first = i
				break
		var by := int(0.05 * Synth.EngineSynth.RATE)
		assert_int(first).override_failure_message(label).is_between(0, by)


func test_a_render_is_the_same_every_time() -> void:
	for sound: StringName in [&"hit_fist", &"respawn", &"engine_charging", &"timer_tick"]:
		assert_that(Synth.samples(sound)).is_equal(Synth.samples(sound))


func test_each_sound_has_its_rendered_file_that_sfx_set_plays() -> void:
	for sound: StringName in Synth.PICKS:
		var path := Synth.FOLDER + String(sound) + ".wav"
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
		var played := SfxSet.paths_for(sound if sound != &"swing" else SoundChooser.SWING)
		assert_array(Array(played)).override_failure_message(path).contains([path])


func test_the_charging_loop_is_imported_looping() -> void:
	for sound: StringName in Synth.LOOPS:
		var stream := load(Synth.FOLDER + String(sound) + ".wav") as AudioStreamWAV
		assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
		assert_int(stream.loop_begin).is_equal(0)
