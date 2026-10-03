extends GdUnitTestSuite
## VoiceCapture (the M5 ADR §1.1, E36 as amended): the device list, the chosen device opened, 20 ms
## chunks at the device's rate with their age, errors in words, and the "opening" mark (named before
## the device opens, cleared after its first second, a clean close or a refusal). Through
## FakeMicrophone: no test opens a microphone.

var _marks: PackedStringArray


func before_test() -> void:
	_marks = PackedStringArray()


func test_the_device_list_has_the_windows_default_first_and_each_device_once() -> void:
	var capture := _capture()
	var mic := capture.microphone as FakeMicrophone
	mic.names = PackedStringArray(["Headset Microphone", "Default", "Headset Microphone"])
	assert_array(Array(capture.devices())).contains_exactly(["Default", "Headset Microphone"])


func test_it_opens_the_chosen_device_and_reads_20_ms_chunks_at_its_rate() -> void:
	var capture := _capture()
	var mic := capture.microphone as FakeMicrophone
	mic.rate = 44100
	assert_bool(capture.open("Headset Microphone")).is_true()
	assert_str(mic.opened_device).is_equal("Headset Microphone")
	assert_str(capture.device).is_equal("Headset Microphone")
	assert_int(capture.rate()).is_equal(44100)
	assert_int(capture.chunk_frames()).is_equal(882)
	mic.capture(882 * 3 + 100, 0.2)
	var chunks := capture.read(capture.chunk_frames())
	assert_int(chunks.size()).is_equal(3)
	for chunk: VoiceCapture.Chunk in chunks:
		assert_int(chunk.frames.size()).is_equal(882)
	# The first chunk waited behind everything captured: (3 * 882 + 100) frames at 44.1 kHz.
	assert_int(chunks[0].age_usec).is_equal(int((882.0 * 3 + 100) * 1000000.0 / 44100))
	assert_int(chunks[2].age_usec).is_less(chunks[0].age_usec)
	# What is left is less than a chunk: it waits for the next read.
	assert_int(mic.frames_available()).is_equal(100)
	assert_array(capture.read(capture.chunk_frames())).is_empty()


func test_the_mark_names_the_device_before_it_opens_and_clears_after_one_second() -> void:
	var capture := _capture()
	var mic := capture.microphone as FakeMicrophone
	capture.mark_changed.connect(func(device: String) -> void: _note(device, mic))
	assert_bool(capture.open("Default")).is_true()
	# Named before the device opened (the note records whether it was open then).
	assert_array(Array(_marks)).contains_exactly(["Default (closed)"])
	assert_bool(capture.is_settling()).is_true()
	mic.capture_chunks(49, 0.0)
	capture.read(capture.chunk_frames())
	assert_bool(capture.is_settling()).is_true()
	mic.capture_chunks(1, 0.0)
	capture.read(capture.chunk_frames())
	assert_bool(capture.is_settling()).is_false()
	assert_array(Array(_marks)).contains_exactly(["Default (closed)", " (open)"])
	# Closing a settled device leaves the mark alone.
	capture.close()
	assert_int(_marks.size()).is_equal(2)
	assert_int(mic.closes).is_equal(1)


func test_a_clean_close_or_a_refusal_clears_the_mark() -> void:
	var capture := _capture()
	var mic := capture.microphone as FakeMicrophone
	capture.mark_changed.connect(func(device: String) -> void: _marks.append(device))
	capture.open("Default")
	capture.close()
	assert_array(Array(_marks)).contains_exactly(["Default", ""])
	assert_bool(capture.is_open()).is_false()
	_marks.clear()
	mic.open_result = ERR_UNAUTHORIZED
	assert_bool(capture.open("Headset Microphone")).is_false()
	assert_array(Array(_marks)).contains_exactly(["Headset Microphone", ""])
	assert_str(capture.error).contains("Headset Microphone")
	assert_str(capture.error).contains("privacy")
	assert_bool(capture.is_open()).is_false()


func test_a_missing_device_is_an_error_and_sets_no_mark() -> void:
	var capture := _capture()
	var mic := capture.microphone as FakeMicrophone
	capture.mark_changed.connect(func(device: String) -> void: _marks.append(device))
	assert_bool(capture.open("USB Microphone")).is_false()
	assert_str(capture.error).contains("USB Microphone")
	assert_array(Array(_marks)).is_empty()
	assert_int(mic.opens).is_equal(0)


func test_a_device_without_a_usable_rate_does_not_open() -> void:
	var capture := _capture()
	var mic := capture.microphone as FakeMicrophone
	mic.rate = 0
	assert_bool(capture.open("Default")).is_false()
	assert_str(capture.error).contains("rate")
	assert_bool(mic.is_open).is_false()
	assert_bool(capture.is_settling()).is_false()


func test_a_closed_capture_reads_nothing() -> void:
	var capture := _capture()
	assert_array(capture.read(960)).is_empty()
	assert_int(capture.chunk_frames()).is_equal(0)


func test_the_test_tone_sets_no_mark_and_runs_in_real_time() -> void:
	var now := [1000000]
	var tone := VoiceToneMicrophone.new()
	tone.clock = func() -> int: return now[0] as int
	var capture := VoiceCapture.new()
	capture.microphone = tone
	capture.mark_changed.connect(func(device: String) -> void: _marks.append(device))
	assert_array(Array(capture.devices())).contains_exactly(["test tone"])
	assert_bool(capture.open("test tone")).is_true()
	assert_array(Array(_marks)).is_empty()
	assert_array(capture.read(960)).is_empty()
	now[0] += 50000
	var chunks := capture.read(960)
	assert_int(chunks.size()).is_equal(2)
	# Over the default voice-activity threshold at its lowest swell, under full scale.
	var peak := VoiceGate.peak_of(chunks[0].frames)
	assert_float(peak).is_greater(VoiceGate.DEFAULT_THRESHOLD)
	assert_float(peak).is_less(0.5)
	# After a long stall it skips ahead instead of bursting.
	now[0] += 5000000
	assert_int(capture.read(960).size()).is_equal(5)


func test_the_line_for_a_device_that_froze_names_it_and_22() -> void:
	var text := VoiceCapture.froze_text("Microphone Array")
	assert_str(text).contains("Microphone Array")
	assert_str(text).contains("#22")
	assert_str(text).contains("headset")


func _capture() -> VoiceCapture:
	var capture := VoiceCapture.new()
	capture.microphone = FakeMicrophone.new()
	return capture


func _note(device: String, mic: FakeMicrophone) -> void:
	_marks.append("%s (%s)" % [device, "open" if mic.is_open else "closed"])
