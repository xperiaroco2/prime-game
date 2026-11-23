extends "res://tools/sfx/synth_voices.gd"
## The ship's engine and the match timer (#1674): the M8 takes, each a
## function `_<take>` (m8_synth.gd's PICKS) returning its samples before the scaling.


## A gill opens: the slit turns cyan with a puff of steam and a soft tick.
func _engine_gill_open_a() -> PackedFloat32Array:
	var out := _buf(0.6)
	_noise(
		out, 0.0, 0.5, 0.7, Vector2(0.01, 0.15), Shape.HIGH, Vector2(2400.0, 1600.0), 0.7, SEED + 51
	)
	_noise(
		out,
		0.0,
		0.03,
		0.4,
		Vector2(0.0005, 0.01),
		Shape.BAND,
		Vector2(1300.0, 1300.0),
		4.0,
		SEED + 52
	)
	return out


## A gill shuts again (pressed on an open one): a dull clack and a short hiss that dies.
func _engine_gill_shut_a() -> PackedFloat32Array:
	var out := _buf(0.4)
	_noise(
		out,
		0.0,
		0.04,
		0.8,
		Vector2(0.0005, 0.012),
		Shape.BAND,
		Vector2(900.0, 900.0),
		2.0,
		SEED + 54
	)
	_tone(out, 0.0, 0.15, Vector2(150.0, 90.0), Vector2(0.001, 0.04), 0.8)
	_noise(
		out,
		0.02,
		0.25,
		0.25,
		Vector2(0.002, 0.06),
		Shape.HIGH,
		Vector2(3000.0, 3000.0),
		0.7,
		SEED + 55
	)
	return out


## A breaker trips: it pops out like a cork, then smoke fizzes (the board's v5 stand-in for the
## cork recording he liked).
func _engine_breaker_trip_a() -> PackedFloat32Array:
	var out := _buf(1.6)
	_tone(out, 0.0, 0.08, Vector2(620.0, 240.0), Vector2(0.002, 0.03), 0.9)
	_noise(
		out,
		0.0,
		0.06,
		0.8,
		Vector2(0.0005, 0.015),
		Shape.HIGH,
		Vector2(1500.0, 1500.0),
		0.7,
		SEED + 57
	)
	_smoke(out, 0.05, 1.5, SEED + 58)
	return out


## A breaker switched on: the clunk and the decided hum Г1 (pure tones with overtones, 110 Hz and a
## slow beat) doubling in pitch while the lamp ramps yellow to green (1.4 s, the board's RAMP_S).
func _engine_breaker_on_a() -> PackedFloat32Array:
	var out := _buf(1.6)
	_clunk(out, 0.0, SEED + 61)
	_hum_g1(out, 0.05, 1.5)
	return out


## The breaker's lamp turns green: the board's light two-note ding.
func _engine_breaker_green_a() -> PackedFloat32Array:
	var out := _buf(0.3)
	_tone(out, 0.0, 0.15, Vector2(1046.5, 1046.5), Vector2(0.005, 0.05), 0.6)
	_tone(out, 0.06, 0.14, Vector2(1568.0, 1568.0), Vector2(0.005, 0.05), 0.45)
	return out


## The short circuit К1, decided on the board (2026-10-27): three falling cartoon zips, then an FM
## "bzzzt" falling from 260 to 120 Hz.
func _engine_zap_k1() -> PackedFloat32Array:
	var out := _buf(0.45)
	for i in 3:
		_tone(out, 0.06 * i, 0.06, Vector2(2400.0 - 300.0 * i, 600.0), Vector2(0.002, 0.02), 0.6)
	_fm(out, 0.16, 0.22, 260.0, 120.0, 0.18, 0.8, 0.002, 0.1, 0.7)
	return out


## The crystal fitted (a socket or the charger's slot): the board's latch, a knock and a low click.
func _engine_crystal_in_a() -> PackedFloat32Array:
	var out := _buf(0.3)
	_noise(
		out,
		0.0,
		0.06,
		1.0,
		Vector2(0.001, 0.02),
		Shape.BAND,
		Vector2(1100.0, 1100.0),
		4.0,
		SEED + 63
	)
	_tone(out, 0.0, 0.04, Vector2(2600.0, 2600.0), Vector2(0.001, 0.01), 0.15)
	_tone(out, 0.01, 0.12, Vector2(140.0, 95.0), Vector2(0.003, 0.04), 0.7)
	return out


## The crystal fitted: the latch, then its light rising back (the board's "home" without the U2).
func _engine_crystal_in_b() -> PackedFloat32Array:
	var out := _buf(0.8)
	_noise(
		out,
		0.0,
		0.06,
		1.0,
		Vector2(0.001, 0.02),
		Shape.BAND,
		Vector2(1100.0, 1100.0),
		4.0,
		SEED + 64
	)
	_tone(out, 0.01, 0.12, Vector2(140.0, 95.0), Vector2(0.003, 0.04), 0.7)
	_tone(out, 0.08, 0.6, Vector2(220.0, 880.0), Vector2(0.02, 0.2), 0.35, 0.0, Wave.TRIANGLE)
	for i in 5:
		var f := 2093.0 + 270.0 * float((i * 3) % 4)
		_tone(out, 0.2 + 0.09 * i, 0.3, Vector2(f, f), Vector2(0.005, 0.1), 0.08)
	return out


## The charger's lightning, a 2 s loop to repeat for the charge: a warm hum with a tremolo, a
## whistle orbiting and sparse crackles (the board's charger without its rise).
func _engine_charging_a() -> PackedFloat32Array:
	var out := _buf(2.0)
	_loop_hum(out, 165.0, 8.0, 0.5)
	var noise := _Noise.new(SEED + 66)
	for i in 14:
		var at := 0.1 + 1.8 * absf(noise.next())
		_noise(
			out,
			at,
			0.03,
			0.25,
			Vector2(0.0005, 0.008),
			Shape.BAND,
			Vector2(2200.0 + 1800.0 * absf(noise.next()), 3000.0),
			2.0,
			SEED + 67 + i
		)
	_orbit(out, 1900.0, 2.0, 0.18, SEED + 90)
	return _looped(out)


## The crystal charged: the board's glassy bell (two notes, never the kalimba) and glints.
func _engine_charged_a() -> PackedFloat32Array:
	var out := _buf(1.6)
	_fm(out, 0.0, 1.4, 1174.66, 1174.66, 3.5, 1.4, 0.004, 0.35, 0.6)
	_fm(out, 0.09, 1.4, 1567.98, 1567.98, 3.5, 1.4, 0.004, 0.35, 0.45)
	_glints(out, 0.1, 1.2, 8, 0.12, SEED + 92)
	return out


# --- The match timer ----------------------------------------------------------------------------


## One of the last ten seconds: a soft wooden tick.
func _timer_tick_a() -> PackedFloat32Array:
	var out := _buf(0.12)
	_noise(
		out,
		0.0,
		0.06,
		1.0,
		Vector2(0.0005, 0.012),
		Shape.BAND,
		Vector2(1300.0, 1300.0),
		4.0,
		SEED + 94
	)
	_tone(out, 0.0, 0.06, Vector2(880.0, 880.0), Vector2(0.001, 0.015), 0.3)
	return out
