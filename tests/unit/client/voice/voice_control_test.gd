extends GdUnitTestSuite
## VoiceControl (the M5 ADR §1.1, §1.7, E36 as amended, D11, D15): the settings applied to the
## sender and the buses. The Windows default opens at the first start under the "opening" mark,
## written before it opens and cleared after its first second; a mark left by a frozen start keeps
## the microphone closed, with the #22 line, until a pick; Off closes only the own microphone;
## nothing opens without the codec or in a headless run; the threshold stays above silence; the
## volumes mute at the slider's bottom; the debug tone and "mute this window" are never saved.
## Through FakeMicrophone and the fake codec; the settings in a file of its own under user://.

const PATH := "user://voice_control_test.cfg"

## The mark as the file held it each time the fake microphone opened.
var _mark_at_open: PackedStringArray


func before_test() -> void:
	_mark_at_open = PackedStringArray()
	AudioBuses.ensure()


func after_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	for bus: StringName in UserSettings.VOLUMES:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, UserSettings.default_db(bus))
		AudioServer.set_bus_mute(index, false)


func test_the_first_start_opens_the_windows_default_under_the_mark() -> void:
	var control := _control(UserSettings.new(PATH))
	var mic := _mic(control)
	control.start()
	assert_bool(control.sender.is_open()).is_true()
	assert_str(mic.opened_device).is_equal(VoiceMicrophone.DEFAULT_DEVICE)
	# The mark was in the file before the device opened.
	assert_array(Array(_mark_at_open)).contains_exactly([VoiceMicrophone.DEFAULT_DEVICE])
	assert_str(_saved().opening).is_equal(VoiceMicrophone.DEFAULT_DEVICE)
	# A second of samples: the opening finished, the mark is cleared in the file.
	mic.capture_chunks(50, 0.0)
	control.sender.step()
	assert_str(_saved().opening).is_empty()
	assert_str(control.settings.opening).is_empty()


func test_a_mark_left_by_a_frozen_start_keeps_the_microphone_closed_until_a_pick() -> void:
	var settings := UserSettings.new(PATH)
	settings.opening = "Microphone Array"
	settings.device = "Microphone Array"
	var control := _control(settings)
	var mic := _mic(control)
	control.start()
	assert_bool(control.sender.is_open()).is_false()
	assert_int(mic.opens).is_equal(0)
	assert_str(control.facts().notice).contains("Microphone Array")
	assert_str(control.facts().notice).contains("#22")
	# Still marked: the next start stays closed too.
	var again := _control(settings)
	_mic(again)
	again.start()
	assert_bool(again.sender.is_open()).is_false()
	# Picking a microphone, even the same one, opens it under a fresh mark.
	control.pick_device("Microphone Array")
	assert_bool(control.sender.is_open()).is_true()
	assert_array(Array(_mark_at_open)).contains_exactly(["Microphone Array"])
	assert_str(control.facts().notice).is_empty()
	assert_str(_saved().device).is_equal("Microphone Array")


func test_a_pick_that_opens_nothing_still_clears_the_mark() -> void:
	var settings := UserSettings.new(PATH)
	settings.opening = "Microphone Array"
	settings.mode = UserSettings.Mode.OFF
	var control := _control(settings)
	var mic := _mic(control)
	control.start()
	control.pick_device("Headset Microphone")
	assert_int(mic.opens).is_equal(0)
	assert_str(_saved().opening).is_empty()
	# The next start opens the pick once voice is on again.
	var again := _control(_saved())
	var again_mic := _mic(again)
	again.start()
	again.set_mode(UserSettings.Mode.VOICE_ACTIVITY)
	assert_str(again_mic.opened_device).is_equal("Headset Microphone")


func test_off_closes_only_the_own_microphone_and_is_saved() -> void:
	var control := _control(UserSettings.new(PATH))
	var mic := _mic(control)
	control.start()
	control.set_mode(UserSettings.Mode.OFF)
	assert_bool(control.sender.is_open()).is_false()
	assert_bool(mic.is_open).is_false()
	assert_int(_saved().mode).is_equal(UserSettings.Mode.OFF)
	# The others stay audible: Off touches no bus.
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.VOICE))).is_false()
	control.set_mode(UserSettings.Mode.PUSH_TO_TALK)
	assert_bool(control.sender.is_open()).is_true()
	assert_int(control.sender.gate.mode).is_equal(VoiceGate.Mode.PUSH_TO_TALK)
	control.set_mode(UserSettings.Mode.VOICE_ACTIVITY)
	assert_int(control.sender.gate.mode).is_equal(VoiceGate.Mode.VOICE_ACTIVITY)


func test_nothing_opens_without_the_codec_and_the_tab_says_so() -> void:
	var control := _control(UserSettings.new(PATH))
	var mic := _mic(control)
	(control.sender.codec as FakeVoiceCodec).is_available = false
	control.start()
	assert_int(mic.opens).is_equal(0)
	assert_bool(control.facts().available).is_false()
	assert_str(control.lobby_hint()).is_empty()
	control.pick_device("Headset Microphone")
	assert_int(mic.opens).is_equal(0)


func test_a_headless_run_opens_no_microphone_and_writes_no_mark() -> void:
	var control := _control(UserSettings.new(PATH))
	var mic := _mic(control)
	control.can_capture = false
	control.start()
	assert_int(mic.opens).is_equal(0)
	assert_bool(FileAccess.file_exists(PATH)).is_false()


