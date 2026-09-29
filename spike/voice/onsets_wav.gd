extends SceneTree
## Spike (#16): runs the acoustic latency detector (SpikeVoiceOnsets) again over a microphone dump
## from `launch.ps1 -Latency` (client1-mic.wav, mono 16-bit), so a changed detector can be checked
## on real recordings. Prints "WAV ..." lines. Run from the project root:
##   <godot console exe> --headless --path . -s res://spike/voice/onsets_wav.gd -- <file.wav>

const CHUNK := 960
const HEADER := 44  # the canonical header AudioStreamWAV.save_to_wav writes


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("WAV FAIL no file given")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(args[0])
	if bytes.size() <= HEADER or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		print("WAV FAIL not a WAV file: ", args[0])
		quit(1)
		return
	var rate := bytes.decode_u32(24)
	var samples := floori((bytes.size() - HEADER) / 2.0)
	var detector := SpikeVoiceOnsets.new(rate)
	var indices: Array[int] = []
	for first in range(0, samples, CHUNK):
		var count := mini(CHUNK, samples - first)
		var frames := PackedVector2Array()
		frames.resize(count)
		for i in count:
			var v := bytes.decode_s16(HEADER + (first + i) * 2) / 32768.0
			frames[i] = Vector2(v, v)
		for onset: Array in detector.feed(frames):
			indices.append(onset[0] as int)
	var delays: Array[float] = []
	for p: Array in SpikeVoiceOnsets.echo_pairs(indices, rate):
		delays.append(((p[1] as int) - (p[0] as int)) * 1000.0 / rate)
	var shown := PackedStringArray()
	for d in delays:
		shown.append("%.1f" % d)
	print(
		(
			"WAV %s rate=%d seconds=%.1f onsets=%d pairs=%d"
			% [args[0].get_file(), rate, float(samples) / rate, indices.size(), delays.size()]
		)
	)
	print("WAV delays_ms: ", " ".join(shown))
	quit(0)
