extends "res://tools/sfx/synth_voices.gd"
## The hits, the swing, the knockdown, the raise, death and the return (#1674): the M8 takes, each a
## function `_<take>` (m8_synth.gd's PICKS) returning its samples before the scaling.


## A soft punch: a low body thump (140 to 55 Hz) under a short muffled smack.
func _hit_fist_a() -> PackedFloat32Array:
	var out := _buf(0.35)
	_tone(out, 0.0, 0.3, Vector2(140.0, 55.0), Vector2(0.002, 0.07))
	_noise(out, 0.0, 0.08, 1.0, Vector2(0.001, 0.025), Shape.LOW, Vector2(1400.0, 500.0), 0.7, SEED)
	_tone(out, 0.0, 0.03, Vector2(900.0, 300.0), Vector2(0.001, 0.008), 0.25)
	return out


## The crystal lands: a heavy thump, a crunch and a glassy ring of three inharmonic partials.
func _hit_crystal_a() -> PackedFloat32Array:
	var out := _buf(0.9)
	_tone(out, 0.0, 0.45, Vector2(95.0, 40.0), Vector2(0.002, 0.12))
	_noise(
		out, 0.0, 0.12, 0.9, Vector2(0.001, 0.04), Shape.LOW, Vector2(2200.0, 600.0), 0.7, SEED + 4
	)
	var partials: Array[Vector3] = [
		Vector3(1180.0, 0.22, 0.35), Vector3(3257.0, 0.12, 0.2), Vector3(6372.0, 0.06, 0.12)
	]
	for partial: Vector3 in partials:
		_tone(out, 0.005, 0.85, Vector2(partial.x, partial.x), Vector2(0.002, partial.z), partial.y)
	return out


## A fist's whoosh: noise through a band that sweeps up and back, 0.2 s.
func _swing_fist_a() -> PackedFloat32Array:
	var out := _buf(0.24)
	_whoosh(out, 0.0, 0.22, 600.0, 2200.0, 0.4, SEED + 6)
	return out


## The crystal's swing: a lower, longer whoosh with a faint shimmer of the crystal in it.
func _swing_crystal_a() -> PackedFloat32Array:
	var out := _buf(0.4)
	_whoosh(out, 0.0, 0.36, 300.0, 1300.0, 0.5, SEED + 8)
	_tone(out, 0.05, 0.3, Vector2(1568.0, 1568.0), Vector2(0.08, 0.1), 0.05)
	_tone(out, 0.05, 0.3, Vector2(2349.0, 2349.0), Vector2(0.08, 0.08), 0.03)
	return out


## A body falls: the knees, then the body, then a soft settle of cloth.
func _knockdown_a() -> PackedFloat32Array:
	var out := _buf(0.8)
	_thud(out, 0.0, 120.0, 0.6, SEED + 10)
	_thud(out, 0.13, 90.0, 1.0, SEED + 11)
	_noise(
		out,
		0.18,
		0.4,
		0.15,
		Vector2(0.02, 0.12),
		Shape.BAND,
		Vector2(1800.0, 900.0),
		0.8,
		SEED + 12
	)
	return out


## Back on the feet: a soft rising sweep and a light pop.
func _revive_a() -> PackedFloat32Array:
	var out := _buf(0.6)
	_tone(out, 0.0, 0.45, Vector2(220.0, 660.0), Vector2(0.05, 0.35), 0.6, 0.0, Wave.TRIANGLE)
	_tone(out, 0.38, 0.2, Vector2(880.0, 1320.0), Vector2(0.003, 0.05), 0.4)
	return out


## Death: a soft low bell, twice, falling a fourth.
func _death_a() -> PackedFloat32Array:
	var out := _buf(1.8)
	_fm(out, 0.0, 1.2, 220.0, 220.0, 3.5, 1.4, 0.004, 0.35, 0.5)
	_fm(out, 0.35, 1.4, 164.81, 164.81, 3.5, 1.4, 0.004, 0.45, 0.6)
	return out


## The drone prints you back, 2.1 s: its hover hum under the print head's stepping chirps rising
## from the feet up, a "ding" when done.
func _print_a() -> PackedFloat32Array:
	var out := _buf(2.4)
	_drone(out, 0.0, 2.2, 165.0, 0.35)
	var noise := _Noise.new(SEED + 19)
	var at := 0.05
	while at < 1.95:
		var pitch := 700.0 + 600.0 * (at / 2.0) + 150.0 * absf(noise.next())
		_tone(out, at, 0.06, Vector2(pitch, pitch), Vector2(0.002, 0.03), 0.18, 0.0, Wave.SQUARE)
		at += 0.07
	_tone(out, 2.05, 0.35, Vector2(1568.0, 1568.0), Vector2(0.002, 0.12), 0.35)
	return out
