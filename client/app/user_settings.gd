class_name UserSettings
extends RefCounted
## The player's own settings on this machine (the M5 ADR §1.7, E43 (a), E47 as amended): the
## microphone, the voice mode, the voice-activity threshold, RNNoise, the four volumes (D15),
## §1.1's "opening" mark, the interface language (#208), the player's own name (#550), large text,
## reduced motion and the window mode (Settings, #491), in a
## ConfigFile under user://, read at the start and written on each change. Only the name is ever
## sent (in Hello). Key bindings get their own file.
##
## The windows that `tools\run.cmd host --clients N` starts on one PC share one user:// folder, and
## the runner gives each its PRIME_INSTANCE (1 the host, 2 and on the clients): the file is
## settings.cfg when it is unset or 1 and settings_<n>.cfg otherwise, so three windows neither
## overwrite each other's choices nor read each other's mark.

## Voice activity is the default (D11, the engineer); push-to-talk is held on V; Off closes the own
## microphone only, the others stay audible (the Voice slider silences them; the design's reading,
## under "Needs the engineer").
enum Mode { VOICE_ACTIVITY, PUSH_TO_TALK, OFF }

const INSTANCE_ENV := "PRIME_INSTANCE"
## window_mode's values.
const WINDOW_FULLSCREEN := "fullscreen"
const WINDOW_WINDOWED := "windowed"
const FOLDER := "user://"
## How each mode is written, so a reordered enum reads an old file right.
const MODE_NAMES: Dictionary[Mode, String] = {
	Mode.VOICE_ACTIVITY: "voice_activity",
	Mode.PUSH_TO_TALK: "push_to_talk",
	Mode.OFF: "off",
}
## The volume sliders' range in dB (placeholders, "not a decision"); at MIN_DB a bus is muted, so
## the Voice slider silences the others.
const MIN_DB := -60.0
const MAX_DB := 6.0
## The four sliders' buses (D15) and their defaults in dB (placeholders, "not a decision"):
## Master, then AudioBuses' own.
const VOLUMES: Array[StringName] = [
	AudioBuses.MASTER, AudioBuses.VOICE, AudioBuses.EFFECTS, AudioBuses.MUSIC
]

## The file, under user://; "" keeps the settings in memory only (read() and write() touch no file).
var path := ""
## The microphone the player picked (VoiceMicrophone.DEFAULT_DEVICE for the Windows default), or ""
## before any pick: the Windows default opens then (E36 as amended).
var device := ""
var mode := Mode.VOICE_ACTIVITY
## The voice-activity threshold, a peak, kept within VoiceGate's bounds (never 0: a silent player
## would stream).
var threshold := VoiceGate.DEFAULT_THRESHOLD:
	set(value):
		threshold = VoiceGate.clamp_threshold(value)
## RNNoise, on by default (E37).
var denoise := true
## The device whose opening has not finished (the M5 ADR's §1.1); "" when none.
var opening := ""
## The interface language the player chose, one of Languages.ALL, or "" before any choice (then
## Languages.shown() follows the system's); any other value reads as "".
var language := "":
	set(value):
		language = value if Languages.ALL.has(value) else ""
## The player's own name (#550, the engineer's answers on #73), which Hello asks the host for, or
## "" before the player chose one (the host then names them Player<n>). Kept as PlayerNames.clean
## leaves it (at most 16 characters, no controls, no blank edges), so Hello always encodes; a value
## that cleans to nothing keeps the name there was: a chosen name is never empty. The main menu's
## name row (#493) and the Esc menu's Character tab (#491) set it.
var player_name := "":
	set(value):
		var cleaned := PlayerNames.clean(value)
		if not cleaned.is_empty():
			player_name = cleaned
## Settings > Accessibility (#491): the large-text theme, off by default.
var large_text := false
## Reduced motion as DisplayServer answers it: 1 on, 0 off, -1 before the player chose (UiPrefs
## follows the system's setting then).
var reduced_motion := -1:
	set(value):
		reduced_motion = value if value in [-1, 0, 1] else -1
## Settings > Display (#491): WINDOW_FULLSCREEN or WINDOW_WINDOWED, or "" before the player chose
## (the window keeps the mode it starts in); any other value reads as "".
var window_mode := "":
	set(value):
		window_mode = value if value in [WINDOW_FULLSCREEN, WINDOW_WINDOWED] else ""
