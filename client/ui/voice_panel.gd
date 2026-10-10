class_name VoicePanel
extends VBoxContainer
## Settings › Sound and voice (the M5 ADR §1.7, D11, D15; the Toy look of #491, prime-game-ui
## handoff s05 `settings-sound` at ui-0.4.0): one in the Esc menu's Settings and one in the main
## menu's (#301), both a SettingsPage. The rows: Mic (the Windows default, then each device; no
## Off entry: Off is a mode), TalkMode (voice activation, the default; push to talk on the Talk
## key; off), Threshold (voice activation only) with MicTest's live meter of the microphone's
## peak, Noise (RNNoise, two chips) and the four volumes (Master, Voice, Effects, Music). Without
## the voice addon the microphone rows give way to `settings.voice_unavailable`. Beside the
## handoff (#491's differences): the line that loudspeakers echo and headphones avoid it, the
## headset and #22 advice, the device's notice, and in debug builds a test tone instead of the
## microphone and "mute this window", neither saved (E47); greybox English, as the deck has no
## keys for them. No talking indicator (D14): the meter shows the microphone's level, never
## whether the gate sends. The sliders keep the engine's units (the gate's peak, dB): no number
## is drawn. It shows a Shown (VoiceControl's) and says what changed through its signals.

signal device_picked(device: String)
signal mode_picked(mode: UserSettings.Mode)
signal threshold_changed(value: float)
signal denoise_toggled(on: bool)
signal volume_changed(bus: StringName, db: float)
signal tone_toggled(on: bool)
signal mute_toggled(on: bool)

## Greybox wording (#150): no deck key yet.
const ECHO := (
	"There is no echo cancellation: with loudspeakers your microphone sends the others' voices"
	+ " back to them. Wear headphones."
)
const HEADSET := (
	"A headset microphone works best. Godot 4.7.2 reads only mono or stereo microphones (#22): a"
	+ " laptop's microphone array can freeze the game. Prefer 48 kHz and turn off Windows' sound"
	+ " enhancements."
)
const LOBBY_HINT := "Voice: Esc, then Settings, to pick your microphone"
const DEFAULT_KEY := &"settings.mic.default"
const UNAVAILABLE_KEY := "settings.voice_unavailable"
## Each mode's deck key, in the dropdown's order.
const MODE_KEYS: Dictionary[UserSettings.Mode, StringName] = {
	UserSettings.Mode.VOICE_ACTIVITY: &"settings.talk_mode.open",
	UserSettings.Mode.PUSH_TO_TALK: &"settings.talk_mode.push",
	UserSettings.Mode.OFF: &"common.off",
}
## Each bus's row: its node name and its deck key.
const VOLUME_ROWS: Dictionary[StringName, Array] = {
	AudioBuses.MASTER: ["Overall", "settings.game_volume"],
	AudioBuses.VOICE: ["Voices", "settings.voice_volume"],
	AudioBuses.EFFECTS: ["Effects", "settings.effects_volume"],
	AudioBuses.MUSIC: ["Music", "settings.music_volume"],
}
const THRESHOLD_STEP := 0.005
const VOLUME_STEP := 1.0
## The meter's size (the handoff's MicTest: 500 x 10).
const METER_SIZE := Vector2(500, 10)


## What the page shows.
class Shown:
	extends RefCounted
	## The voice codec is there.
	var available := false
	## The microphones, VoiceMicrophone.DEFAULT_DEVICE first.
	var devices := PackedStringArray()
	## The picked one; "" before any pick (the Windows default then).
	var device := ""
	var mode := UserSettings.Mode.VOICE_ACTIVITY
	var threshold := VoiceGate.DEFAULT_THRESHOLD
	## The microphone's latest peak (0 while closed).
	var peak := 0.0
	var denoise := true
	## Bus -> dB, for UserSettings.VOLUMES.
	var volumes: Dictionary[StringName, float] = {}
	## An error or the #22 line for a device that froze the game; "" for none.
	var notice := ""
	var debug := false
	var tone := false
	var muted := false


var unavailable_label := SettingRows.note(UNAVAILABLE_KEY)
var notice_label := SettingRows.note("")
var device_button := SettingRows.dropdown("Device")
var mode_button := SettingRows.dropdown("Mode")
var threshold_slider := SettingRows.slider(
	VoiceGate.MIN_THRESHOLD, VoiceGate.MAX_THRESHOLD, THRESHOLD_STEP
)
var meter := ProgressBar.new()
## Noise suppression: the Off and On chips (one ButtonGroup).
var denoise_chips: HBoxContainer
var volume_sliders: Dictionary[StringName, HSlider] = {}
var mic_row: PanelContainer
var mode_row: PanelContainer
var threshold_row: PanelContainer
var test_row: PanelContainer
var echo_label := SettingRows.note(ECHO)
var headset_label := SettingRows.note(HEADSET)
var debug_box := VBoxContainer.new()
var tone_chip := UiParts.toggle("common.on", Callable(), &"ToyChipToggleOnLight")
var mute_chip := UiParts.toggle("common.on", Callable(), &"ToyChipToggleOnLight")

var _devices := PackedStringArray()
var _mode := UserSettings.Mode.VOICE_ACTIVITY


