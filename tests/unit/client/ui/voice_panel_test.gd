extends GdUnitTestSuite
## The Esc menu's Voice tab (client/ui/voice_panel.gd; the M5 ADR §1.7, D11, D15): what it shows of
## VoiceControl's facts, the words it must say (unavailable without the addon, loudspeakers echo,
## the headset and #22 advice), its bounds (the threshold slider never reaches 0), and the signals
## a change sends. How it looks: `shot client/dev/esc_voice_preview.tscn`.

var _got: Array = []


func before_test() -> void:
	_got.clear()


func test_it_shows_the_microphones_the_mode_and_the_volumes() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	var shown := _shown()
	shown.device = "Headset Microphone"
	shown.mode = UserSettings.Mode.PUSH_TO_TALK
	shown.threshold = 0.3
	shown.peak = 0.2
	shown.denoise = false
	shown.volumes[AudioBuses.MUSIC] = -20.0
	panel.show_facts(shown)
	assert_bool(panel.unavailable_label.visible).is_false()
	assert_bool(panel.microphone_box.visible).is_true()
	# The Windows default first by that name, then each device; no Off entry (Off is a mode).
	var names := PackedStringArray()
	for i: int in panel.device_button.item_count:
		names.append(panel.device_button.get_item_text(i))
	assert_array(Array(names)).contains_exactly(
		["Windows default", "Headset Microphone", "Microphone Array"]
	)
	assert_str(panel.device_button.get_item_text(panel.device_button.selected)).is_equal(
		"Headset Microphone"
	)
	assert_int(panel.mode_button.get_selected_id()).is_equal(UserSettings.Mode.PUSH_TO_TALK)
	assert_float(panel.threshold_slider.value).is_equal_approx(0.3, 0.001)
	assert_float(panel.meter.value).is_equal_approx(0.2, 0.001)
	assert_bool(panel.denoise_check.button_pressed).is_false()
	assert_float(panel.volume_sliders[AudioBuses.MUSIC].value).is_equal(-20.0)
	assert_float(panel.volume_sliders[AudioBuses.EFFECTS].value).is_equal(-6.0)
	# Before any pick the Windows default shows as picked.
	shown.device = ""
	panel.show_facts(shown)
	assert_int(panel.device_button.selected).is_equal(0)


func test_the_modes_name_voice_activity_the_default_and_the_talk_key() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	assert_int(panel.mode_button.item_count).is_equal(3)
	assert_str(panel.mode_button.get_item_text(0)).contains("default")
	assert_str(panel.mode_button.get_item_text(1)).contains("V")
	assert_str(panel.mode_button.get_item_text(2)).starts_with("Off")
	assert_str(VoicePanel.talk_key()).is_equal("V")


func test_it_says_voice_is_unavailable_without_the_addon() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	var shown := _shown()
	shown.available = false
	shown.debug = true
	panel.show_facts(shown)
	assert_bool(panel.unavailable_label.visible).is_true()
	assert_str(panel.unavailable_label.text).contains("unavailable")
	assert_bool(panel.microphone_box.visible).is_false()
	assert_bool(panel.debug_box.visible).is_false()
	# The volumes still apply.
	assert_bool(panel.volume_sliders[AudioBuses.MASTER].is_visible_in_tree()).is_false()
	assert_bool((panel.volume_sliders[AudioBuses.MASTER].get_parent() as Control).visible).is_true()


func test_it_says_loudspeakers_echo_and_gives_the_headset_advice() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	assert_str(panel.echo_label.text).contains("headphones")
	assert_str(panel.echo_label.text).contains("loudspeakers")
	assert_str(panel.headset_label.text).contains("#22")
	assert_str(panel.headset_label.text).contains("headset")


func test_a_notice_shows_only_when_there_is_one() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	var shown := _shown()
	panel.show_facts(shown)
	assert_bool(panel.notice_label.visible).is_false()
	shown.notice = VoiceCapture.froze_text("Microphone Array")
	panel.show_facts(shown)
	assert_bool(panel.notice_label.visible).is_true()
	assert_str(panel.notice_label.text).contains("#22")


func test_the_threshold_slider_never_reaches_digital_silence() -> void:
	# The manager's review of PR #234 (item 4).
	var panel: VoicePanel = auto_free(VoicePanel.new())
	assert_float(panel.threshold_slider.min_value).is_equal(VoiceGate.MIN_THRESHOLD)
	assert_float(panel.threshold_slider.min_value).is_greater(0.0)
	panel.threshold_slider.value = 0.0
	assert_float(panel.threshold_slider.value).is_greater(0.0)
	assert_float(panel.volume_sliders[AudioBuses.VOICE].min_value).is_equal(UserSettings.MIN_DB)


func test_the_debug_tools_show_only_in_a_debug_build() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	var shown := _shown()
	panel.show_facts(shown)
	assert_bool(panel.debug_box.visible).is_false()
	shown.debug = true
	shown.tone = true
	panel.show_facts(shown)
	assert_bool(panel.debug_box.visible).is_true()
	assert_bool(panel.tone_check.button_pressed).is_true()
	assert_bool(panel.mute_check.button_pressed).is_false()


func test_each_change_sends_its_signal_and_showing_sends_none() -> void:
	var panel: VoicePanel = auto_free(VoicePanel.new())
	# A Range out of the tree sends no value_changed.
	add_child(panel)
	panel.device_picked.connect(func(device: String) -> void: _got.append(["device", device]))
	panel.mode_picked.connect(func(mode: UserSettings.Mode) -> void: _got.append(["mode", mode]))
	panel.threshold_changed.connect(func(value: float) -> void: _got.append(["threshold", value]))
	panel.denoise_toggled.connect(func(on: bool) -> void: _got.append(["denoise", on]))
	panel.volume_changed.connect(
		func(bus: StringName, db: float) -> void: _got.append(["volume", bus, db])
	)
	panel.tone_toggled.connect(func(on: bool) -> void: _got.append(["tone", on]))
	panel.mute_toggled.connect(func(on: bool) -> void: _got.append(["mute", on]))
	var shown := _shown()
	shown.debug = true
	panel.show_facts(shown)
	panel.show_facts(shown)
	assert_array(_got).is_empty()
	panel.device_button.item_selected.emit(2)
	panel.mode_button.item_selected.emit(2)
	panel.threshold_slider.value = 0.25
	panel.denoise_check.button_pressed = false
	panel.volume_sliders[AudioBuses.VOICE].value = -12.0
	panel.tone_check.button_pressed = true
	panel.mute_check.button_pressed = true
	(
		assert_array(_got)
		. is_equal(
			[
				["device", "Microphone Array"],
				["mode", UserSettings.Mode.OFF],
				["threshold", 0.25],
				["denoise", false],
				["volume", AudioBuses.VOICE, -12.0],
				["tone", true],
				["mute", true],
			]
		)
	)


func _shown() -> VoicePanel.Shown:
	var shown := VoicePanel.Shown.new()
	shown.available = true
	shown.devices = PackedStringArray(["Default", "Headset Microphone", "Microphone Array"])
	for bus: StringName in UserSettings.VOLUMES:
		shown.volumes[bus] = UserSettings.default_db(bus)
	return shown
