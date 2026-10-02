extends SceneTree
## The real codec's round trip and the FEC-or-concealment probe (E34, the M5 ADR §1.3), through
## TwoVoipCodec's boundary, as the M1 spike's codec_roundtrip.gd did it. On Windows with the addon
## in addons/twovoip/ (M5-3, and any PR that changes the codec adapter), headless:
##   tools\run.cmd run tests/integration/voice/twovoip_roundtrip.gd --headless
## Without the addon it prints "ROUNDTRIP SKIP" and exits 0. It is not a verify step: CI removes
## the addon (E35), and tests never load it.
##
## - The round trip: 2 s of a sine, 440 Hz and then 660 Hz from frame LOST on, encoded 20 ms at a
##   time (no denoiser: a tone is not speech), decoded into a playback and mixed back; it must keep
##   every frame and come back at the sine's frequency and at least half its level. Exit 0 on PASS,
##   1 on FAIL.
## - The probe: the same frames with frame LOST missing, decoded from the next packet with
##   `conceal` as VoiceJitter asks for it. In the lost frame's last 10 ms, FEC rebuilds the new
##   660 Hz from the data the next packet carries, while concealment can only extrapolate the 440 Hz
##   before the gap. It prints which, for M5-3's PR to record (whether v6.5 turns in-band FEC on is
##   unknown); it does not fail the run.

const RATE := 48000
const CHUNKS := 100
const LOST := 60
const FREQ := 440.0
const FREQ_AFTER := 660.0
const AMP := 0.5
## Mixed output skipped at the start (the codec's warm-up), in seconds.
const WARM_UP := 0.1


func _init() -> void:
	var codec := TwoVoipCodec.new()
	if not codec.available():
		print("ROUNDTRIP SKIP: the TwoVoIP addon is not loaded (addons/twovoip/, M5-3)")
		quit(0)
		return
	quit(0 if _run(codec) else 1)


func _run(codec: TwoVoipCodec) -> bool:
	var packets := _encode(codec)
	if packets.is_empty():
		return false
	var clean := _decode(codec, packets, -1)
	if clean.is_empty():
		return false
	var ok := _check_round_trip(clean)
	var probed := _decode(codec, packets, LOST)
	if not probed.is_empty():
		_probe(clean, probed)
	print("ROUNDTRIP ", "PASS" if ok else "FAIL")
	return ok


## The Opus packets of the test signal, or none on failure.
func _encode(codec: TwoVoipCodec) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	var encoder := codec.new_encoder()
	var error := "no encoder"
	if encoder != null:
		error = encoder.start(RATE, false)
	if error != "":
		print("ROUNDTRIP FAIL encoder: ", error)
		return packets
	var size := encoder.chunk_frames()
	print("ROUNDTRIP encoder ok, input chunk ", size)
	var bytes := 0
	for i: int in CHUNKS:
		var freq := FREQ if i < LOST else FREQ_AFTER
		var chunk := PackedVector2Array()
		chunk.resize(size)
		for j: int in size:
			var v := AMP * sin(TAU * freq * float(i * size + j) / RATE)
			chunk[j] = Vector2(v, v)
		var packet := encoder.encode(chunk)
		if packet.is_empty():
			print("ROUNDTRIP FAIL encoding chunk ", i)
			packets.clear()
			return packets
		packets.append(packet)
		bytes += packet.size()
	print("ROUNDTRIP encoded %d packets, %.1f bytes each" % [CHUNKS, float(bytes) / CHUNKS])
	return packets


## Every packet decoded and mixed at the audio server's rate; frame `lost` (unless -1) is missing
## and decoded from the next packet with `conceal`. Empty on failure.
func _decode(codec: TwoVoipCodec, packets: Array[PackedByteArray], lost: int) -> PackedVector2Array:
	var stream := codec.new_stream()
	var raw: AudioStreamPlayback = null
	if stream != null:
		raw = stream.instantiate_playback()
	var playback := TwoVoipPlayback.new(null, TwoVoipCodec.PLAYBACK_CLASS, raw)
	if not playback.bound():
		print("ROUNDTRIP FAIL no Opus playback")
		return PackedVector2Array()
	raw.start(0.0)
	for i: int in packets.size():
		if i == lost:
			playback.push(packets[i + 1], true)
		else:
			playback.push(packets[i], false)
	playback.set_running(true)
	var frames := playback.queued_frames()
	var want_frames := CHUNKS * TwoVoipEncoder.FRAME_SAMPLES
	print("ROUNDTRIP decoded %d frames (expected %d), lost frame %d" % [frames, want_frames, lost])
	if frames != want_frames:
		print("ROUNDTRIP FAIL decoded frame count")
		return PackedVector2Array()
	var mix_rate := AudioServer.get_mix_rate()
	return raw.mix_audio(1.0, int(mix_rate * frames / RATE))


func _check_round_trip(out: PackedVector2Array) -> bool:
	var mix_rate := AudioServer.get_mix_rate()
	var from := int(mix_rate * WARM_UP)
	var to := int(mix_rate * LOST * TwoVoipEncoder.FRAME_SAMPLES / RATE)
	if to - from <= 0 or out.size() < to:
		print("ROUNDTRIP FAIL mixed only ", out.size(), " frames")
		return false
	var sum_sq := 0.0
	var crossings := 0
	for k: int in range(from, to):
		var v := out[k].x
		sum_sq += v * v
		if k > from and (out[k - 1].x < 0.0) != (v < 0.0):
			crossings += 1
	var rms := sqrt(sum_sq / (to - from))
	var freq := crossings / 2.0 / ((to - from) / mix_rate)
	var sine_rms := AMP / sqrt(2.0)
	print("ROUNDTRIP rms %.3f (sine %.3f), freq %.1f Hz (sine %.0f)" % [rms, sine_rms, freq, FREQ])
	return absf(freq - FREQ) < 10.0 and rms > 0.5 * sine_rms


func _probe(clean: PackedVector2Array, probed: PackedVector2Array) -> void:
	var mix_rate := AudioServer.get_mix_rate()
	var frame := mix_rate * TwoVoipEncoder.FRAME_SAMPLES / RATE
	var from := int(mix_rate * LOST * TwoVoipEncoder.FRAME_SAMPLES / RATE + frame / 2.0)
	var to := int(from + frame / 2.0)
	if probed.size() < to:
		print("ROUNDTRIP FEC-PROBE mixed only ", probed.size(), " frames")
		return
	var after := _power(probed, from, to, FREQ_AFTER, mix_rate)
	var before := _power(probed, from, to, FREQ, mix_rate)
	var clean_after := _power(clean, from, to, FREQ_AFTER, mix_rate)
	var verdict := "FEC" if after > before else "CONCEALMENT"
	print(
		(
			(
				"ROUNDTRIP FEC-PROBE %s: in the lost frame's last 10 ms, power at %.0f Hz %.4f and at"
				+ " %.0f Hz %.4f (the clean decode: %.4f at %.0f Hz)"
			)
			% [verdict, FREQ_AFTER, after, FREQ, before, clean_after, FREQ_AFTER]
		)
	)


## The mean power of `out`'s left channel at `freq` over [from, to): one DFT bin.
func _power(out: PackedVector2Array, from: int, to: int, freq: float, mix_rate: float) -> float:
	var re := 0.0
	var im := 0.0
	for k: int in range(from, to):
		var phase := TAU * freq * k / mix_rate
		re += out[k].x * cos(phase)
		im -= out[k].x * sin(phase)
	var n := float(to - from)
	return (re * re + im * im) / (n * n)
