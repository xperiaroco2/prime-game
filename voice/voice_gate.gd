class_name VoiceGate
extends RefCounted
## Which encoded frames leave (E37, D11, the M5 ADR §1.2). The microphone's every 20 ms chunk is
## encoded, so the codec's and the denoiser's state stay continuous, and feed() gets each chunk
## with its frame and says which frames to send now. Nothing leaves in silence: a silent player's
## steady stream would show where they stand.
## - Voice activity (the default, D11): open while the chunk's peak is over `threshold`, and for a
##   hangover of HANGOVER_MS after it falls below.
## - Push-to-talk: open while the talk key is held (`talk_held`; client/ reads the key).
## - Pre-roll: when the gate opens, the PREROLL frames before go out first, oldest first, so the
##   first syllable is not cut: with the current frame at most 3 in one send, under the relay's
##   newest 5 per poll. The ring holds only frames never sent (it fills only while closed), so a
##   gate closed for one chunk and reopened sends no frame twice: the relay renumbers what it
##   relays, and the listener could not tell a resent frame from a new one.
## - `may_speak` (client/ decides it: false while the own player is downed or dead and in a phase
##   whose voice rule hears nobody) closes the gate and empties the pre-roll ring while false, so
##   the ring only ever holds frames captured while the player could be heard: a downed player
##   whispering with the key held while being raised sends nothing of it when the revive lands.
## Off (no microphone) is the capture's state (M5-6), not a mode here. Pure: the level is the raw
## chunk's peak, computed here, so a test feeds it silence and a sine; voice/ reads no game state.

enum Mode { VOICE_ACTIVITY, PUSH_TO_TALK }

const FRAME_MS := 20
## The hangover after the peak falls below the threshold: a placeholder, "not a decision".
const HANGOVER_MS := 300
## HANGOVER_MS in frames.
const HANGOVER_FRAMES := 15
## Frames sent before the one that opens the gate.
const PREROLL := 2
## The default voice-activity threshold, a peak of 0.1 (about -20 dBFS): a placeholder, "not a
## decision"; the Voice tab's slider sets it (M5-6).
const DEFAULT_THRESHOLD := 0.1
## The lowest threshold, a peak of 0.01 (-40 dBFS; a placeholder, "not a decision"): at or below 0
## the gate would open on digital silence, and a silent player would stream where they stand.
const MIN_THRESHOLD := 0.01
## The highest threshold: a full-scale peak.
const MAX_THRESHOLD := 1.0

var mode := Mode.VOICE_ACTIVITY
## The peak over which voice activity opens the gate, in sample units, kept within MIN_THRESHOLD
## and MAX_THRESHOLD.
var threshold := DEFAULT_THRESHOLD:
	set(value):
		threshold = clamp_threshold(value)
## The latest chunk's peak, for the Voice tab's meter.
var last_peak := 0.0

var _open := false
var _hangover := 0
## The newest frames captured while the gate was closed and the player could be heard.
var _ring: Array[PackedByteArray] = []


## The frames to send for this chunk, oldest first: empty while closed, the pre-roll and `frame`
## when the gate opens, `frame` while it stays open. `chunk` is the raw microphone chunk `frame`
## was encoded from. An empty `frame` (VoiceEncoder.encode failed) is never sent nor kept for the
## pre-roll; its chunk still counts for the gate and the hangover, and a gate it would open opens
## with the next frame. While the gate is closed it empties the ring: the frames before an outage
## are stale and never go out as pre-roll.
func feed(
	chunk: PackedVector2Array, frame: PackedByteArray, may_speak: bool, talk_held: bool
) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	last_peak = peak_of(chunk)
	if not may_speak:
		_open = false
		_hangover = 0
		_ring.clear()
		return out
	var wants := _wants_open(talk_held)
	if frame.is_empty():
		_open = _open and wants
		if not _open:
			# An outage: what the ring holds is from before it and never goes out as pre-roll.
			_ring.clear()
		return out
	if not wants:
		_open = false
		_ring.append(frame)
		if _ring.size() > PREROLL:
			_ring.pop_front()
		return out
	if not _open:
		_open = true
		out.append_array(_ring)
		_ring.clear()
	out.append(frame)
	return out


## Whether the gate is open: the last feed() sent its frame, unless that frame was empty.
func is_open() -> bool:
	return _open


## Switches the mode; the gate closes, the hangover ends, the pre-roll stays.
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_open = false
	_hangover = 0


## `value` within MIN_THRESHOLD and MAX_THRESHOLD; NaN gives the default.
static func clamp_threshold(value: float) -> float:
	if is_nan(value):
		return DEFAULT_THRESHOLD
	return clampf(value, MIN_THRESHOLD, MAX_THRESHOLD)


## The largest absolute sample of either channel in `chunk`.
static func peak_of(chunk: PackedVector2Array) -> float:
	var peak := 0.0
	for frame: Vector2 in chunk:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return peak


func _wants_open(talk_held: bool) -> bool:
	if mode == Mode.PUSH_TO_TALK:
		_hangover = 0
		return talk_held
	if last_peak > threshold:
		_hangover = HANGOVER_FRAMES
		return true
	if _hangover > 0:
		_hangover -= 1
		return true
	return false