func test_the_threshold_is_kept_above_digital_silence_and_saved() -> void:
	var control := _control(UserSettings.new(PATH))
	_mic(control)
	control.start()
	control.set_threshold(0.0)
	assert_float(control.sender.gate.threshold).is_equal(VoiceGate.MIN_THRESHOLD)
	assert_float(_saved().threshold).is_equal(VoiceGate.MIN_THRESHOLD)
	control.set_threshold(0.3)
	assert_float(control.sender.gate.threshold).is_equal_approx(0.3, 0.0001)


func test_the_saved_gate_and_volumes_apply_at_the_start() -> void:
	var settings := UserSettings.new(PATH)
	settings.mode = UserSettings.Mode.PUSH_TO_TALK
	settings.threshold = 0.4
	settings.set_volume_db(AudioBuses.MUSIC, -20.0)
	var control := _control(settings)
	_mic(control)
	control.start()
	assert_int(control.sender.gate.mode).is_equal(VoiceGate.Mode.PUSH_TO_TALK)
	assert_float(control.sender.gate.threshold).is_equal_approx(0.4, 0.0001)
	assert_float(AudioServer.get_bus_volume_db(AudioBuses.index_of(AudioBuses.MUSIC))).is_equal(
		-20.0
	)


func test_a_volume_at_the_bottom_mutes_its_bus() -> void:
	var control := _control(UserSettings.new(PATH))
	_mic(control)
	control.start()
	var voice := AudioBuses.index_of(AudioBuses.VOICE)
	control.set_volume(AudioBuses.VOICE, UserSettings.MIN_DB)
	assert_bool(AudioServer.is_bus_mute(voice)).is_true()
	control.set_volume(AudioBuses.VOICE, -10.0)
	assert_bool(AudioServer.is_bus_mute(voice)).is_false()
	assert_float(AudioServer.get_bus_volume_db(voice)).is_equal(-10.0)
	assert_float(_saved().volume_db(AudioBuses.VOICE)).is_equal(-10.0)


func test_mute_this_window_and_the_test_tone_are_debug_only_and_never_saved() -> void:
	var control := _control(UserSettings.new(PATH))
	var mic := _mic(control)
	control.debug = true
	control.start()
	control.set_muted(true)
	assert_bool(AudioServer.is_bus_mute(AudioBuses.index_of(AudioBuses.MASTER))).is_true()
	control.set_tone(true)
	assert_str(control.sender.capture.device).is_equal(VoiceControl.TONE)
	assert_bool(control.sender.capture.microphone is VoiceToneMicrophone).is_true()
	assert_bool(mic.is_open).is_false()
	control.set_volume(AudioBuses.EFFECTS, -8.0)
	var file := ConfigFile.new()
	file.load(PATH)
	for key: String in file.get_section_keys("voice"):
		assert_str(key).is_not_equal("tone")
		assert_str(key).is_not_equal("muted")
	control.set_tone(false)
	control.set_muted(false)
	assert_bool(control.sender.capture.microphone == mic).is_true()
	assert_bool(mic.is_open).is_true()
	assert_bool(AudioServer.is_bus_mute(AudioBuses.index_of(AudioBuses.MASTER))).is_false()
	# A release build has neither.
	control.debug = false
	control.set_tone(true)
	control.set_muted(true)
	assert_bool(control.tone or control.muted).is_false()


func test_the_lobby_hint_shows_until_a_microphone_is_picked() -> void:
	var control := _control(UserSettings.new(PATH))
	_mic(control)
	control.start()
	assert_str(control.lobby_hint()).is_equal(VoicePanel.LOBBY_HINT)
	control.pick_device(VoiceMicrophone.DEFAULT_DEVICE)
	assert_str(control.lobby_hint()).is_empty()


func test_rnnoise_off_reopens_the_encoder_without_it() -> void:
	var control := _control(UserSettings.new(PATH))
	_mic(control)
	control.start()
	assert_bool((control.sender.encoder() as FakeVoiceEncoder).denoise).is_true()
	control.set_denoise(false)
	assert_bool(control.sender.is_open()).is_true()
	assert_bool((control.sender.encoder() as FakeVoiceEncoder).denoise).is_false()
	assert_bool(_saved().denoise).is_false()


func test_the_tab_lists_the_windows_default_first_and_a_failed_device_says_why() -> void:
	var control := _control(UserSettings.new(PATH))
	var mic := _mic(control)
	mic.names = PackedStringArray(["Headset Microphone", "Default"])
	control.start()
	var shown := control.facts()
	assert_array(Array(shown.devices)).contains_exactly(["Default", "Headset Microphone"])
	assert_str(shown.device).is_empty()
	mic.names = PackedStringArray(["Default"])
	control.pick_device("Headset Microphone")
	assert_bool(control.sender.is_open()).is_false()
	shown = control.facts()
	assert_str(shown.notice).contains("Headset Microphone")
	# The picked device stays listed, so the tab shows what is picked.
	assert_bool(shown.devices.has("Headset Microphone")).is_true()


func _control(settings: UserSettings) -> VoiceControl:
	var sender: VoiceSender = auto_free(VoiceSender.new())
	sender.capture.microphone = FakeMicrophone.new()
	sender.codec = FakeVoiceCodec.new()
	sender.reads_device_input = false
	var control := VoiceControl.new(settings, sender)
	control.can_capture = true
	control.debug = false
	return control


func _mic(control: VoiceControl) -> FakeMicrophone:
	var mic := control.sender.capture.microphone as FakeMicrophone
	mic.on_open = func() -> void: _mark_at_open.append(_saved().opening)
	return mic


func _saved() -> UserSettings:
	var settings := UserSettings.new(PATH)
	settings.read()
	return settings
