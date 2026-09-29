extends SceneTree
## Spike (#12): headless Opus round trip through TwoVoIP without a microphone.
## A 440 Hz sine is encoded chunk by chunk, the packets are pushed into an
## AudioStreamPlaybackOpus and mixed back with AudioStreamPlayback.mix_audio.
## Prints ROUNDTRIP lines and exits 0 on success, 1 on failure. Run:
##   <godot console exe> --headless --path . -s res://spike/voice/codec_roundtrip.gd

const RATE := 48000
const CHUNK := 960  # 20 ms at 48 kHz
const CHUNKS := 100  # 2 s of audio
const FREQ := 440.0
const AMP := 0.5


func _init() -> void:
	var packets := _encode()
	quit(0 if not packets.is_empty() and _decode_and_measure(packets) else 1)


## Returns the Opus packets, or an empty array on failure.
func _encode() -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	var enc := TwovoipOpusEncoder.new()
	var err: int = enc.initialize(
		RATE, RATE, 1, TwovoipOpusEncoder.DENOISER_DISABLED, TwovoipOpusEncoder.AGC_DISABLED, CHUNK
	)
	if err != OK or not enc.create_opus_encoder(24000, 5, true):
		print("ROUNDTRIP FAIL encoder setup: ", error_string(err))
		return packets
	var in_size: int = enc.get_required_input_chunk_size()
	print("ROUNDTRIP encoder ok, required input chunk ", in_size)
	var bytes := 0
	var t := 0
	for i in CHUNKS:
		var frames := PackedVector2Array()
		frames.resize(in_size)
		for j in in_size:
			var s := AMP * sin(TAU * FREQ * float(t) / RATE)
			frames[j] = Vector2(s, s)
			t += 1
		var packet := PackedByteArray()
		if enc.process_chunk(frames) >= 0:
			packet = enc.encode_chunk(PackedByteArray())
		if packet.is_empty():
			print("ROUNDTRIP FAIL encoding chunk ", i)
			packets.clear()
			return packets
		packets.append(packet)
		bytes += packet.size()
	print("ROUNDTRIP encoded %d packets, %d bytes, avg %d" % [CHUNKS, bytes, bytes / CHUNKS])
	return packets


func _decode_and_measure(packets: Array[PackedByteArray]) -> bool:
	var stream := AudioStreamOpus.new()
	stream.set_opus_sample_rate(RATE)
	stream.set_opus_channels(1)
	stream.set_buffer_length(3.0)
	var playback := stream.instantiate_playback() as AudioStreamPlaybackOpus
	if playback == null:
		print("ROUNDTRIP FAIL instantiate_playback")
		return false
	playback.start()
	for p in packets:
		playback.push_opus_packet(p, 0, 0)
	playback.mark_end_opus_stream(true)
	var decoded: int = playback.queue_length_frames()
	print("ROUNDTRIP decoded %d frames (expected %d)" % [decoded, CHUNKS * CHUNK])
	if decoded != CHUNKS * CHUNK:
		print("ROUNDTRIP FAIL decoded frame count")
		return false

	var mix_rate: float = AudioServer.get_mix_rate()
	var want := int(mix_rate * float(CHUNKS * CHUNK) / RATE)
	var out: PackedVector2Array = playback.mix_audio(1.0, want)
	# Skip the first 0.1 s (codec warm-up) when measuring.
	var skip := int(mix_rate * 0.1)
	var n_meas := out.size() - skip
	if n_meas <= 0:
		print("ROUNDTRIP FAIL mixed only ", out.size(), " frames")
		return false
	var sum_sq := 0.0
	var crossings := 0
	var prev := 0.0
	for k in range(skip, out.size()):
		var v: float = out[k].x
		sum_sq += v * v
		if k > skip and (prev < 0.0) != (v < 0.0):
			crossings += 1
		prev = v
	var rms := sqrt(sum_sq / n_meas)
	var freq := crossings / 2.0 / (n_meas / mix_rate)
	var sine_rms := AMP / sqrt(2.0)
	print(
		(
			"ROUNDTRIP mixed %d/%d frames at %d Hz; rms %.3f (sine %.3f), freq %.1f Hz"
			% [out.size(), want, int(mix_rate), rms, sine_rms, freq]
		)
	)
	var ok := absf(freq - FREQ) < 10.0 and rms > 0.5 * sine_rms
	print("ROUNDTRIP ", "PASS" if ok else "FAIL")
	return ok
