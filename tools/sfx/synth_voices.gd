extends RefCounted
## The voices of the project's own synthesis (#1674): tones, FM, filtered noise and their shapes,
## summed into a buffer of samples. No sample, preset or recording: the same sums give the same
## file every render (fixed-seed noise). The M8 takes (m8_*_takes.gd) extend it.

enum Wave { SINE, TRIANGLE, SQUARE, SAW }
enum Shape { LOW, HIGH, BAND }

const EngineSynth := preload("res://tools/sfx/engine_synth.gd")
const RATE := 44100
## The noise's seed: the same every render.
const SEED := 1674


## A tone at `at` s for `length` s, its pitch an exponential sweep from `sweep.x` to `sweep.y` Hz,
## its level `envelope` (_env()). `vibrato` is its depth (a
## share of the pitch, 5.5 Hz); `cutoff` > 0 low-passes it.
func _tone(
	out: PackedFloat32Array,
	at: float,
	length: float,
	sweep: Vector2,
	envelope: Vector2,
	gain := 1.0,
	vibrato := 0.0,
	wave := Wave.SINE,
	cutoff := 0.0
) -> void:
	var start := roundi(at * RATE)
	var count := mini(roundi(length * RATE), out.size() - start)
	var phase := 0.0
	var low := 0.0
	var alpha := EngineSynth._alpha(cutoff) if cutoff > 0.0 else 1.0
	var f0 := sweep.x
	var f1 := sweep.y
	for i in count:
		var t := float(i) / RATE
		var freq := f0 * pow(f1 / f0, t / length) * (1.0 + vibrato * sin(TAU * 5.5 * t))
		phase += freq / RATE
		phase -= floorf(phase)
		var value := 0.0
		match wave:
			Wave.SINE:
				value = sin(TAU * phase)
			Wave.TRIANGLE:
				value = 4.0 * absf(phase - 0.5) - 1.0
			Wave.SQUARE:
				value = 0.6 if phase < 0.5 else -0.6
			Wave.SAW:
				value = 0.7 * (2.0 * phase - 1.0)
		low += alpha * (value - low)
		out[start + i] += gain * low * _env(t, length, envelope)


## Two-operator FM (a bell, a clonk): a sine carrier at `f0` sweeping to `f1`, pushed by a sine at
## `ratio` times it whose depth falls from `index` times the carrier to nothing over half the sound.
func _fm(
	out: PackedFloat32Array,
	at: float,
	length: float,
	f0: float,
	f1: float,
	ratio: float,
	index: float,
	attack: float,
	tau: float,
	gain: float
) -> void:
	var start := roundi(at * RATE)
	var count := mini(roundi(length * RATE), out.size() - start)
	var carrier := 0.0
	var modulator := 0.0
	for i in count:
		var t := float(i) / RATE
		var freq := f0 * pow(f1 / f0, minf(1.0, t / (0.6 * length)))
		modulator += TAU * freq * ratio / RATE
		var depth := freq * index * maxf(0.0, 1.0 - t / (0.5 * length))
		carrier += TAU * (freq + depth * sin(modulator)) / RATE
		out[start + i] += gain * sin(carrier) * _env(t, length, Vector2(attack, tau))


## Seeded noise through a resonant filter (`shape`) whose frequency sweeps from `sweep.x` to
## `sweep.y` Hz, its level `envelope` (_env()).
func _noise(
	out: PackedFloat32Array,
	at: float,
	length: float,
	gain: float,
	envelope: Vector2,
	shape: Shape,
	sweep: Vector2,
	q: float,
	seed_value: int
) -> void:
	var start := roundi(at * RATE)
	var count := mini(roundi(length * RATE), out.size() - start)
	var noise := _Noise.new(seed_value)
	var filter := _Biquad.new()
	for i in count:
		var t := float(i) / RATE
		if i % 32 == 0:
			filter.set_to(shape, sweep.x * pow(sweep.y / sweep.x, t / length), q)
		out[start + i] += gain * filter.next(noise.next()) * _env(t, length, envelope)


## A whoosh: noise through a band rising from `f0` to `f1` and back, swelling and fading.
func _whoosh(
	out: PackedFloat32Array,
	at: float,
	length: float,
	f0: float,
	f1: float,
	gain: float,
	seed_value: int
) -> void:
	var start := roundi(at * RATE)
	var count := mini(roundi(length * RATE), out.size() - start)
	var noise := _Noise.new(seed_value)
	var filter := _Biquad.new()
	for i in count:
		var x := float(i) / count
		if i % 32 == 0:
			filter.set_to(Shape.BAND, f0 + (f1 - f0) * sin(PI * minf(1.0, x * 1.3)), 1.4)
		out[start + i] += gain * filter.next(noise.next()) * sin(PI * x) * sin(PI * x)


