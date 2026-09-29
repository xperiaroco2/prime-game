extends SceneTree
## Spike (#16): the CPU cost of one voice stream through TwoVoIP v6.5, headless, no microphone.
## Encode side, per 20 ms frame, in SpikeVoiceSource's settings (48 kHz mono Opus, 24 kbit/s,
## complexity 5, voice_optimal): process_chunk (resampling to 48 kHz and, for a microphone,
## RNNoise) and encode_chunk (Opus). Decode side: push_opus_packet (Opus decode into the playback
## queue, as SpikeVoiceSpeaker does; decode_fec 0 and 1) and mix_audio (the playback's resampling
## to the mix rate, done by the audio thread). Not covered: the AudioStreamPlayer3D's panning and
## attenuation in the audio thread, and the mixing of buses.
## Every case runs RUNS times over FRAMES frames; the median run is reported. Run from the root:
##   <godot console exe> --headless --path . -s res://spike/voice/codec_bench.gd
## Prints "BENCH ..." lines and exits 0, or 1 when the codec fails.

const OPUS_RATE := 48000
const CHUNK := 960  # 20 ms at 48 kHz
const FRAME_US := 20000.0
const BIT_RATE := 24000
const COMPLEXITY := 5
const FRAMES := 1500  # 30 s of audio
const RUNS := 5
const MIX_BLOCK := 512  # frames per mix_audio call, about an audio driver buffer

var _ok := true
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	print(
		(
			"BENCH godot=%s cpu='%s' cores=%d frames=%d runs=%d mix_rate=%d"
			% [
				Engine.get_version_info()["string"],
				OS.get_processor_name(),
				OS.get_processor_count(),
				FRAMES,
				RUNS,
				int(AudioServer.get_mix_rate())
			]
		)
	)
	var packets: Dictionary[String, Array] = {}
	for sig: String in ["voiced", "tone", "noise", "silence"]:
		for in_rate: int in [48000, 44100]:
			for denoise: bool in [false, true]:
				var got := _bench_encode(sig, in_rate, denoise)
				if in_rate == OPUS_RATE and not denoise:
					packets[sig] = got
	for sig: String in packets:
		_bench_decode(sig, packets[sig])
	quit(0 if _ok else 1)


## Encodes FRAMES frames of `sig` RUNS times and prints the median run; returns its packets.
func _bench_encode(sig: String, in_rate: int, denoise: bool) -> Array[PackedByteArray]:
	var process_us: Array[float] = []
	var encode_us: Array[float] = []
	var p99_us: Array[float] = []
	var packets: Array[PackedByteArray] = []
	for run in RUNS:
		var enc := TwovoipOpusEncoder.new()
		var mode := (
			TwovoipOpusEncoder.DENOISER_RNNOISE if denoise else TwovoipOpusEncoder.DENOISER_DISABLED
		)
		var code: int = enc.initialize(
			in_rate, OPUS_RATE, 1, mode, TwovoipOpusEncoder.AGC_DISABLED, CHUNK
		)
		if code != OK or not enc.create_opus_encoder(BIT_RATE, COMPLEXITY, true):
			print("BENCH FAIL encoder setup ", error_string(code))
			_ok = false
			return packets
		var in_size: int = enc.get_required_input_chunk_size()
		var chunks: Array[PackedVector2Array] = []
		_rng.seed = 16
		for i in FRAMES:
			chunks.append(_signal(sig, i * in_size, in_size, in_rate))
		packets.clear()
		var t_process := 0
		var t_encode := 0
		var per_frame: Array[int] = []
		for chunk in chunks:
			var t0 := Time.get_ticks_usec()
			var got: int = enc.process_chunk(chunk)
			var t1 := Time.get_ticks_usec()
			var packet: PackedByteArray = enc.encode_chunk(PackedByteArray())
			var t2 := Time.get_ticks_usec()
			if got < 0 or packet.is_empty():
				print("BENCH FAIL encoding ", sig)
				_ok = false
				return packets
			t_process += t1 - t0
			t_encode += t2 - t1
			per_frame.append(t2 - t0)
			packets.append(packet)
		per_frame.sort()
		process_us.append(float(t_process) / FRAMES)
		encode_us.append(float(t_encode) / FRAMES)
		p99_us.append(float(per_frame[int(FRAMES * 0.99)]))
	var sizes: Array[int] = []
	for p in packets:
		sizes.append(p.size())
	sizes.sort()
	var total := 0
	for s in sizes:
		total += s
	var process := _median(process_us)
	var encode := _median(encode_us)
	print(
		(
			(
				"BENCH encode sig=%s in_rate=%d rnnoise=%s process_us=%.1f encode_us=%.1f"
				+ " total_us=%.1f p99_us=%.0f core_pct=%.3f bytes_mean=%.1f bytes_min=%d bytes_max=%d"
			)
			% [
				sig,
				in_rate,
				denoise,
				process,
				encode,
				process + encode,
				_median(p99_us),
				(process + encode) / FRAME_US * 100.0,
				float(total) / sizes.size(),
				sizes[0],
				sizes[-1]
			]
		)
	)
	return packets


