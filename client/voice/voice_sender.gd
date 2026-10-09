class_name VoiceSender
extends Node
## The own voice, from the microphone to the host (the M5 ADR §1.1 and §1.2, E37; ARCHITECTURE §6):
## every frame it drains VoiceCapture, encodes EVERY captured chunk (so the codec's and RNNoise's
## state stay continuous), feeds each to VoiceGate with this frame's `may_speak` and talk key, and
## sends what the gate lets out through ClientSession.send_voice. Nothing leaves in silence.
##
## The contract (the manager's review of PR #234, item 5): every chunk is drained and fed in the
## frame it arrives, also while `may_speak` is false, with that frame's `may_speak`. So a backlog
## recorded while downed, dead or in a silent phase goes through the gate as unspeakable and
## empties its pre-roll, and never goes out after a revive. What Godot has handed over in the frame
## may_speak turns true (or after the own model's `silencings` moved) counts as unspeakable too
## (step()): recorded before the change but for the audio of that frame after the fold, dropped with
## it; the driver's own buffer (under one chunk) may still hold a little from before.
##
## `may_speak` (may_speak_of()) is client/'s decision, never voice/'s: the own life fold is living
## and the client's own copy of the mode hears someone in the current phase (VoiceRule.radius_of >
## 0, E41), from the own ClientModel only, never Match or MatchState (invariant 2, the host's own
## client too; the E18 boundary test scans res://client and res://voice). Not sending narrows
## nothing: the host routes none of it anyway (the voice invariant).
##
## Nothing opens without the codec (the addon absent: voice unavailable). Off (D11) is a closed
## capture; VoiceControl decides what opens. Push-to-talk reads `voice_talk` (V) only while
## `listening`: the keys are not typing (#488: the Esc menu keeps the voice, a text field or a key
## capture does not).

const TALK_ACTION := &"voice_talk"
## The words for a machine without the voice codec (greybox, #150).
const UNAVAILABLE := "voice is unavailable: the voice addon (TwoVoIP) is not installed"

## The own model and the client's own copy of the mode, after setup(); null before and between
## sessions (then may_speak is false and nothing is sent).
var model: ClientModel
var mode: GameMode
var capture := VoiceCapture.new()
## The codec to encode with: the base codec, never available, until the game sets one.
var codec := VoiceCodec.new()
var gate := VoiceGate.new()
## Sends one frame (ClientSession.send_voice after setup()); none between sessions.
var send := Callable()
## Read the talk key from the keyboard; tests turn it off and set `talk_held`.
var reads_device_input := true
## The keys are not typing into a text field or a key capture: the talk key counts (Game sets it).
var listening := true
## The talk key, while reads_device_input is off.
var talk_held := false
## Why the last open() failed; "" after a success.
var error := ""
## For the F3 overlay (debug builds, E47): the latest chunk's peak, its age when it was read, the
## time its encoding took, and the frames sent since the start.
var peak := 0.0
var frame_age_usec := 0
var encode_usec := 0
var sent := 0

var _encoder: VoiceEncoder
## may_speak at the last step(); a fresh capture holds nothing recorded before, so it starts true.
var _could_speak := true
## Frames still waiting that were recorded before may_speak last turned true (or `silencings` last
## moved).
var _stale_frames := 0
## The own model's `silencings` at the last step(); -1 for none (no model, or a new one).
var _silencings := -1


func _init() -> void:
	name = "VoiceSender"


## Speaks into `client`'s session with `game_mode`'s phases, until reset().
func setup(client: ClientSession, game_mode: GameMode) -> void:
	model = client.model
	mode = game_mode
	send = client.send_voice
	_silencings = -1


## Forgets the session (it ended). The microphone stays as the settings have it.
func reset() -> void:
	model = null
	mode = null
	send = Callable()
	_silencings = -1


