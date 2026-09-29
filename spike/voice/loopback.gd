extends Control
## Spike (#12): local microphone loopback through TwoVoIP.
## Microphone -> TwovoipOpusEncoder -> Opus packets -> AudioStreamPlaybackOpus -> speakers,
## all on this machine. Use headphones: with speakers the loop feeds back. Prints LOOPBACK stats
## every 2 s; closes after --quit-after-seconds N if given after "--" on the command line.

const OPUS_RATE := 48000
const CHUNK := 960  # 20 ms at 48 kHz
const PREBUFFER_FRAMES := 4800  # 100 ms before playback starts
const STATS_EVERY := 2.0

var _enc := TwovoipOpusEncoder.new()
var _player := AudioStreamPlayer.new()
var _playback: AudioStreamPlaybackOpus
var _label := Label.new()
var _paused := true
var _packets := 0
var _bytes := 0
var _peak := 0.0
var _since_stats := 0.0
var _elapsed := 0.0
var _quit_after := -1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var qi := args.find("--quit-after-seconds")
	if qi >= 0 and qi + 1 < args.size():
		_quit_after = args[qi + 1].to_float()

	_label.position = Vector2(16, 16)
	add_child(_label)
	add_child(_player)

	print("LOOPBACK input devices: ", AudioServer.get_input_device_list())
	print(
		"LOOPBACK input device: ",
		AudioServer.input_device,
		", output device: ",
		AudioServer.output_device
	)
	var err := AudioServer.set_input_device_active(true)
	if err != OK:
		_fail(
			(
				"set_input_device_active: %s (is audio/driver/enable_input on? Windows mic privacy?)"
				% error_string(err)
			)
		)
		return
	var in_rate := int(AudioServer.get_input_mix_rate())
	print("LOOPBACK input mix rate ", in_rate, ", output mix rate ", AudioServer.get_mix_rate())

	err = _enc.initialize(
		in_rate,
		OPUS_RATE,
		1,
		TwovoipOpusEncoder.DENOISER_RNNOISE,
		TwovoipOpusEncoder.AGC_DISABLED,
		CHUNK
	)
	if err != OK:
		_fail("encoder initialize: %s" % error_string(err))
		return
	if not _enc.create_opus_encoder(24000, 5, true):
		_fail("create_opus_encoder")
		return
	print("LOOPBACK encoder ok, required input chunk ", _enc.get_required_input_chunk_size())

	var stream := AudioStreamOpus.new()
	stream.set_opus_sample_rate(OPUS_RATE)
	stream.set_opus_channels(1)
	_player.stream = stream
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamPlaybackOpus
	if _playback == null:
		_fail("no AudioStreamPlaybackOpus")
		return
	# The playback starts paused on its end mark; it is released once PREBUFFER_FRAMES are queued.
	_playback.mark_end_opus_stream(false)


func _process(delta: float) -> void:
	_elapsed += delta
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		_stats()
		print("LOOPBACK quit after ", _quit_after, " s")
		get_tree().quit(0)
		return
	if _playback == null:
		return
	var in_size: int = _enc.get_required_input_chunk_size()
	while AudioServer.get_input_frames_available() >= in_size:
		var frames: PackedVector2Array = AudioServer.get_input_frames(in_size)
		if frames.size() < in_size or _enc.process_chunk(frames) < 0:
			break
		_peak = maxf(_peak, _enc.get_peak())
		var packet: PackedByteArray = _enc.encode_chunk(PackedByteArray())
		if packet.is_empty():
			continue
		_packets += 1
		_bytes += packet.size()
		_playback.push_opus_packet(packet, 0, 0)
	if _paused and _playback.queue_length_frames() >= PREBUFFER_FRAMES:
		_playback.mark_end_opus_stream(true)
		_paused = false
		print("LOOPBACK playback started")
	_since_stats += delta
	if _since_stats >= STATS_EVERY:
		_stats()
		_since_stats = 0.0


func _exit_tree() -> void:
	_player.stop()
	AudioServer.set_input_device_active(false)


func _stats() -> void:
	if _playback == null:
		return
	var queue_ms := _playback.queue_length_frames() * 1000.0 / OPUS_RATE
	var kbps := _bytes * 8.0 / 1000.0 / maxf(_elapsed, 0.001)
	var line := (
		(
			"t=%.1fs packets=%d avg=%dB %.1fkbit/s mic_peak=%.3f queue=%.0fms"
			+ " skips=%d overflow_skips=%d"
		)
		% [
			_elapsed,
			_packets,
			_bytes / maxi(_packets, 1),
			kbps,
			_peak,
			queue_ms,
			_playback.get_skips(false),
			_playback.get_skips(true),
		]
	)
	print("LOOPBACK ", line)
	_label.text = "TwoVoIP loopback (use headphones)\n" + line.replace(" ", "\n")
	_peak = 0.0


func _fail(msg: String) -> void:
	push_error("LOOPBACK FAIL " + msg)
	_label.text = "LOOPBACK FAIL " + msg
	print("LOOPBACK FAIL ", msg)