## A body's thud: a low sweep from `f0` to about half and a short muffled noise.
func _thud(out: PackedFloat32Array, at: float, f0: float, gain: float, seed_value: int) -> void:
	_tone(out, at, 0.3, Vector2(f0, f0 * 0.5), Vector2(0.002, 0.08), gain)
	_noise(
		out,
		at,
		0.15,
		0.7 * gain,
		Vector2(0.001, 0.04),
		Shape.LOW,
		Vector2(900.0, 300.0),
		0.7,
		seed_value
	)


## A gulp: a low formant pulse rising a little, with a throat click.
func _gulp(out: PackedFloat32Array, at: float, seed_value: int) -> void:
	_noise(
		out, at, 0.16, 0.9, Vector2(0.01, 0.05), Shape.BAND, Vector2(260.0, 420.0), 4.0, seed_value
	)
	_tone(out, at, 0.14, Vector2(180.0, 300.0), Vector2(0.01, 0.04), 0.6)
	_noise(
		out,
		at + 0.1,
		0.03,
		0.3,
		Vector2(0.0005, 0.008),
		Shape.BAND,
		Vector2(1800.0, 1800.0),
		3.0,
		seed_value + 100
	)


## `count` bubbles spread over `length` s from `at`: short sines chirping up from `f0` to `f1`.
func _bubbles(
	out: PackedFloat32Array,
	at: float,
	length: float,
	count: int,
	f0: float,
	f1: float,
	gain: float,
	seed_value: int
) -> void:
	var noise := _Noise.new(seed_value)
	for i in count:
		var when := at + length * absf(noise.next())
		var base := f0 + (f1 - f0) * absf(noise.next())
		_tone(
			out,
			when,
			0.05,
			Vector2(base, base * 1.8),
			Vector2(0.002, 0.015),
			gain * (0.5 + 0.5 * absf(noise.next()))
		)


## Smoke: a soft hiss with sparse crackles.
func _smoke(out: PackedFloat32Array, at: float, length: float, seed_value: int) -> void:
	_noise(
		out,
		at,
		length,
		0.2,
		Vector2(0.05, length * 0.35),
		Shape.HIGH,
		Vector2(3200.0, 3200.0),
		0.7,
		seed_value
	)
	var noise := _Noise.new(seed_value + 1)
	for i in 12:
		var when := at + length * 0.8 * absf(noise.next())
		var f := 3000.0 + 3000.0 * absf(noise.next())
		_noise(
			out,
			when,
			0.02,
			0.3,
			Vector2(0.0005, 0.006),
			Shape.BAND,
			Vector2(f, f),
			3.0,
			seed_value + 2 + i
		)


## A breaker's clunk: a wooden knock and a low thump.
func _clunk(out: PackedFloat32Array, at: float, seed_value: int) -> void:
	_noise(
		out,
		at,
		0.06,
		1.0,
		Vector2(0.0005, 0.015),
		Shape.BAND,
		Vector2(500.0, 500.0),
		4.0,
		seed_value
	)
	_tone(out, at, 0.12, Vector2(110.0, 70.0), Vector2(0.002, 0.04), 0.8)
	_noise(
		out,
		at,
		0.02,
		0.5,
		Vector2(0.0005, 0.005),
		Shape.HIGH,
		Vector2(3000.0, 3000.0),
		0.7,
		seed_value + 1
	)


## The decided hum Г1: 110 Hz with its 2nd and 3rd partials (0.4, 0.15) and 110.7 Hz beating
## against it, all doubling in pitch over the sound.
func _hum_g1(out: PackedFloat32Array, at: float, length: float) -> void:
	for part: Array in [[1.0, 1.0], [2.0, 0.4], [3.0, 0.15]]:
		var f := 110.0 * (part[0] as float)
		_tone(out, at, length, Vector2(f, f * 2.0), Vector2(0.08, 10.0), 0.25 * (part[1] as float))
	_tone(out, at, length, Vector2(110.7, 221.4), Vector2(0.08, 10.0), 0.125)


