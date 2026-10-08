class_name VoicePanel
extends VBoxContainer
## The Esc menu's Voice tab (the M5 ADR §1.7, D11, D15; in every screen with the Esc menu): the
## microphone (the Windows default, then each device; no Off entry: Off is a mode), the mode (voice
## activity, the default; push-to-talk with its key; Off), the voice-activity threshold with a live
## meter of the microphone's peak, RNNoise, the four volume sliders (Master, Voice, Effects, Music),
## the line that loudspeakers echo and headphones avoid it, the headset and #22 advice, and, without
## the voice addon, the line that voice is unavailable. In debug builds a test tone instead of the
## microphone and "mute this window", neither saved (E47). No talking indicator (D14): the meter
## shows the microphone's level, never whether the gate sends. It shows a Shown (VoiceControl's) and
## says what changed through its signals; built in code with the shared greybox theme only (#150).

signal device_picked(device: String)
signal mode_picked(mode: UserSettings.Mode)
signal threshold_changed(value: float)
signal denoise_toggled(on: bool)
signal volume_changed(bus: StringName, db: float)
signal tone_toggled(on: bool)
signal mute_toggled(on: bool)

## Greybox wording (#150).
const UNAVAILABLE := (
	"Voice is unavailable: the voice addon (TwoVoIP) is not installed. The game runs without"
	+ " voice; the volumes below still apply."
)
const ECHO := (
	"There is no echo cancellation: with loudspeakers your microphone sends the others' voices"
	+ " back to them. Wear headphones."
)
const HEADSET := (
	"A headset microphone works best. Godot 4.7.2 reads only mono or stereo microphones (#22): a"
	+ " laptop's microphone array can freeze the game. Prefer 48 kHz and turn off Windows' sound"
	+ " enhancements."
)
const LOBBY_HINT := "Voice: Esc, then Voice, to pick your microphone"
const DEFAULT_NAME := "Windows default"
const MODE_NAMES: Dictionary[UserSettings.Mode, String] = {
	UserSettings.Mode.VOICE_ACTIVITY: "Voice activity (the default)",
	UserSettings.Mode.PUSH_TO_TALK: "Push-to-talk: hold %s",
	UserSettings.Mode.OFF: "Off: your microphone is closed",
}
const VOLUME_NAMES: Dictionary[StringName, String] = {
	AudioBuses.MASTER: "Master",
	AudioBuses.VOICE: "Voice",
	AudioBuses.EFFECTS: "Effects",
	AudioBuses.MUSIC: "Music",
}
const THRESHOLD_STEP := 0.005
const VOLUME_STEP := 1.0


## What the tab shows.
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


var unavailable_label := _text(UNAVAILABLE)
var notice_label := _text("")
var microphone_box := VBoxContainer.new()
var device_button := OptionButton.new()
var mode_button := OptionButton.new()
var threshold_slider := HSlider.new()
var meter := ProgressBar.new()
var denoise_check := CheckBox.new()
var volume_sliders: Dictionary[StringName, HSlider] = {}
var echo_label := _text(ECHO)
var headset_label := _text(HEADSET)
var debug_box := VBoxContainer.new()
var tone_check := CheckBox.new()
var mute_check := CheckBox.new()

var _devices := PackedStringArray()


