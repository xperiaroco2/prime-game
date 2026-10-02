class_name TwoVoipEncoder
extends VoiceEncoder
## TwoVoipCodec's encoder: the addon's encoder object, reached only by Object.call (TwoVoipCodec
## says why). The calls and their arguments are the M1 spike's (`voice_source.gd`):
## `initialize(input_rate, 48000, 1, denoiser, AGC_DISABLED, 960)`,
## `create_opus_encoder(24000, 5, true)`, `get_required_input_chunk_size()`, then per chunk
## `process_chunk(frames)` and `encode_chunk(PackedByteArray())`. It resamples the device's rate
## to 48 kHz and encodes mono from Godot's stereo frames.

const OPUS_RATE := 48000
const CHANNELS := 1
## Samples in one 20 ms frame at 48 kHz.
const FRAME_SAMPLES := 960
const BIT_RATE := 24000
const COMPLEXITY := 5

var _encoder: Object
var _class: StringName
var _chunk := 0


## `encoder` is an instance of the addon's class `encoder_class`, whose constants this reads.
func _init(encoder: Object, encoder_class: StringName) -> void:
	_encoder = encoder
	_class = encoder_class


func start(input_rate: int, denoise: bool) -> String:
	_chunk = 0
	var names: Array[StringName] = [
		&"DENOISER_RNNOISE" if denoise else &"DENOISER_DISABLED", &"AGC_DISABLED"
	]
	for constant: StringName in names:
		if not ClassDB.class_has_integer_constant(_class, constant):
			return "the voice addon has no %s" % constant
	var denoiser := ClassDB.class_get_integer_constant(_class, names[0])
	var agc := ClassDB.class_get_integer_constant(_class, names[1])
	var code: int = _encoder.call(
		&"initialize", input_rate, OPUS_RATE, CHANNELS, denoiser, agc, FRAME_SAMPLES
	)
	if code != OK:
		return "voice encoder: %s" % error_string(code)
	var created: bool = _encoder.call(&"create_opus_encoder", BIT_RATE, COMPLEXITY, true)
	if not created:
		return "voice encoder: create_opus_encoder failed"
	var chunk: int = _encoder.call(&"get_required_input_chunk_size")
	if chunk <= 0:
		return "voice encoder: no input chunk size"
	_chunk = chunk
	return ""


func chunk_frames() -> int:
	return _chunk


func encode(chunk: PackedVector2Array) -> PackedByteArray:
	if _chunk <= 0 or chunk.size() != _chunk:
		return PackedByteArray()
	var processed: int = _encoder.call(&"process_chunk", chunk)
	if processed < 0:
		return PackedByteArray()
	var packet: PackedByteArray = _encoder.call(&"encode_chunk", PackedByteArray())
	return packet