func _init() -> void:
	name = "Sound"
	theme_type_variation = &"ToyColumnEight"
	add_child(unavailable_label)
	add_child(notice_label)
	# Choosing the item already shown counts: the Windows default before any pick, or a device
	# whose opening froze the game, is picked by choosing it again.
	device_button.allow_reselect = true
	device_button.item_selected.connect(_on_device)
	mic_row = SettingRows.row("Mic", "settings.mic", device_button)
	add_child(mic_row)
	for mode: UserSettings.Mode in MODE_KEYS:
		mode_button.add_item("", mode)
	mode_button.item_selected.connect(_on_mode)
	mode_row = SettingRows.row("TalkMode", "settings.talk_mode", mode_button)
	add_child(mode_row)
	threshold_slider.value_changed.connect(
		func(value: float) -> void: threshold_changed.emit(value)
	)
	threshold_row = SettingRows.row("Threshold", "settings.voice_threshold", threshold_slider)
	add_child(threshold_row)
	meter.name = "Meter"
	meter.theme_type_variation = &"ToyBarSlider"
	meter.custom_minimum_size = METER_SIZE
	meter.min_value = 0.0
	meter.max_value = 1.0
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	test_row = SettingRows.row("MicTest", "settings.mic_test", meter)
	add_child(test_row)
	add_child(echo_label)
	add_child(headset_label)
	var noise_keys: Dictionary[String, String] = {"Off": "common.off", "On": "common.on"}
	denoise_chips = SettingRows.chips("Toggle", noise_keys, _on_denoise)
	add_child(SettingRows.row("Noise", "settings.noise_suppression", denoise_chips))
	for bus: StringName in UserSettings.VOLUMES:
		var slider := SettingRows.slider(UserSettings.MIN_DB, UserSettings.MAX_DB, VOLUME_STEP)
		slider.value_changed.connect(func(db: float) -> void: volume_changed.emit(bus, db))
		volume_sliders[bus] = slider
		var names: Array = VOLUME_ROWS[bus]
		add_child(SettingRows.row(str(names[0]), str(names[1]), slider))
	debug_box.name = "Debug"
	debug_box.theme_type_variation = &"ToyColumnEight"
	tone_chip.name = "Tone"
	tone_chip.toggled.connect(func(on: bool) -> void: tone_toggled.emit(on))
	debug_box.add_child(SettingRows.row("Tone", "Test tone, not the microphone (debug)", tone_chip))
	mute_chip.name = "Mute"
	mute_chip.toggled.connect(func(on: bool) -> void: mute_toggled.emit(on))
	debug_box.add_child(SettingRows.row("Mute", "Mute this window (debug)", mute_chip))
	add_child(debug_box)
	_retext()


## Shows `facts`; a control the player is not moving takes its value without a signal.
func show_facts(facts: Shown) -> void:
	unavailable_label.visible = not facts.available
	for each: Control in [mic_row, mode_row, test_row, echo_label, headset_label]:
		each.visible = facts.available
	threshold_row.visible = facts.available and facts.mode == UserSettings.Mode.VOICE_ACTIVITY
	notice_label.text = facts.notice
	notice_label.visible = not facts.notice.is_empty()
	if facts.devices != _devices:
		_devices = facts.devices.duplicate()
		_list_devices()
	var picked := facts.device if not facts.device.is_empty() else VoiceMicrophone.DEFAULT_DEVICE
	device_button.select(_devices.find(picked))
	_mode = facts.mode
	mode_button.select(mode_button.get_item_index(facts.mode))
	threshold_slider.set_value_no_signal(facts.threshold)
	meter.value = facts.peak
	SettingRows.show_chip(denoise_chips, "On" if facts.denoise else "Off")
	for bus: StringName in volume_sliders:
		volume_sliders[bus].set_value_no_signal(
			facts.volumes.get(bus, UserSettings.default_db(bus)) as float
		)
	debug_box.visible = facts.debug and facts.available
	SettingRows.set_pressed(tone_chip, facts.tone)
	SettingRows.set_pressed(mute_chip, facts.muted)


## Whether noise suppression shows on.
func denoise_on() -> bool:
	return (denoise_chips.get_node(^"On") as Button).button_pressed


## A device's name in the list: the Windows default by the deck's word.
static func device_name(device: String) -> String:
	return KeyLabel.word(DEFAULT_KEY) if device == VoiceMicrophone.DEFAULT_DEVICE else device


## The talk key's name, from the input map (V by default, D11; rebindable, #211); "?" unbound.
static func talk_key() -> String:
	var label := KeyLabel.of_action(VoiceSender.TALK_ACTION)
	return label if not label.is_empty() else "?"


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and mode_button != null:
		_retext()


## The dropdowns' words in the current language (their items are set from code).
func _retext() -> void:
	for mode: UserSettings.Mode in MODE_KEYS:
		mode_button.set_item_text(mode_button.get_item_index(mode), KeyLabel.word(MODE_KEYS[mode]))
	_list_devices()


func _list_devices() -> void:
	var selected := device_button.selected
	device_button.clear()
	for device: String in _devices:
		device_button.add_item(device_name(device))
	device_button.select(selected if selected < _devices.size() else -1)


func _on_device(index: int) -> void:
	if index >= 0 and index < _devices.size():
		device_picked.emit(_devices[index])


func _on_mode(index: int) -> void:
	_mode = mode_button.get_item_id(index) as UserSettings.Mode
	threshold_row.visible = mic_row.visible and _mode == UserSettings.Mode.VOICE_ACTIVITY
	mode_picked.emit(_mode)


func _on_denoise(chip: String) -> void:
	denoise_toggled.emit(chip == "On")
