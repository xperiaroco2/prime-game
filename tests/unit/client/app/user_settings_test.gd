extends GdUnitTestSuite
## UserSettings (the M5 ADR §1.7, E43, E47 as amended): the defaults, a round trip through the file
## under user://, a damaged or partial file falling back to the defaults, the threshold kept above
## digital silence, and one file per window by PRIME_INSTANCE.

const PATH := "user://user_settings_test.cfg"


func after_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_the_defaults() -> void:
	var settings := UserSettings.new(PATH)
	assert_str(settings.device).is_empty()
	assert_int(settings.mode).is_equal(UserSettings.Mode.VOICE_ACTIVITY)
	assert_float(settings.threshold).is_equal(VoiceGate.DEFAULT_THRESHOLD)
	assert_bool(settings.denoise).is_true()
	assert_str(settings.opening).is_empty()
	# D15's four sliders at 0, 0, -6 and -14 dB (placeholders).
	var volumes: Array[float] = []
	for bus: StringName in UserSettings.VOLUMES:
		volumes.append(settings.volume_db(bus))
	assert_array(UserSettings.VOLUMES).contains_exactly([&"Master", &"Voice", &"Effects", &"Music"])
	assert_array(volumes).contains_exactly([0.0, 0.0, -6.0, -14.0])
	# No file yet: the defaults stay.
	assert_int(settings.read()).is_not_equal(OK)
	assert_int(settings.mode).is_equal(UserSettings.Mode.VOICE_ACTIVITY)


func test_a_round_trip_keeps_every_setting() -> void:
	var settings := UserSettings.new(PATH)
	settings.device = "Headset Microphone"
	settings.mode = UserSettings.Mode.PUSH_TO_TALK
	settings.threshold = 0.25
	settings.denoise = false
	settings.opening = "Microphone Array"
	settings.set_volume_db(&"Master", -3.0)
	settings.set_volume_db(&"Voice", -60.0)
	settings.set_volume_db(&"Effects", 2.5)
	settings.set_volume_db(&"Music", -20.0)
	assert_int(settings.write()).is_equal(OK)
	var back := UserSettings.new(PATH)
	assert_int(back.read()).is_equal(OK)
	assert_str(back.device).is_equal("Headset Microphone")
	assert_int(back.mode).is_equal(UserSettings.Mode.PUSH_TO_TALK)
	assert_float(back.threshold).is_equal_approx(0.25, 0.0001)
	assert_bool(back.denoise).is_false()
	assert_str(back.opening).is_equal("Microphone Array")
	assert_float(back.volume_db(&"Master")).is_equal(-3.0)
	assert_float(back.volume_db(&"Voice")).is_equal(-60.0)
	assert_float(back.volume_db(&"Effects")).is_equal(2.5)
	assert_float(back.volume_db(&"Music")).is_equal(-20.0)
	# Off round-trips too.
	back.mode = UserSettings.Mode.OFF
	back.opening = ""
	back.write()
	var again := UserSettings.new(PATH)
	again.read()
	assert_int(again.mode).is_equal(UserSettings.Mode.OFF)
	assert_str(again.opening).is_empty()


func test_a_damaged_or_partial_file_falls_back_to_the_defaults() -> void:
	var file := ConfigFile.new()
	file.set_value("voice", "mode", "shout")
	file.set_value("voice", "threshold", "loud")
	file.set_value("volume", "Music", 40.0)
	file.set_value("volume", "Voice", "x")
	file.save(PATH)
	var settings := UserSettings.new(PATH)
	assert_int(settings.read()).is_equal(OK)
	assert_int(settings.mode).is_equal(UserSettings.Mode.VOICE_ACTIVITY)
	assert_float(settings.threshold).is_equal(VoiceGate.DEFAULT_THRESHOLD)
	assert_bool(settings.denoise).is_true()
	assert_float(settings.volume_db(&"Music")).is_equal(UserSettings.MAX_DB)
	assert_float(settings.volume_db(&"Voice")).is_equal(0.0)
	assert_float(settings.volume_db(&"Effects")).is_equal(-6.0)


func test_settings_with_no_path_stay_in_memory() -> void:
	var settings := UserSettings.new()
	settings.mode = UserSettings.Mode.OFF
	assert_int(settings.write()).is_equal(OK)
	assert_int(settings.read()).is_equal(ERR_FILE_NOT_FOUND)
	assert_int(settings.mode).is_equal(UserSettings.Mode.OFF)


func test_a_missing_threshold_reads_back_the_default() -> void:
	var file := ConfigFile.new()
	file.set_value("voice", "mode", "push_to_talk")
	file.save(PATH)
	var settings := UserSettings.new(PATH)
	assert_int(settings.read()).is_equal(OK)
	assert_float(settings.threshold).is_equal(VoiceGate.DEFAULT_THRESHOLD)


func test_a_saved_threshold_outlives_a_change_of_the_default() -> void:
	# #286 moved only the default (0.1 to 0.05): a file saved at the old default keeps 0.1.
	# A default back at 0.1 would make this test check nothing: fail then instead.
	assert_bool(absf(VoiceGate.DEFAULT_THRESHOLD - 0.1) > 0.0001).is_true()
	var file := ConfigFile.new()
	file.set_value("voice", "threshold", 0.1)
	file.save(PATH)
	var settings := UserSettings.new(PATH)
	assert_int(settings.read()).is_equal(OK)
	assert_float(settings.threshold).is_equal_approx(0.1, 0.0001)


func test_the_threshold_never_reaches_digital_silence() -> void:
	# The manager's review of PR #234 (item 4): at or below 0 a silent player streams.
	var settings := UserSettings.new(PATH)
	settings.threshold = 0.0
	assert_float(settings.threshold).is_equal(VoiceGate.MIN_THRESHOLD)
	settings.threshold = -1.0
	assert_float(settings.threshold).is_equal(VoiceGate.MIN_THRESHOLD)
	var file := ConfigFile.new()
	file.set_value("voice", "threshold", 0.0)
	file.save(PATH)
	settings.read()
	assert_float(settings.threshold).is_equal(VoiceGate.MIN_THRESHOLD)


func test_the_volumes_stay_within_the_sliders() -> void:
	var settings := UserSettings.new(PATH)
	settings.set_volume_db(&"Voice", -200.0)
	assert_float(settings.volume_db(&"Voice")).is_equal(UserSettings.MIN_DB)
	settings.set_volume_db(&"Voice", NAN)
	assert_float(settings.volume_db(&"Voice")).is_equal(0.0)
	# A bus that is not a slider's is not kept.
	settings.set_volume_db(&"Other", -3.0)
	assert_float(settings.volume_db(&"Other")).is_equal(0.0)


func test_each_window_has_its_own_file() -> void:
	# E47 as amended: the runner's PRIME_INSTANCE, 1 the host, 2 and on the clients.
	assert_str(UserSettings.file_name("")).is_equal("settings.cfg")
	assert_str(UserSettings.file_name("1")).is_equal("settings.cfg")
	assert_str(UserSettings.file_name("2")).is_equal("settings_2.cfg")
	assert_str(UserSettings.file_name(" 3 ")).is_equal("settings_3.cfg")
	assert_str(UserSettings.file_name("0")).is_equal("settings.cfg")
	assert_str(UserSettings.file_name("two")).is_equal("settings.cfg")
	var own := UserSettings.for_this_window()
	var expected := UserSettings.file_name(OS.get_environment(UserSettings.INSTANCE_ENV))
	assert_str(own.path).is_equal("user://" + expected)