## Decodes the packets RUNS times as SpikeVoiceSpeaker does, then mixes them out; prints the median.
func _bench_decode(sig: String, packets: Array) -> void:
	for fec: int in [0, 1]:
		var decode_us: Array[float] = []
		var mix_us: Array[float] = []
		for run in RUNS:
			var stream := AudioStreamOpus.new()
			stream.set_opus_sample_rate(OPUS_RATE)
			stream.set_opus_channels(1)
			stream.set_buffer_length(float(FRAMES * CHUNK) / OPUS_RATE + 2.0)
			var playback := stream.instantiate_playback() as AudioStreamPlaybackOpus
			if playback == null:
				print("BENCH FAIL instantiate_playback")
				_ok = false
				return
			playback.start()
			var t0 := Time.get_ticks_usec()
			for p: PackedByteArray in packets:
				playback.push_opus_packet(p, 0, fec)
			var t1 := Time.get_ticks_usec()
			playback.mark_end_opus_stream(true)
			var queued: int = playback.queue_length_frames()
			if queued != FRAMES * CHUNK:
				print("BENCH FAIL decoded %d frames, expected %d" % [queued, FRAMES * CHUNK])
				_ok = false
				return
			var want := int(AudioServer.get_mix_rate() * FRAMES * CHUNK / OPUS_RATE)
			var mixed := 0
			var t2 := Time.get_ticks_usec()
			while mixed < want:
				mixed += playback.mix_audio(1.0, mini(MIX_BLOCK, want - mixed)).size()
			var t3 := Time.get_ticks_usec()
			decode_us.append(float(t1 - t0) / FRAMES)
			mix_us.append(float(t3 - t2) / FRAMES)
		var decode := _median(decode_us)
		var mix := _median(mix_us)
		print(
			(
				"BENCH decode sig=%s fec=%d decode_us=%.1f mix_us=%.1f total_us=%.1f core_pct=%.3f"
				% [sig, fec, decode, mix, decode + mix, (decode + mix) / FRAME_US * 100.0]
			)
		)


## `count` stereo frames of the test signal from sample `first` on, at `rate`.
func _signal(sig: String, first: int, count: int, rate: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var t := float(first + i) / rate
		var v := 0.0
		match sig:
			"tone":  # SpikeVoiceSource's tone
				v = 0.3 * (0.7 + 0.3 * sin(TAU * 2.0 * t)) * sin(TAU * 440.0 * t)
			"voiced":  # a buzz of harmonics at a wobbling pitch, in syllables of 4 per second
				var f0 := 120.0 + 15.0 * sin(TAU * 0.7 * t)
				var phase := TAU * (120.0 * t - 15.0 / (TAU * 0.7) * cos(TAU * 0.7 * t))
				for k in range(1, 25):
					if k * f0 < 4000.0:
						v += sin(k * phase) / k
				var syllable := maxf(0.0, sin(TAU * 4.0 * t))
				v = 0.15 * v * syllable * syllable + _rng.randf_range(-0.005, 0.005)
			"noise":
				v = _rng.randf_range(-0.1, 0.1)
		frames[i] = Vector2(v, v)
	return frames


static func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[floori(sorted.size() / 2.0)]
