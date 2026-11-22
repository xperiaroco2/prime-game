extends RefCounted
## The M8 sounds (#1674): the project's own synthesis, as engine_synth.gd (synth_voices.gd's sums,
## no sample, preset or recording). render_m8_sounds.gd writes them to assets/audio/prime_m8/; each
## is mono 44.1 kHz 16-bit PCM, its mean taken out and scaled to its peak. The engineer picked each
## by ear on a listening page of 61 takes (2026-11-23, "все по рекомендаціях": every recommended
## take); the rest were dropped.

const EngineSynth := preload("res://tools/sfx/engine_synth.gd")
const FOLDER := "res://assets/audio/prime_m8/"
## The scripts whose functions `_<take>` sum the takes.
const TAKES: Array[GDScript] = [
	preload("res://tools/sfx/m8_life_takes.gd"),
	preload("res://tools/sfx/m8_lobby_takes.gd"),
	preload("res://tools/sfx/m8_engine_takes.gd"),
]

## Each sound's file name (without `.wav`, SfxSet's id) and the take it is: the function named
## `_<take>`.
const PICKS: Dictionary[StringName, StringName] = {
	&"hit_fist": &"hit_fist_a",
	&"hit_heavy": &"hit_crystal_a",
	&"swing": &"swing_fist_a",
	&"swing_heavy": &"swing_crystal_a",
	&"knockdown": &"knockdown_a",
	&"revive": &"revive_a",
	&"death": &"death_a",
	&"respawn": &"print_a",
	&"tap_pour": &"tap_pour_a",
	&"drink": &"drink_b",
	&"pinball_flipper": &"pinball_flipper_a",
	&"pinball_bumper": &"pinball_bumper_a",
	&"pinball_launch": &"pinball_launch_a",
	&"pinball_drain": &"pinball_drain_a",
	&"pinball_best": &"pinball_best_a",
	&"mirror_open": &"mirror_open_a",
	&"engine_gill_open": &"engine_gill_open_a",
	&"engine_gill_shut": &"engine_gill_shut_a",
	&"engine_breaker_trip": &"engine_breaker_trip_a",
	&"engine_breaker_on": &"engine_breaker_on_a",
	&"engine_breaker_green": &"engine_breaker_green_a",
	&"engine_zap": &"engine_zap_k1",
	&"engine_crystal_charger": &"engine_crystal_in_a",
	&"engine_crystal_socket": &"engine_crystal_in_b",
	&"engine_charging": &"engine_charging_a",
	&"engine_charged": &"engine_charged_a",
	&"timer_tick": &"timer_tick_a",
}
## Each sound's peak after the scaling.
const PEAKS: Dictionary[StringName, float] = {
	&"hit_fist": 0.8,
	&"hit_heavy": 0.85,
	&"swing": 0.5,
	&"swing_heavy": 0.6,
	&"knockdown": 0.8,
	&"revive": 0.5,
	&"death": 0.55,
	&"respawn": 0.55,
	&"tap_pour": 0.55,
	&"drink": 0.65,
	&"pinball_flipper": 0.6,
	&"pinball_bumper": 0.6,
	&"pinball_launch": 0.6,
	&"pinball_drain": 0.55,
	&"pinball_best": 0.5,
	&"mirror_open": 0.45,
	&"engine_gill_open": 0.55,
	&"engine_gill_shut": 0.6,
	&"engine_breaker_trip": 0.7,
	&"engine_breaker_on": 0.65,
	&"engine_breaker_green": 0.4,
	&"engine_zap": 0.7,
	&"engine_crystal_charger": 0.65,
	&"engine_crystal_socket": 0.65,
	&"engine_charging": 0.5,
	&"engine_charged": 0.5,
	&"timer_tick": 0.4,
}
## The sounds that loop (their sum crossfades its end into its start): imported with a forward
## loop.
const LOOPS: Array[StringName] = [&"engine_charging"]


## The samples of sound `sound_name` (a key of PICKS), from -1 to 1; empty for another name.
static func samples(sound_name: StringName) -> PackedFloat32Array:
	if not PICKS.has(sound_name):
		return PackedFloat32Array()
	var method := "_%s" % PICKS[sound_name]
	for script: GDScript in TAKES:
		var takes: Object = script.new()
		if takes.has_method(method):
			var raw: PackedFloat32Array = takes.call(method)
			return EngineSynth.scaled(raw, PEAKS[sound_name])
	return PackedFloat32Array()
