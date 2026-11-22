extends RefCounted
## The M8 sounds (#1674): the project's own synthesis, as engine_synth.gd (synth_voices.gd's sums,
## no sample, preset or recording). render_m8_sounds.gd writes them; each is mono 44.1 kHz 16-bit
## PCM, its mean taken out and scaled to its peak. CANDIDATES holds every take the engineer
## chooses from by ear; a pick keeps its function, the rest go.

const EngineSynth := preload("res://tools/sfx/engine_synth.gd")
## The scripts whose functions `_<take>` sum the takes.
const TAKES: Array[GDScript] = [
	preload("res://tools/sfx/m8_life_takes.gd"),
	preload("res://tools/sfx/m8_lobby_takes.gd"),
	preload("res://tools/sfx/m8_engine_takes.gd"),
]

## Every take by file name (without `.wav`) and its peak after the scaling; its sum is the
## function named `_<take>` below.
const CANDIDATES: Dictionary[StringName, float] = {
	# The hits, the swing, the knockdown, the raise, death and the return.
	&"hit_fist_a": 0.8,
	&"hit_fist_b": 0.8,
	&"hit_fist_c": 0.75,
	&"hit_crystal_a": 0.85,
	&"hit_crystal_b": 0.85,
	&"hit_crystal_c": 0.8,
	&"swing_fist_a": 0.5,
	&"swing_fist_b": 0.5,
	&"swing_crystal_a": 0.6,
	&"swing_crystal_b": 0.6,
	&"knockdown_a": 0.8,
	&"knockdown_b": 0.75,
	&"knockdown_c": 0.8,
	&"revive_a": 0.5,
	&"revive_b": 0.5,
	&"death_a": 0.55,
	&"death_b": 0.55,
	&"death_c": 0.6,
	&"print_a": 0.55,
	&"print_b": 0.55,
	&"print_c": 0.55,
	# The lobby: the bar, the pinball, the mirror.
	&"tap_pour_a": 0.55,
	&"tap_pour_b": 0.55,
	&"drink_a": 0.65,
	&"drink_b": 0.65,
	&"pinball_flipper_a": 0.6,
	&"pinball_flipper_b": 0.6,
	&"pinball_bumper_a": 0.6,
	&"pinball_bumper_b": 0.6,
	&"pinball_launch_a": 0.6,
	&"pinball_launch_b": 0.6,
	&"pinball_drain_a": 0.55,
	&"pinball_drain_b": 0.55,
	&"pinball_best_a": 0.5,
	&"pinball_best_b": 0.5,
	&"mirror_open_a": 0.45,
	&"mirror_open_b": 0.45,
	&"mirror_colour_a": 0.5,
	&"mirror_colour_b": 0.5,
	# The engine.
	&"engine_fixed_b": 0.5,
	&"engine_gill_open_a": 0.55,
	&"engine_gill_open_b": 0.55,
	&"engine_gill_shut_a": 0.6,
	&"engine_gill_shut_b": 0.6,
	&"engine_breaker_trip_a": 0.7,
	&"engine_breaker_trip_b": 0.7,
	&"engine_breaker_on_a": 0.65,
	&"engine_breaker_on_b": 0.65,
	&"engine_breaker_green_a": 0.4,
	&"engine_zap_k1": 0.7,
	&"engine_crystal_in_a": 0.65,
	&"engine_crystal_in_b": 0.65,
	&"engine_crystal_out_a": 0.55,
	&"engine_charging_a": 0.5,
	&"engine_charging_b": 0.5,
	&"engine_charged_a": 0.5,
	&"engine_charged_b": 0.5,
	# The match timer.
	&"timer_tick_a": 0.4,
	&"timer_tick_b": 0.4,
	&"timer_up_a": 0.6,
	&"timer_up_b": 0.6,
}


## The samples of take `take` (a key of CANDIDATES), from -1 to 1; empty for another name.
static func samples(take: StringName) -> PackedFloat32Array:
	if not CANDIDATES.has(take):
		return PackedFloat32Array()
	var method := "_%s" % take
	for script: GDScript in TAKES:
		var takes: Object = script.new()
		if takes.has_method(method):
			var raw: PackedFloat32Array = takes.call(method)
			return EngineSynth.scaled(raw, CANDIDATES[take])
	return PackedFloat32Array()
