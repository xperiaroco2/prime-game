extends RefCounted
## The ship engine's placeholder sounds (#1501; GDD §8 "The ship's engine"), the project's own
## synthesis: no sample, preset or recording, only the sums below, so every render is the same
## file (a fixed-seed noise). render_engine_sounds.gd writes them to assets/audio/prime_engine/
## (docs/credits/prime_engine.md); SfxSet plays them. Each is mono 44.1 kHz 16-bit PCM, its mean
## taken out and scaled to its PEAKS level. Every sound, length, pitch and level is a placeholder
## for the engineer to pick by ear on sfx-check's listening page, "not a decision".

const RATE := 44100
## The six sounds by file name (without `.wav`), in GDD §8's order.
const NAMES: Array[StringName] = [
	&"engine_call", &"engine_beep", &"engine_wail", &"engine_zap", &"engine_blast", &"engine_roar"
]
## Each sound's peak after the scaling: the beep held and the wail long, so lower (sfx-check's RMS
## band), the call soft, the zap, the blast and the roar full.
const PEAKS: Dictionary[StringName, float] = {
	&"engine_call": 0.45,
	&"engine_beep": 0.25,
	&"engine_wail": 0.6,
	&"engine_zap": 0.8,
	&"engine_blast": 0.8,
	&"engine_roar": 0.8,
}
## The noise's seed: the same every render.
const SEED := 1501


## The samples of sound `sound_name` (one of NAMES), from -1 to 1; empty for another name.
static func samples(sound_name: StringName) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	match sound_name:
		&"engine_call":
			raw = call_tone()
		&"engine_beep":
			raw = beep()
		&"engine_wail":
			raw = wail()
		&"engine_zap":
			raw = zap()
		&"engine_blast":
			raw = blast()
		&"engine_roar":
			raw = roar()
		_:
			return raw
	return scaled(raw, PEAKS[sound_name])


## The ship calls: a soft round "boop" at E5 (659.25 Hz) with a touch of its octave, 4 ms in, then
## falling away over 0.35 s.
static func call_tone() -> PackedFloat32Array:
	var out := _silence(0.35)
	for i in out.size():
		var t := float(i) / RATE
		var level := _attack(t, 0.004) * exp(-t / 0.09)
		var phase := TAU * 659.25 * t
		out[i] = level * (sin(phase) + 0.25 * sin(2.0 * phase))
	return out


## One lamp of the order: a short electronic beep at E6 (1318.5 Hz), a sine with a little of its
## third harmonic, held 0.12 s with 3 ms edges.
static func beep() -> PackedFloat32Array:
	var out := _silence(0.13)
	for i in out.size():
		var t := float(i) / RATE
		var level := minf(_attack(t, 0.003), _attack(0.13 - t, 0.02))
		var phase := TAU * 1318.5 * t
		out[i] = level * (sin(phase) + 0.3 * sin(3.0 * phase))
	return out


## A problem: a siren rising from 380 Hz to 1100 Hz over 1.3 s (an exponential sweep), a soft
## sawtooth of four harmonics with a 7 Hz tremolo, swelling in and cut off in its last 0.1 s.
static func wail() -> PackedFloat32Array:
	var length := 1.4
	var out := _silence(length)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var freq := 380.0 * pow(1100.0 / 380.0, minf(1.0, t / 1.3))
		phase += TAU * freq / RATE
		var tone := 0.0
		for h in range(1, 5):
			tone += sin(phase * h) / h
		var level := minf(0.35 + 0.65 * minf(1.0, t / 0.5), _attack(length - t, 0.1))
		level *= _attack(t, 0.01) * (0.85 + 0.15 * sin(TAU * 7.0 * t))
		out[i] = level * tone
	return out


## A short circuit: 0.45 s of crackle (noise let through in random 4 ms bursts) over a 110 Hz
## buzz (a clipped sine) that falls to 70 Hz, all decaying fast.
static func zap() -> PackedFloat32Array:
	var length := 0.45
	var out := _silence(length)
	var noise := _Noise.new(SEED + 1)
	var burst := 0
	var gate := 1.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		if burst <= 0:
			burst = int(0.004 * RATE)
			gate = 1.0 if noise.next() > -0.2 else 0.15
		burst -= 1
		var freq := 110.0 - 40.0 * t / length
		phase += TAU * freq / RATE
		var buzz := clampf(2.5 * sin(phase), -1.0, 1.0)
		var level := _attack(t, 0.002) * exp(-t / 0.14)
		out[i] = level * (0.75 * gate * noise.next() + 0.45 * buzz)
	return out


