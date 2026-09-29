class_name SpikeVoiceSource
extends RefCounted
## Spike (#15): a speaker's voice as Opus frames of 20 ms, from the microphone (as in
## spike/voice/loopback.gd) or from a synthetic tone. On one machine every instance shares one
## microphone, so only one client captures it and the other plays a tone through the same encoder:
## a steady sine with a slow 2 Hz swell, easy to tell apart and to measure.
## Latency and CPU (#16): each frame's age at encoding (how long its first sample waited, in
## Godot's microphone buffer or for the tone clock), the time spent encoding, an optional onset
## detector on the raw microphone samples (SpikeVoiceOnsets) and an optional dump of them.

const OPUS_RATE := 48000
const CHUNK := 960  # 20 ms at 48 kHz
const BIT_RATE := 24000
const COMPLEXITY := 5
const TONE_AMPLITUDE := 0.3
const MAX_TONE_CHUNKS := 5  # after a long frame the tone skips ahead instead of bursting

var peak := 0.0  # the input peak since the caller last reset it
var last_peak := 0.0  # the input peak of the latest 20 ms chunk
## One per frame of the latest pull(): how long its first sample had waited when it was encoded, ms.
var ages: Array[float] = []
var encode_usec := 0  # time in process_chunk and encode_chunk
var encoded := 0
## Set it to find click onsets in the raw microphone samples; found ones collect in onsets.
var detector: SpikeVoiceOnsets
## [index, peak, unix] from the detector, for the caller to drain; unix is when the onset reached
## Godot's microphone buffer.
var onsets: Array[Array] = []
var dump_mic := false  # keep the raw microphone samples for save_dump()
var _dump := PackedByteArray()
var _enc := TwovoipOpusEncoder.new()
var _tone_hz := 0.0
var _in_size := 0
var _in_rate := OPUS_RATE
var _mic := false
var _denoise := true
var _clock := 0.0
var _generated := 0


## Starts the microphone when tone_hz is 0, else a tone of tone_hz. `mic_device` picks an input
## device by its name in AudioServer.get_input_device_list() ("" keeps the Windows default).
## `denoise` false turns RNNoise off for the microphone (a tone never uses it).
## Returns an error message, or "" on success.
## Godot 4.7.2's WASAPI driver reads only mono or stereo microphones: with a 4-channel laptop
## microphone array it prints an error for every sample and freezes (#15). Pick a headset
## microphone with mic_device, or set the device to 2 channels in the Windows sound settings.
func start(tone_hz: float, mic_device: String = "", denoise: bool = true) -> String:
	_tone_hz = tone_hz
	_mic = tone_hz <= 0.0
	_in_rate = OPUS_RATE
	# A tone is not speech: RNNoise would treat it as noise and remove it.
	var denoiser := TwovoipOpusEncoder.DENOISER_DISABLED
	if _mic:
		if mic_device != "":
			if not AudioServer.get_input_device_list().has(mic_device):
				_mic = false
				return "no input device '%s'" % mic_device
			AudioServer.input_device = mic_device
		var err := AudioServer.set_input_device_active(true)
		if err != OK:
			return (
				"microphone: %s (audio/driver/enable_input, Windows mic privacy?)"
				% error_string(err)
			)
		_in_rate = int(AudioServer.get_input_mix_rate())
		_denoise = denoise
		if denoise:
			denoiser = TwovoipOpusEncoder.DENOISER_RNNOISE
	var code := _enc.initialize(
		_in_rate, OPUS_RATE, 1, denoiser, TwovoipOpusEncoder.AGC_DISABLED, CHUNK
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
	if not _mic:
		return "tone %.0f Hz" % _tone_hz
	return (
		"mic '%s' at %d Hz rnnoise=%s input_buffer_frames=%d"
		% [
			AudioServer.input_device,
			_in_rate,
			_denoise,
			AudioServer.get_input_buffer_length_frames()
		]
	)


func is_mic() -> bool:
	return _mic


func input_rate() -> int:
	return _in_rate


## The Opus frames encoded since the last call, with their ages in `ages`. `delta` is the frame
## time; the tone runs on it.
func pull(delta: float) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	ages.clear()
	if _in_size <= 0:
		return out
	if _mic:
		while AudioServer.get_input_frames_available() >= _in_size:
			# The oldest unread sample has waited about as long as the buffer holds.
			var age_ms := AudioServer.get_input_frames_available() * 1000.0 / _in_rate
			var frames := AudioServer.get_input_frames(_in_size)
			if frames.size() < _in_size:
				break
			_inspect(frames)
			if not _encode(frames, out, age_ms):
				break
		return out
	_clock += delta
	var due := floori(_clock * OPUS_RATE)
	if due - _generated > MAX_TONE_CHUNKS * _in_size:
		_generated = due - MAX_TONE_CHUNKS * _in_size
	while _generated + _in_size <= due:
		var age_ms := (due - _generated) * 1000.0 / OPUS_RATE
		if not _encode(_tone(_generated, _in_size), out, age_ms):
			break
		_generated += _in_size
	return out


## Writes the kept microphone samples to a mono 16-bit WAV file.
func save_dump(path: String) -> Error:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _in_rate
	wav.stereo = false
	wav.data = _dump
	return wav.save_to_wav(path)


func _inspect(frames: PackedVector2Array) -> void:
	if detector != null:
		# When the last sample of these frames reached Godot's buffer, about: now, less what is
		# still unread behind it. Each onset gets the time it was captured, on the system clock.
		var backlog_s := float(AudioServer.get_input_frames_available()) / _in_rate
		var end_unix := Time.get_unix_time_from_system() - backlog_s
		for onset: Array in detector.feed(frames):
			var behind_s := float(detector.fed() - (onset[0] as int)) / _in_rate
			onset.append(end_unix - behind_s)
			onsets.append(onset)
	if dump_mic:
		var at := _dump.size()
		_dump.resize(at + frames.size() * 2)
		for i in frames.size():
			var v := clampf((frames[i].x + frames[i].y) * 0.5, -1.0, 1.0)
			_dump.encode_s16(at + i * 2, roundi(v * 32767.0))


func _encode(frames: PackedVector2Array, out: Array[PackedByteArray], age_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	if _enc.process_chunk(frames) < 0:
		return false
	last_peak = _enc.get_peak()
	peak = maxf(peak, last_peak)
	var packet := _enc.encode_chunk(PackedByteArray())
	encode_usec += Time.get_ticks_usec() - t0
	encoded += 1
	if not packet.is_empty():
		out.append(packet)
		ages.append(age_ms)
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
