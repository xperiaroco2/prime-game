class_name SpikeVoiceSource
extends RefCounted
## Spike (#15): a speaker's voice as Opus frames of 20 ms, from the microphone (as in
## spike/voice/loopback.gd) or from a synthetic tone. On one machine every instance shares one
## microphone, so only one client captures it and the other plays a tone through the same encoder:
## a steady sine with a slow 2 Hz swell, easy to tell apart and to measure.

const OPUS_RATE := 48000
const CHUNK := 960  # 20 ms at 48 kHz
const BIT_RATE := 24000
const COMPLEXITY := 5
const TONE_AMPLITUDE := 0.3
const MAX_TONE_CHUNKS := 5  # after a long frame the tone skips ahead instead of bursting

var peak := 0.0  # the input peak since the caller last reset it
var _enc := TwovoipOpusEncoder.new()
var _tone_hz := 0.0
var _in_size := 0
var _mic := false
var _clock := 0.0
var _generated := 0


## Starts the microphone when tone_hz is 0, else a tone of tone_hz. Returns an error message, or
## "" on success.
func start(tone_hz: float) -> String:
	_tone_hz = tone_hz
	_mic = tone_hz <= 0.0
	var in_rate := OPUS_RATE
	# A tone is not speech: RNNoise would treat it as noise and remove it.
	var denoiser := TwovoipOpusEncoder.DENOISER_DISABLED
	if _mic:
		var err := AudioServer.set_input_device_active(true)
		if err != OK:
			return (
				"microphone: %s (audio/driver/enable_input, Windows mic privacy?)"
				% error_string(err)
			)
		in_rate = int(AudioServer.get_input_mix_rate())
		denoiser = TwovoipOpusEncoder.DENOISER_RNNOISE
	var code := _enc.initialize(
		in_rate, OPUS_RATE, 1, denoiser, TwovoipOpusEncoder.AGC_DISABLED, CHUNK
	)
	if code != OK:
		return "encoder initialize: %s" % error_string(code)
	if not _enc.create_opus_encoder(BIT_RATE, COMPLEXITY, true):
		return "create_opus_encoder failed"
	_in_size = _enc.get_required_input_chunk_size()
	return ""


func stop() -> void:
	if _mic:
		AudioServer.set_input_device_active(false)
	_mic = false
	_in_size = 0


func describe() -> String:
	return "mic" if _mic else "tone %.0f Hz" % _tone_hz


## The Opus frames encoded since the last call. `delta` is the frame time; the tone runs on it.
func pull(delta: float) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if _in_size <= 0:
		return out
	if _mic:
		while AudioServer.get_input_frames_available() >= _in_size:
			var frames := AudioServer.get_input_frames(_in_size)
			if frames.size() < _in_size or not _encode(frames, out):
				break
		return out
	_clock += delta
	var due := floori(_clock * OPUS_RATE)
	if due - _generated > MAX_TONE_CHUNKS * _in_size:
		_generated = due - MAX_TONE_CHUNKS * _in_size
	while _generated + _in_size <= due:
		if not _encode(_tone(_generated, _in_size), out):
			break
		_generated += _in_size
	return out


func _encode(frames: PackedVector2Array, out: Array[PackedByteArray]) -> bool:
	if _enc.process_chunk(frames) < 0:
		return false
	peak = maxf(peak, _enc.get_peak())
	var packet := _enc.encode_chunk(PackedByteArray())
	if not packet.is_empty():
		out.append(packet)
	return true


func _tone(first: int, count: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var t := float(first + i) / OPUS_RATE
		var swell := 0.7 + 0.3 * sin(TAU * 2.0 * t)
		var v := TONE_AMPLITUDE * swell * sin(TAU * _tone_hz * t)
		frames[i] = Vector2(v, v)
	return frames
