class_name SpikeVoiceClicks
extends RefCounted
## Spike (#16): both ends of the acoustic mouth-to-ear measurement (SpikeVoiceOnsets explains it).
## The clicking listener: a click through its loudspeaker every `every` s (+-20 %), and voice
## only for ECHO_GATE_S after each one. The microphone client: every onset it hears, and at the end
## each click paired with its echo. Lines go to `log_line` (the walk spike's "WALK client ...").

## Long enough for the relayed click (one machine: about 0.4 s), too short for the echo of the
## echo. With the Voice bus open all the time the loudspeaker and the microphone feed back and howl.
const ECHO_GATE_S := 0.7

var log_line: Callable
var played := 0
var _every := 0.0
var _player: AudioStreamPlayer
var _bus := -1
var _next := -1.0
var _gate_until := -1.0
var _rng := RandomNumberGenerator.new()
var _onset_unix: Dictionary[int, float] = {}  # the microphone client's onsets by sample index


func _init(logger: Callable) -> void:
	log_line = logger


## The listener: clicks on the Master bus from `parent`, and gates the Voice bus `voice_bus`.
func start_clicking(parent: Node, voice_bus: int, every: float) -> void:
	_every = every
	_bus = voice_bus
	_player = AudioStreamPlayer.new()
	_player.stream = click_sound()
	parent.add_child(_player)
	_rng.seed = Time.get_ticks_usec()
	_next = 2.0  # after the host has placed everyone
	AudioServer.set_bus_mute(_bus, true)


## The listener, every frame, with the spike's clock.
func update(clock: float) -> void:
	if _gate_until >= 0.0 and clock >= _gate_until:
		_gate_until = -1.0
		AudioServer.set_bus_mute(_bus, true)
	if _player == null or clock < _next:
		return
	_player.play()
	_gate_until = clock + ECHO_GATE_S
	AudioServer.set_bus_mute(_bus, false)
	played += 1
	log_line.call("click n=%d unix=%.4f" % [played, Time.get_unix_time_from_system()])
	_next = clock + _every * _rng.randf_range(0.8, 1.2)


## The microphone client: onsets from SpikeVoiceSource.onsets, each [index, peak, unix].
func add_onsets(onsets: Array[Array], floor_level: float) -> void:
	for onset: Array in onsets:
		var index: int = onset[0]
		_onset_unix[index] = onset[2] as float
		log_line.call(
			(
				"click_onset index=%d peak=%.3f unix=%.4f floor=%.4f"
				% [index, onset[1], onset[2], floor_level]
			)
		)


## The microphone client, once at the end: each click and its echo, whose delay is the
## mouth-to-ear latency.
func log_echoes(rate: int) -> void:
	var indices: Array[int] = _onset_unix.keys()
	indices.sort()
	for p: Array in SpikeVoiceOnsets.echo_pairs(indices, rate):
		var click: int = p[0]
		var ms := ((p[1] as int) - click) * 1000.0 / rate
		log_line.call(
			"click_echo ms=%.1f click_index=%d click_unix=%.4f" % [ms, click, _onset_unix[click]]
		)
	_onset_unix.clear()


## 30 ms of a 200 Hz buzz with a sharp start. A buzz of harmonics, not a bare tick, so RNNoise
## takes it for voice and keeps it.
static func click_sound() -> AudioStreamWAV:
	var rate := 48000
	var count := roundi(0.03 * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var v := 0.0
		for k in range(1, 16):
			v += sin(TAU * 200.0 * k * t) / k
		var fade := minf(1.0, float(i) / 24.0) * minf(1.0, float(count - i) / 240.0)
		data.encode_s16(i * 2, roundi(clampf(0.45 * v * fade, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
