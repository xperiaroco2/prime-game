class_name VoiceControl
extends RefCounted
## The player's voice settings applied (the M5 ADR §1.1, §1.7, E36 as amended, E43, D11, D15):
## UserSettings to VoiceSender (which microphone is open, the mode, the threshold, RNNoise) and to
## the buses (the four volumes); the Esc menu's Voice tab changes them through here, and each
## change is written at once. The debug test tone and "mute this window" (E47) are never saved.
##
## Which microphone opens: none without the codec (voice unavailable), none in Off (Off closes
## only the own microphone; the others stay audible, the Voice slider silences them), none in a
## headless run (the Dummy driver captures nothing, and the runner's headless sessions must not
## write a mark); else the picked device, or the Windows default before any pick, so voice
## activity, the default, works without the menu. The "opening" mark: VoiceCapture names the
## device before it opens and this writes it to the settings file at once; a mark found at the
## start (`froze`) keeps the microphone closed, with VoiceCapture.froze_text(), until the player
## picks a microphone, even the same one.

## The test tone's device name (VoiceToneMicrophone).
const TONE := "test tone"

var settings: UserSettings
var sender: VoiceSender
## A real microphone may open here: not in a headless run.
var can_capture := DisplayServer.get_name() != "headless"
## The test tone and "mute this window" exist (debug builds only, E47).
var debug := OS.is_debug_build()
## Debug, never saved: the test tone speaks instead of the microphone; this window is muted.
var tone := false
var muted := false
## The device whose opening never finished at the last start: kept closed until a pick.
var froze := ""

var _microphone: VoiceMicrophone
var _tone := VoiceToneMicrophone.new()
var _devices := PackedStringArray()


func _init(with_settings: UserSettings, with_sender: VoiceSender) -> void:
	settings = with_settings
	sender = with_sender
	_microphone = sender.capture.microphone
	sender.capture.mark_changed.connect(_on_mark)


## At the start: the volumes, the gate as saved, a mark left by a frozen opening, then the
## microphone as the settings want it.
func start() -> void:
	froze = settings.opening
	sender.gate.threshold = settings.threshold
	sender.gate.set_mode(_gate_mode())
	apply_volumes()
	refresh_devices()
	apply_microphone()


## Whether this machine has the voice codec.
func available() -> bool:
	return sender.codec.available()


## The device that should be open now, or "" for none.
func wanted_device() -> String:
	if not available() or settings.mode == UserSettings.Mode.OFF:
		return ""
	if tone and debug:
		return TONE
	if not can_capture or not froze.is_empty():
		return ""
	return settings.device if not settings.device.is_empty() else VoiceMicrophone.DEFAULT_DEVICE


## Opens or closes the microphone as wanted_device() says; one already open as wanted stays.
func apply_microphone() -> void:
	var wanted := wanted_device()
	var source := _tone if wanted == TONE else _microphone
	if wanted.is_empty():
		sender.close()
		return
	if sender.is_open() and sender.capture.device == wanted and sender.capture.microphone == source:
		return
	sender.close()
	sender.capture.microphone = source
	sender.open(wanted, settings.denoise)


## The player picks a microphone (VoiceMicrophone.DEFAULT_DEVICE for the Windows default): saved,
## and opened even if its opening froze the game last time.
func pick_device(device: String) -> void:
	settings.device = device
	froze = ""
	settings.write()
	sender.close()
	apply_microphone()


func set_mode(mode: UserSettings.Mode) -> void:
	settings.mode = mode
	settings.write()
	sender.gate.set_mode(_gate_mode())
	apply_microphone()


## The voice-activity threshold, kept above digital silence.
func set_threshold(value: float) -> void:
	settings.threshold = value
	sender.gate.threshold = settings.threshold
	settings.write()


func set_denoise(on: bool) -> void:
	settings.denoise = on
	settings.write()
	if sender.is_open():
		sender.close()
	apply_microphone()


func set_volume(bus: StringName, db: float) -> void:
	settings.set_volume_db(bus, db)
	settings.write()
	apply_volume(bus)


## Debug builds only: the test tone instead of the microphone, not saved.
func set_tone(on: bool) -> void:
	if not debug:
		return
	tone = on
	apply_microphone()


## Debug builds only: this window silent (the Master bus muted), not saved.
func set_muted(on: bool) -> void:
	if not debug:
		return
	muted = on
	apply_volume(AudioBuses.MASTER)


func apply_volumes() -> void:
	for bus: StringName in UserSettings.VOLUMES:
		apply_volume(bus)


## Sets `bus`'s volume from the settings; at the slider's bottom, or Master while muted, the bus is
## muted.
func apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var db := settings.volume_db(bus)
	AudioServer.set_bus_volume_db(index, db)
	var mute := db <= UserSettings.MIN_DB or (bus == AudioBuses.MASTER and muted)
	AudioServer.set_bus_mute(index, mute)


## Reads the device list again (the Voice tab does when it opens): listing devices can be slow.
func refresh_devices() -> void:
	_devices = _microphone.devices() if available() else PackedStringArray()


## What the Voice tab shows now.
func facts() -> VoicePanel.Shown:
	var shown := VoicePanel.Shown.new()
	shown.available = available()
	shown.devices = PackedStringArray([VoiceMicrophone.DEFAULT_DEVICE])
	for device: String in _devices:
		if not shown.devices.has(device):
			shown.devices.append(device)
	if not settings.device.is_empty() and not shown.devices.has(settings.device):
		shown.devices.append(settings.device)
	shown.device = settings.device
	shown.mode = settings.mode
	shown.threshold = settings.threshold
	shown.peak = sender.peak if sender.is_open() else 0.0
	shown.denoise = settings.denoise
	for bus: StringName in UserSettings.VOLUMES:
		shown.volumes[bus] = settings.volume_db(bus)
	shown.debug = debug
	shown.tone = tone
	shown.muted = muted
	var notices := PackedStringArray()
	if shown.available and not froze.is_empty() and settings.mode != UserSettings.Mode.OFF:
		notices.append(VoiceCapture.froze_text(froze))
	if shown.available and not sender.error.is_empty() and not sender.is_open():
		notices.append(sender.error)
	shown.notice = "\n".join(notices)
	return shown


## The lobby's hint until a microphone is picked; "" once one is, or without voice.
func lobby_hint() -> String:
	if not available() or not settings.device.is_empty():
		return ""
	return VoicePanel.LOBBY_HINT


func _gate_mode() -> VoiceGate.Mode:
	if settings.mode == UserSettings.Mode.PUSH_TO_TALK:
		return VoiceGate.Mode.PUSH_TO_TALK
	return VoiceGate.Mode.VOICE_ACTIVITY


func _on_mark(device: String) -> void:
	settings.opening = device
	settings.write()