## The Lobby tab's own preset (Save your own, #491): setting id -> a whole number or the ids of a
## set; empty before the host saved one. LobbyPresets keeps only what the mode declares.
var own_preset: Dictionary = {}

var _volumes: Dictionary[StringName, float] = {}


func _init(at := "") -> void:
	path = at
	for bus: StringName in VOLUMES:
		_volumes[bus] = default_db(bus)


## The settings file of this window: FOLDER + file_name(PRIME_INSTANCE), read if it exists.
static func for_this_window() -> UserSettings:
	var settings := UserSettings.new(FOLDER + file_name(OS.get_environment(INSTANCE_ENV)))
	settings.read()
	return settings


## settings.cfg for an unset, empty, invalid or first instance; settings_<n>.cfg for n > 1.
static func file_name(instance: String) -> String:
	var number := instance.strip_edges()
	if number.is_valid_int() and number.to_int() > 1:
		return "settings_%d.cfg" % number.to_int()
	return "settings.cfg"


## A bus's default volume in dB.
static func default_db(bus: StringName) -> float:
	return AudioBuses.DEFAULT_DB.get(bus, 0.0)


## The volume of `bus` (one of VOLUMES) in dB.
func volume_db(bus: StringName) -> float:
	return _volumes.get(bus, default_db(bus))


## Sets the volume of `bus` (one of VOLUMES), kept within MIN_DB and MAX_DB.
func set_volume_db(bus: StringName, db: float) -> void:
	if VOLUMES.has(bus):
		_volumes[bus] = default_db(bus) if is_nan(db) else clampf(db, MIN_DB, MAX_DB)


## Reads the file; a missing file keeps the defaults, and so does any value that is missing or
## out of place (an unknown mode or language, a threshold out of bounds is clamped).
func read() -> Error:
	if path.is_empty():
		return ERR_FILE_NOT_FOUND
	var file := ConfigFile.new()
	var code := file.load(path)
	if code != OK:
		return code
	device = str(file.get_value("voice", "device", ""))
	var mode_name := str(file.get_value("voice", "mode", MODE_NAMES[Mode.VOICE_ACTIVITY]))
	mode = Mode.VOICE_ACTIVITY
	for each: Mode in MODE_NAMES:
		if MODE_NAMES[each] == mode_name:
			mode = each
	threshold = _number(file.get_value("voice", "threshold", NAN), VoiceGate.DEFAULT_THRESHOLD)
	denoise = file.get_value("voice", "denoise", true) == true
	opening = str(file.get_value("voice", "opening", ""))
	language = str(file.get_value("interface", "language", ""))
	player_name = str(file.get_value("player", "name", ""))
	large_text = file.get_value("interface", "large_text", false) == true
	var motion: Variant = file.get_value("interface", "reduced_motion", -1)
	reduced_motion = motion as int if motion is int else -1
	window_mode = str(file.get_value("display", "window_mode", ""))
	var preset: Variant = file.get_value("lobby", "own_preset", {})
	own_preset = preset as Dictionary if preset is Dictionary else {}
	for bus: StringName in VOLUMES:
		set_volume_db(bus, _number(file.get_value("volume", String(bus), NAN), default_db(bus)))
	return OK


## Writes every setting to the file.
func write() -> Error:
	if path.is_empty():
		return OK
	var file := ConfigFile.new()
	file.set_value("voice", "device", device)
	file.set_value("voice", "mode", MODE_NAMES[mode])
	file.set_value("voice", "threshold", threshold)
	file.set_value("voice", "denoise", denoise)
	file.set_value("voice", "opening", opening)
	file.set_value("interface", "language", language)
	file.set_value("player", "name", player_name)
	file.set_value("interface", "large_text", large_text)
	file.set_value("interface", "reduced_motion", reduced_motion)
	file.set_value("display", "window_mode", window_mode)
	file.set_value("lobby", "own_preset", own_preset)
	for bus: StringName in VOLUMES:
		file.set_value("volume", String(bus), volume_db(bus))
	return file.save(path)


static func _number(value: Variant, fallback: float) -> float:
	if value is float:
		return value as float
	if value is int:
		return float(value as int)
	return fallback