## Opens `device` (VoiceMicrophone.DEFAULT_DEVICE for the Windows default) and a fresh encoder at
## its rate, with RNNoise when `denoise` and the source is a microphone (it would remove the test
## tone). False, with `error`, when the codec is unavailable or the device or the encoder fails.
func open(device: String, denoise: bool) -> bool:
	close()
	error = ""
	if not codec.available():
		error = UNAVAILABLE
		return false
	if not capture.open(device):
		error = capture.error
		return false
	_encoder = codec.new_encoder()
	_could_speak = true
	_stale_frames = 0
	_silencings = model.silencings if model != null else -1
	var why := "the voice codec made no encoder"
	if _encoder != null:
		why = _encoder.start(capture.rate(), denoise and capture.microphone.is_device())
	if not why.is_empty():
		capture.close()
		_encoder = null
		error = why
		return false
	return true


## Closes the microphone: nothing is captured, encoded or sent; the pre-roll is emptied.
func close() -> void:
	capture.close()
	_encoder = null
	gate.feed(PackedVector2Array(), PackedByteArray(), false, false)
	peak = 0.0


func is_open() -> bool:
	return capture.is_open() and _encoder != null


## The encoder of the open microphone; null while closed.
func encoder() -> VoiceEncoder:
	return _encoder


## Whether the own player may be heard now: may_speak_of() for the own model and mode.
func may_speak() -> bool:
	return may_speak_of(model, mode)


## Whether a player whose own client holds `own_model` and `own_mode` may be heard now: welcomed,
## its own life fold living, and the current phase's voice rule hearing someone in the client's
## own copy of the mode (a phase with no voice rule hears nobody, E41). False with either null.
static func may_speak_of(own_model: ClientModel, own_mode: GameMode) -> bool:
	if own_model == null or own_mode == null:
		return false
	if not own_model.roster.has(own_model.own_peer):
		return false
	if own_model.life_of(own_model.own_peer) != ClientModel.Life.ALIVE:
		return false
	var spec := own_mode.find_phase(own_model.phase)
	return VoiceRule.radius_of(spec.voice_rule if spec != null else null) > 0.0


func _process(_delta: float) -> void:
	step()


## One frame: every chunk captured since the last, encoded and fed to the gate with this frame's
## may_speak and talk key; what the gate lets out is sent.
##
## In the frame where may_speak turns true (a revive or a phase that hears someone, folded by the
## session's physics step at the start of this frame), every frame Godot has handed over by then
## was recorded before the player could be heard (but for this frame's audio after the fold):
## those chunks are fed as unspeakable too, however long the frame was (a hitch, a level load).
## The same holds whenever the own model's `silencings` moved since the last step, though
## may_speak is true at both: a knockdown and its revive, or Round, End and Lobby, all folded
## between two steps (a hang longer than a revive, #241); not sampled once a frame, it is read
## from the model. A frame with no whole chunk while unspeakable still empties the pre-roll.
func step() -> void:
	if not is_open():
		return
	var speak := may_speak()
	var silencings := model.silencings if model != null else -1
	if (speak and not _could_speak) or silencings != _silencings:
		_stale_frames = capture.microphone.frames_available()
	_could_speak = speak
	_silencings = silencings
	var chunks := capture.read(_encoder.chunk_frames())
	if chunks.is_empty():
		if not speak:
			var shown := gate.last_peak
			gate.feed(PackedVector2Array(), PackedByteArray(), false, false)
			gate.last_peak = shown
		return
	var held := _talk_held()
	for chunk: VoiceCapture.Chunk in chunks:
		var fresh := speak and _stale_frames <= 0
		_stale_frames = maxi(_stale_frames - chunk.frames.size(), 0)
		var began := Time.get_ticks_usec()
		var frame := _encoder.encode(chunk.frames)
		encode_usec = Time.get_ticks_usec() - began
		frame_age_usec = chunk.age_usec
		for out: PackedByteArray in gate.feed(chunk.frames, frame, fresh, held):
			if send.is_valid() and send.call(out) == OK:
				sent += 1
	peak = gate.last_peak


func _talk_held() -> bool:
	if not listening:
		return false
	if reads_device_input:
		return Input.is_action_pressed(TALK_ACTION)
	return talk_held
