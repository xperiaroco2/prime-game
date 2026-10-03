class_name FakeMuLaw
extends RefCounted
## The fake codec's format, apart from FakeVoiceCodec so that its encoder and playback depend on
## this script and not on the codec that makes them (a cycle of scripts leaks at exit): 8 kHz mono
## µ-law, one byte a sample, 160 bytes a 20 ms frame. The companding is µ-law's continuous curve
## (mu 255), not G.711's segment tables.

const RATE := 8000
const FRAME_SAMPLES := 160
const MU := 255.0


## One sample in -1..1 as a µ-law byte.
static func encode_sample(value: float) -> int:
	var v := clampf(value, -1.0, 1.0)
	var y := signf(v) * log(1.0 + MU * absf(v)) / log(1.0 + MU)
	return clampi(roundi((y + 1.0) * 127.5), 0, 255)


## One µ-law byte as a sample in -1..1.
static func decode_sample(byte: int) -> float:
	var y := float(byte) / 127.5 - 1.0
	return signf(y) * (pow(1.0 + MU, absf(y)) - 1.0) / MU


## One frame as stereo audio frames, both channels alike.
static func decode_frame(frame: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frame.size())
	for i: int in frame.size():
		var v := decode_sample(frame[i])
		out[i] = Vector2(v, v)
	return out
