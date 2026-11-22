extends "res://tools/sfx/synth_voices.gd"
## The hits, the swing, the knockdown, the raise, death and the return (#1674): the M8 takes, each a
## function `_<take>` (m8_synth.gd's CANDIDATES) returning its samples before the scaling.


## A soft punch: a low body thump (140 to 55 Hz) under a short muffled smack.
func _hit_fist_a() -> PackedFloat32Array:
	var out := _buf(0.35)
	_tone(out, 0.0, 0.3, Vector2(140.0, 55.0), Vector2(0.002, 0.07))
	_noise(out, 0.0, 0.08, 1.0, Vector2(0.001, 0.025), Shape.LOW, Vector2(1400.0, 500.0), 0.7, SEED)
	_tone(out, 0.0, 0.03, Vector2(900.0, 300.0), Vector2(0.001, 0.008), 0.25)
	return out


## A slap-punch: a bright slap on top of a shorter body.
func _hit_fist_b() -> PackedFloat32Array:
	var out := _buf(0.3)
	_noise(
		out,
		0.0,
		0.05,
		1.0,
		Vector2(0.0005, 0.012),
		Shape.BAND,
		Vector2(2200.0, 1400.0),
		1.2,
		SEED + 1
	)
	_tone(out, 0.004, 0.25, Vector2(120.0, 60.0), Vector2(0.002, 0.06), 0.9)
	_noise(
		out, 0.004, 0.1, 0.5, Vector2(0.001, 0.03), Shape.LOW, Vector2(700.0, 300.0), 0.7, SEED + 2
	)
	return out


## A cartoon "pok": a pitched knock falling fast over a small thump.
func _hit_fist_c() -> PackedFloat32Array:
	var out := _buf(0.3)
	_tone(out, 0.0, 0.12, Vector2(620.0, 210.0), Vector2(0.001, 0.035), 0.8)
	_tone(out, 0.0, 0.25, Vector2(130.0, 70.0), Vector2(0.002, 0.06), 0.7)
	_noise(
		out,
		0.0,
		0.03,
		0.4,
		Vector2(0.0005, 0.008),
		Shape.HIGH,
		Vector2(2500.0, 2500.0),
		0.7,
		SEED + 3
	)
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


## A heavy, dull clonk: a thump and an FM "clonk" a little like a big stone bell.
func _hit_crystal_b() -> PackedFloat32Array:
	var out := _buf(0.7)
	_tone(out, 0.0, 0.45, Vector2(85.0, 38.0), Vector2(0.002, 0.13))
	_fm(out, 0.0, 0.5, 420.0, 300.0, 1.41, 2.5, 0.002, 0.11, 0.55)
	_noise(
		out, 0.0, 0.09, 0.8, Vector2(0.001, 0.03), Shape.LOW, Vector2(1800.0, 500.0), 0.7, SEED + 5
	)
	return out


## A big cartoon bonk with a short glassy shimmer after it.
func _hit_crystal_c() -> PackedFloat32Array:
	var out := _buf(0.8)
	_tone(out, 0.0, 0.3, Vector2(330.0, 90.0), Vector2(0.001, 0.07), 0.9)
	_tone(out, 0.0, 0.4, Vector2(90.0, 45.0), Vector2(0.002, 0.1), 0.8)
	for i in 6:
		var at := 0.05 + 0.045 * i
		_tone(
			out,
			at,
			0.3,
			Vector2(2093.0 + 260.0 * (i % 3), 2093.0 + 260.0 * (i % 3)),
			Vector2(0.003, 0.08),
			0.1
		)
	return out


## A fist's whoosh: noise through a band that sweeps up and back, 0.2 s.
func _swing_fist_a() -> PackedFloat32Array:
	var out := _buf(0.24)
	_whoosh(out, 0.0, 0.22, 600.0, 2200.0, 0.4, SEED + 6)
	return out


## A shorter, airier whoosh.
func _swing_fist_b() -> PackedFloat32Array:
	var out := _buf(0.18)
	_whoosh(out, 0.0, 0.16, 900.0, 3200.0, 0.6, SEED + 7)
	return out


## The crystal's swing: a lower, longer whoosh with a faint shimmer of the crystal in it.
func _swing_crystal_a() -> PackedFloat32Array:
	var out := _buf(0.4)
	_whoosh(out, 0.0, 0.36, 300.0, 1300.0, 0.5, SEED + 8)
	_tone(out, 0.05, 0.3, Vector2(1568.0, 1568.0), Vector2(0.08, 0.1), 0.05)
	_tone(out, 0.05, 0.3, Vector2(2349.0, 2349.0), Vector2(0.08, 0.08), 0.03)
	return out


## A heavy two-handed heave: a low whoosh with a body.
func _swing_crystal_b() -> PackedFloat32Array:
	var out := _buf(0.4)
	_whoosh(out, 0.0, 0.36, 220.0, 900.0, 0.4, SEED + 9)
	_tone(out, 0.0, 0.36, Vector2(70.0, 110.0), Vector2(0.12, 0.12), 0.25)
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


## A cartoon fall: a slide whistle falling, then a thud.
func _knockdown_b() -> PackedFloat32Array:
	var out := _buf(0.85)
	_tone(out, 0.0, 0.45, Vector2(950.0, 240.0), Vector2(0.02, 0.4), 0.35, 0.03)
	_thud(out, 0.42, 95.0, 1.0, SEED + 13)
	return out


