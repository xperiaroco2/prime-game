extends "res://tools/sfx/synth_voices.gd"
## The lobby: the bar, the pinball and the mirror (#1674): the M8 takes, each a
## function `_<take>` (m8_synth.gd's PICKS) returning its samples before the scaling.


## The tap pours a mug, 1.6 s: a fizzing stream whose pitch rises as the mug fills, and bubbles.
func _tap_pour_a() -> PackedFloat32Array:
	var out := _buf(1.7)
	_noise(
		out, 0.0, 1.6, 0.6, Vector2(0.05, 0.2), Shape.BAND, Vector2(900.0, 1900.0), 1.2, SEED + 30
	)
	_bubbles(out, 0.1, 1.5, 22, 300.0, 900.0, 0.2, SEED + 31)
	return out


## Two quick gulps.
func _drink_b() -> PackedFloat32Array:
	var out := _buf(0.7)
	_gulp(out, 0.0, SEED + 40)
	_gulp(out, 0.24, SEED + 41)
	return out


## A flipper: a solenoid's clack with a low thunk.
func _pinball_flipper_a() -> PackedFloat32Array:
	var out := _buf(0.2)
	_noise(
		out,
		0.0,
		0.03,
		0.9,
		Vector2(0.0005, 0.01),
		Shape.HIGH,
		Vector2(1500.0, 1500.0),
		0.7,
		SEED + 42
	)
	_tone(out, 0.0, 0.12, Vector2(190.0, 110.0), Vector2(0.001, 0.03), 0.8)
	return out


## A bumper: a pop and a bright bell.
func _pinball_bumper_a() -> PackedFloat32Array:
	var out := _buf(0.5)
	_noise(
		out,
		0.0,
		0.03,
		0.7,
		Vector2(0.0005, 0.01),
		Shape.HIGH,
		Vector2(2000.0, 2000.0),
		0.7,
		SEED + 44
	)
	_fm(out, 0.0, 0.45, 1318.5, 1318.5, 3.5, 1.2, 0.002, 0.12, 0.5)
	return out


## The ball launched: a spring released, the ball rolling off.
func _pinball_launch_a() -> PackedFloat32Array:
	var out := _buf(0.8)
	_tone(out, 0.0, 0.25, Vector2(140.0, 520.0), Vector2(0.002, 0.1), 0.6, 0.05, Wave.TRIANGLE)
	_noise(
		out,
		0.08,
		0.6,
		0.25,
		Vector2(0.05, 0.25),
		Shape.BAND,
		Vector2(600.0, 1200.0),
		1.5,
		SEED + 46
	)
	return out


## The ball lost: three notes falling.
func _pinball_drain_a() -> PackedFloat32Array:
	var out := _buf(0.9)
	var notes: Array[float] = [523.25, 415.3, 311.13]
	for i in notes.size():
		_tone(
			out,
			0.15 * i,
			0.4,
			Vector2(notes[i], notes[i]),
			Vector2(0.004, 0.12),
			0.5,
			0.0,
			Wave.SQUARE
		)
	return out


## A new best score: a quick rising arpeggio.
func _pinball_best_a() -> PackedFloat32Array:
	var out := _buf(1.0)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in notes.size():
		_tone(
			out,
			0.07 * i,
			0.4,
			Vector2(notes[i], notes[i]),
			Vector2(0.003, 0.12),
			0.4,
			0.0,
			Wave.SQUARE
		)
	return out


## The mirror's menu opens: a soft glassy shimmer, rising.
func _mirror_open_a() -> PackedFloat32Array:
	var out := _buf(0.8)
	var notes: Array[float] = [1568.0, 2093.0, 2349.3, 2637.0, 3136.0]
	for i in notes.size():
		_tone(out, 0.05 * i, 0.5, Vector2(notes[i], notes[i]), Vector2(0.004, 0.15), 0.25)
	return out
