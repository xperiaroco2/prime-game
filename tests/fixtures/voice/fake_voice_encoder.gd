class_name FakeVoiceEncoder
extends VoiceEncoder
## FakeVoiceCodec's encoder: each 20 ms chunk of stereo frames at the input rate becomes 160 µ-law
## bytes at 8 kHz, mixed to mono and picked by nearest sample (no filter: a test signal, not
## speech).

## The latest start()'s arguments, for tests.
var input_rate := 0
var denoise := false

var _chunk := 0


func start(rate: int, with_denoise: bool) -> String:
	_chunk = 0
	if rate <= 0 or rate % 50 != 0:
		return "fake codec: an input rate of %d Hz is not a whole number of 20 ms frames" % rate
	input_rate = rate
	denoise = with_denoise
	_chunk = int(float(rate) / 50.0)
	return ""


func chunk_frames() -> int:
	return _chunk


func encode(chunk: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	if _chunk <= 0 or chunk.size() != _chunk:
		return out
	out.resize(FakeMuLaw.FRAME_SAMPLES)
	for i: int in FakeMuLaw.FRAME_SAMPLES:
		var source := chunk[int(float(i) * _chunk / FakeMuLaw.FRAME_SAMPLES)]
		out[i] = FakeMuLaw.encode_sample((source.x + source.y) * 0.5)
	return out