## The blast through the ship: a 55 Hz thump falling to 35 Hz and decaying over 0.4 s, under a
## roar of noise through a low-pass whose cut-off falls from 3 kHz to 200 Hz, 2 s in all.
static func blast() -> PackedFloat32Array:
	var length := 2.0
	var out := _silence(length)
	var noise := _Noise.new(SEED + 2)
	var low := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var cutoff := 200.0 + 2800.0 * exp(-t / 0.35)
		low += _alpha(cutoff) * (noise.next() - low)
		phase += TAU * (35.0 + 20.0 * exp(-t / 0.2)) / RATE
		var thump := sin(phase) * exp(-t / 0.4)
		var level := _attack(t, 0.003) * exp(-t / 0.6)
		out[i] = level * (2.2 * low + 0.9 * thump)
	return out


## The finish: the ship's roar, a turbine spinning up (a sawtooth of six harmonics rising from
## 70 Hz to 190 Hz) inside a rumble of noise whose low-pass opens from 300 Hz to 2.5 kHz,
## swelling over 0.9 s, then held and fading out in its last 0.7 s, 2.8 s in all.
static func roar() -> PackedFloat32Array:
	var length := 2.8
	var out := _silence(length)
	var noise := _Noise.new(SEED + 3)
	var low := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var spin := minf(1.0, t / 1.6)
		phase += TAU * (70.0 + 120.0 * spin) / RATE
		var tone := 0.0
		for h in range(1, 7):
			tone += sin(phase * h) / h
		low += _alpha(300.0 + 2200.0 * spin) * (noise.next() - low)
		var level := minf(0.1 + 0.9 * minf(1.0, t / 0.9), _attack(length - t, 0.7))
		level *= _attack(t, 0.01)
		out[i] = level * (0.45 * tone + 1.6 * low)
	return out


## `raw` with its mean taken out and scaled so its largest magnitude is `peak`.
static func scaled(raw: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var out := raw.duplicate()
	if out.is_empty():
		return out
	var mean := 0.0
	for value: float in out:
		mean += value
	mean /= out.size()
	var top := 0.0
	for i in out.size():
		out[i] -= mean
		top = maxf(top, absf(out[i]))
	if top <= 0.0:
		return out
	for i in out.size():
		out[i] *= peak / top
	return out


## A WAV file of `values` (-1 to 1): RIFF, mono, RATE, 16-bit PCM.
static func wav_bytes(values: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(values.size() * 2)
	for i in values.size():
		data.encode_s16(i * 2, clampi(roundi(values[i] * 32767.0), -32768, 32767))
	var head := PackedByteArray()
	head.resize(44)
	head.encode_u32(0, 0x46464952)  # "RIFF"
	head.encode_u32(4, 36 + data.size())
	head.encode_u32(8, 0x45564157)  # "WAVE"
	head.encode_u32(12, 0x20746D66)  # "fmt "
	head.encode_u32(16, 16)
	head.encode_u16(20, 1)  # PCM
	head.encode_u16(22, 1)  # mono
	head.encode_u32(24, RATE)
	head.encode_u32(28, RATE * 2)
	head.encode_u16(32, 2)
	head.encode_u16(34, 16)
	head.encode_u32(36, 0x61746164)  # "data"
	head.encode_u32(40, data.size())
	return head + data


static func _silence(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(roundi(seconds * RATE))
	return out


## A linear rise from 0 to 1 over `seconds` from t 0 (1 after it).
static func _attack(t: float, seconds: float) -> float:
	return clampf(t / seconds, 0.0, 1.0)


## A one-pole low-pass's coefficient for `cutoff` Hz.
static func _alpha(cutoff: float) -> float:
	var step := TAU * cutoff / RATE
	return step / (step + 1.0)


## White noise from -1 to 1 by a 32-bit xorshift: the same numbers on every machine and version.
class _Noise:
	extends RefCounted
	var _state: int

	func _init(seed_value: int) -> void:
		_state = seed_value & 0xFFFFFFFF
		if _state == 0:
			_state = 1

	func next() -> float:
		_state ^= (_state << 13) & 0xFFFFFFFF
		_state ^= _state >> 17
		_state ^= (_state << 5) & 0xFFFFFFFF
		return float(_state) / 2147483647.5 - 1.0