func _init() -> void:
	name = "VoicePanel"
	theme_type_variation = &"EscPage"
	add_child(unavailable_label)
	notice_label.theme_type_variation = &"Shortfalls"
	add_child(notice_label)
	add_child(microphone_box)
	# Choosing the item already shown counts: the Windows default before any pick, or a device
	# whose opening froze the game, is picked by choosing it again.
	device_button.allow_reselect = true
	device_button.item_selected.connect(_on_device)
	microphone_box.add_child(UiParts.labelled("Microphone", device_button))
	for mode: UserSettings.Mode in MODE_NAMES:
		mode_button.add_item(_mode_name(mode), mode)
	mode_button.item_selected.connect(_on_mode)
	microphone_box.add_child(UiParts.labelled("Mode", mode_button))
	threshold_slider.min_value = VoiceGate.MIN_THRESHOLD
	threshold_slider.max_value = VoiceGate.MAX_THRESHOLD
	threshold_slider.step = THRESHOLD_STEP
	threshold_slider.value_changed.connect(
		func(value: float) -> void: threshold_changed.emit(value)
	)
	microphone_box.add_child(UiParts.labelled("Voice activity at", threshold_slider))
	meter.min_value = 0.0
	meter.max_value = 1.0
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	microphone_box.add_child(UiParts.labelled("Microphone level", meter))
	denoise_check.text = "Noise suppression (RNNoise)"
	denoise_check.toggled.connect(func(on: bool) -> void: denoise_toggled.emit(on))
	microphone_box.add_child(denoise_check)
	microphone_box.add_child(echo_label)
	microphone_box.add_child(headset_label)
	add_child(UiParts.heading("Volume"))
	for bus: StringName in UserSettings.VOLUMES:
		var slider := HSlider.new()
		slider.min_value = UserSettings.MIN_DB
		slider.max_value = UserSettings.MAX_DB
		slider.step = VOLUME_STEP
		slider.value_changed.connect(func(db: float) -> void: volume_changed.emit(bus, db))
		volume_sliders[bus] = slider
		add_child(UiParts.labelled(VOLUME_NAMES[bus], slider))
	tone_check.text = "Test tone instead of the microphone (debug, not saved)"
	tone_check.toggled.connect(func(on: bool) -> void: tone_toggled.emit(on))
	debug_box.add_child(tone_check)
	mute_check.text = "Mute this window (debug, not saved)"
	mute_check.toggled.connect(func(on: bool) -> void: mute_toggled.emit(on))
	debug_box.add_child(mute_check)
	add_child(debug_box)


## Shows `facts`; a control the player is not moving takes its value without a signal.
func show_facts(facts: Shown) -> void:
	unavailable_label.visible = not facts.available
	microphone_box.visible = facts.available
	notice_label.text = facts.notice
	notice_label.visible = not facts.notice.is_empty()
	if facts.devices != _devices:
		_devices = facts.devices.duplicate()
		device_button.clear()
		for device: String in _devices:
			device_button.add_item(device_name(device))
	var picked := facts.device if not facts.device.is_empty() else VoiceMicrophone.DEFAULT_DEVICE
	device_button.select(_devices.find(picked))
	# The talk key follows a rebind in the Controls tab (#211).
	var talk := mode_button.get_item_index(UserSettings.Mode.PUSH_TO_TALK)
	mode_button.set_item_text(talk, _mode_name(UserSettings.Mode.PUSH_TO_TALK))
	mode_button.select(mode_button.get_item_index(facts.mode))
	threshold_slider.set_value_no_signal(facts.threshold)
	meter.value = facts.peak
	denoise_check.set_pressed_no_signal(facts.denoise)
	for bus: StringName in volume_sliders:
		volume_sliders[bus].set_value_no_signal(
			facts.volumes.get(bus, UserSettings.default_db(bus)) as float
		)
	debug_box.visible = facts.debug and facts.available
	tone_check.set_pressed_no_signal(facts.tone)
	mute_check.set_pressed_no_signal(facts.muted)


## A device's name in the list: the Windows default by that name.
static func device_name(device: String) -> String:
	return DEFAULT_NAME if device == VoiceMicrophone.DEFAULT_DEVICE else device


## The talk key's name, from the input map (V by default, D11; rebindable, #211); "?" unbound.
static func talk_key() -> String:
	var label := KeyLabel.of_action(VoiceSender.TALK_ACTION)
	return label if not label.is_empty() else "?"


static func _mode_name(mode: UserSettings.Mode) -> String:
	var words := MODE_NAMES[mode]
	return words % talk_key() if mode == UserSettings.Mode.PUSH_TO_TALK else words


func _on_device(index: int) -> void:
	if index >= 0 and index < _devices.size():
		device_picked.emit(_devices[index])


func _on_mode(index: int) -> void:
	mode_picked.emit(mode_button.get_item_id(index) as UserSettings.Mode)


static func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