## The drone's hover: a buzz at `f` with its blades beating at 38 Hz, swelling in and out.
func _drone(out: PackedFloat32Array, at: float, length: float, f: float, gain: float) -> void:
	var start := roundi(at * RATE)
	var count := mini(roundi(length * RATE), out.size() - start)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		phase += TAU * f / RATE
		var value := sin(phase) + 0.5 * sin(2.0 * phase) + 0.25 * sin(3.0 * phase)
		var blades := 0.75 + 0.25 * sin(TAU * 38.0 * t)
		var level := minf(EngineSynth._attack(t, 0.25), EngineSynth._attack(length - t, 0.3))
		out[start + i] += gain * 0.5 * value * blades * level


## A held hum for a loop: `f` and its octave with a tremolo at `rate` Hz, the whole buffer.
func _loop_hum(out: PackedFloat32Array, f: float, rate: float, gain: float) -> void:
	for i in out.size():
		var t := float(i) / RATE
		var value := sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t)
		out[i] += gain * 0.5 * value * (0.8 + 0.2 * sin(TAU * rate * t))


## A whistle of noise at `f` whose level circles at 3 Hz, the whole buffer.
func _orbit(
	out: PackedFloat32Array, f: float, _length: float, gain: float, seed_value: int
) -> void:
	var noise := _Noise.new(seed_value)
	var filter := _Biquad.new()
	filter.set_to(Shape.BAND, f, 2.2)
	for i in out.size():
		var t := float(i) / RATE
		out[i] += gain * filter.next(noise.next()) * (0.6 + 0.4 * sin(TAU * 3.0 * t))


## `count` glints: short high sines at random moments over `length` s from `at`.
func _glints(
	out: PackedFloat32Array, at: float, length: float, count: int, gain: float, seed_value: int
) -> void:
	var notes: Array[float] = [2093.0, 2349.32, 2637.02, 3135.96]
	var noise := _Noise.new(seed_value)
	for i in count:
		var when := at + length * absf(noise.next())
		var f := notes[int(absf(noise.next()) * 3.99)]
		_tone(
			out,
			when,
			0.3,
			Vector2(f, f),
			Vector2(0.005, 0.09),
			gain * (0.5 + 0.5 * absf(noise.next()))
		)


## `out` made to loop: its last 50 ms cross-faded into its first, then cut there.
func _looped(out: PackedFloat32Array) -> PackedFloat32Array:
	var fade := roundi(0.05 * RATE)
	var size := out.size() - fade
	var looped := out.slice(0, size)
	for i in fade:
		var x := float(i) / fade
		looped[i] = looped[i] * x + out[size + i] * (1.0 - x)
	return looped


## The level at `t` of a sound `length` s long: `envelope.x` s in, then an exponential decay with
## time constant `envelope.y` s, faded to zero over its last 10 ms.
static func _env(t: float, length: float, envelope: Vector2) -> float:
	var level := EngineSynth._attack(t, envelope.x) * exp(-maxf(0.0, t - envelope.x) / envelope.y)
	return level * EngineSynth._attack(length - t, 0.01)


static func _buf(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(roundi(seconds * RATE))
	return out


## Seeded white noise from -1 to 1 (engine_synth's xorshift).
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


## An RBJ biquad: low-pass, high-pass or band-pass (constant peak).
class _Biquad:
	extends RefCounted
	var _b0 := 1.0
	var _b1 := 0.0
	var _b2 := 0.0
	var _a1 := 0.0
	var _a2 := 0.0
	var _x1 := 0.0
	var _x2 := 0.0
	var _y1 := 0.0
	var _y2 := 0.0

	func set_to(shape: int, freq: float, q: float) -> void:
		var w := TAU * clampf(freq, 20.0, 20000.0) / RATE
		var alpha := sin(w) / (2.0 * q)
		var cosw := cos(w)
		var a0 := 1.0 + alpha
		match shape:
			0:
				_b0 = (1.0 - cosw) / 2.0
				_b1 = 1.0 - cosw
				_b2 = (1.0 - cosw) / 2.0
			1:
				_b0 = (1.0 + cosw) / 2.0
				_b1 = -(1.0 + cosw)
				_b2 = (1.0 + cosw) / 2.0
			_:
				_b0 = alpha
				_b1 = 0.0
				_b2 = -alpha
		_b0 /= a0
		_b1 /= a0
		_b2 /= a0
		_a1 = -2.0 * cosw / a0
		_a2 = (1.0 - alpha) / a0

	func next(x: float) -> float:
		var y := _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2
		_x2 = _x1
		_x1 = x
		_y2 = _y1
		_y1 = y
		return y