## One heavy thump with a short breath forced out ("oof" without a voice).
func _knockdown_c() -> PackedFloat32Array:
	var out := _buf(0.6)
	_thud(out, 0.0, 85.0, 1.0, SEED + 14)
	_noise(
		out, 0.02, 0.2, 0.35, Vector2(0.01, 0.07), Shape.BAND, Vector2(520.0, 420.0), 2.0, SEED + 15
	)
	_noise(
		out,
		0.02,
		0.18,
		0.2,
		Vector2(0.01, 0.06),
		Shape.BAND,
		Vector2(1100.0, 900.0),
		2.0,
		SEED + 16
	)
	return out


## Back on the feet: a soft rising sweep and a light pop.
func _revive_a() -> PackedFloat32Array:
	var out := _buf(0.6)
	_tone(out, 0.0, 0.45, Vector2(220.0, 660.0), Vector2(0.05, 0.35), 0.6, 0.0, Wave.TRIANGLE)
	_tone(out, 0.38, 0.2, Vector2(880.0, 1320.0), Vector2(0.003, 0.05), 0.4)
	return out


## Two rising soft notes (a fourth), rounder than the task's kalimba so they are never taken for it.
func _revive_b() -> PackedFloat32Array:
	var out := _buf(0.7)
	_tone(out, 0.0, 0.35, Vector2(293.66, 293.66), Vector2(0.01, 0.12), 0.6, 0.0, Wave.TRIANGLE)
	_tone(out, 0.14, 0.5, Vector2(392.0, 392.0), Vector2(0.01, 0.18), 0.6, 0.0, Wave.TRIANGLE)
	return out


## Death: a soft low bell, twice, falling a fourth.
func _death_a() -> PackedFloat32Array:
	var out := _buf(1.8)
	_fm(out, 0.0, 1.2, 220.0, 220.0, 3.5, 1.4, 0.004, 0.35, 0.5)
	_fm(out, 0.35, 1.4, 164.81, 164.81, 3.5, 1.4, 0.004, 0.45, 0.6)
	return out


## Death: a tone that deflates, sagging and wobbling down.
func _death_b() -> PackedFloat32Array:
	var out := _buf(1.3)
	_tone(out, 0.0, 1.2, Vector2(440.0, 140.0), Vector2(0.02, 0.5), 0.6, 0.06, Wave.TRIANGLE)
	_noise(
		out, 0.0, 1.1, 0.12, Vector2(0.05, 0.45), Shape.BAND, Vector2(1200.0, 300.0), 1.0, SEED + 17
	)
	return out


## Death: a hollow low chord fading out under a long breath.
func _death_c() -> PackedFloat32Array:
	var out := _buf(2.0)
	for f: float in [110.0, 130.81, 164.81]:
		_tone(out, 0.0, 1.9, Vector2(f, f * 0.97), Vector2(0.15, 0.8), 0.3, 0.0, Wave.TRIANGLE)
	_noise(
		out, 0.0, 1.8, 0.15, Vector2(0.3, 0.7), Shape.BAND, Vector2(900.0, 300.0), 0.8, SEED + 18
	)
	return out


## The drone prints you back, 2.1 s: its hover hum under the print head's stepping chirps rising
## from the feet up, a "ding" when done.
func _print_a() -> PackedFloat32Array:
	var out := _buf(2.4)
	_drone(out, 0.0, 2.2, 165.0, 0.35)
	var noise := _Noise.new(SEED + 19)
	var step := 0
	var at := 0.05
	while at < 1.95:
		var pitch := 700.0 + 600.0 * (at / 2.0) + 150.0 * absf(noise.next())
		_tone(out, at, 0.06, Vector2(pitch, pitch), Vector2(0.002, 0.03), 0.18, 0.0, Wave.SQUARE)
		step += 1
		at += 0.07
	_tone(out, 2.05, 0.35, Vector2(1568.0, 1568.0), Vector2(0.002, 0.12), 0.35)
	return out


## A scan up the body: a buzzy sweep rising over 2 s, a sparkle at the top.
func _print_b() -> PackedFloat32Array:
	var out := _buf(2.4)
	_drone(out, 0.0, 2.2, 150.0, 0.25)
	_tone(out, 0.0, 2.05, Vector2(180.0, 1200.0), Vector2(0.1, 0.1), 0.3, 0.0, Wave.SAW)
	for i in 8:
		var f := 2093.0 + 300.0 * float((i * 5) % 7)
		_tone(out, 2.0 + 0.03 * i, 0.3, Vector2(f, f), Vector2(0.003, 0.09), 0.12)
	return out


## The print head zips back and forth faster as the body fills, over the drone's hum.
func _print_c() -> PackedFloat32Array:
	var out := _buf(2.4)
	_drone(out, 0.0, 2.2, 180.0, 0.3)
	var at := 0.05
	var gap := 0.22
	var n := 0
	while at < 2.0:
		var lift := at / 2.0
		_noise(
			out,
			at,
			0.09,
			0.35,
			Vector2(0.004, 0.05),
			Shape.BAND,
			Vector2(1800.0 + 1800.0 * lift, 2800.0 + 1800.0 * lift),
			3.0,
			SEED + 20 + n
		)
		at += gap
		gap = maxf(0.08, gap * 0.9)
		n += 1
	_tone(out, 2.05, 0.3, Vector2(1046.5, 1046.5), Vector2(0.002, 0.1), 0.3)
	_tone(out, 2.1, 0.3, Vector2(1568.0, 1568.0), Vector2(0.002, 0.1), 0.25)
	return out
