class_name SpikeVoiceSpeaker
extends RefCounted
## Spike (#15): one remote speaker as a listener hears it. An AudioStreamPlayer3D, a child of the
## speaker's avatar at mouth height, plays the relayed Opus frames through SpikeVoiceJitter.
## Spatialization happens here, on the listener (ARCHITECTURE §6): the listener is the client's
## current Camera3D. Falloff: ATTENUATION_DISABLED with max_distance is linear attenuation clamped
## to a sphere (Godot 4.7 docs), so with max_distance = the host's cutoff the volume reaches zero
## about where the host stops delivering (see SpikeVoiceRouting for why not exactly), and delivery
## switching on or off makes no audible step.

var jitter := SpikeVoiceJitter.new()
var player := AudioStreamPlayer3D.new()
var overflow := 0  # frames dropped because the playback queue was full
var _playback: AudioStreamPlaybackOpus


func _init(cutoff: float, bus: StringName) -> void:
	var stream := AudioStreamOpus.new()
	stream.set_opus_sample_rate(SpikeVoiceSource.OPUS_RATE)
	stream.set_opus_channels(1)
	player.stream = stream
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = cutoff
	player.bus = bus


## Puts the player on the avatar and starts it paused until the prebuffer is full. Returns false
## when the stream gives no Opus playback.
func attach(avatar: Node3D, mouth: Vector3) -> bool:
	player.position = mouth
	avatar.add_child(player)
	player.play()
	_playback = player.get_stream_playback() as AudioStreamPlaybackOpus
	if _playback == null:
		return false
	_playback.mark_end_opus_stream(false)
	return true


func push(seq: int, opus: PackedByteArray) -> void:
	jitter.push(seq, opus)


## Decodes the frames that are due and starts or stops the playback; call every frame.
func update() -> void:
	if _playback == null:
		return
	for frame: Array in jitter.pop():
		if _playback.available_space_frames() < SpikeVoiceSource.CHUNK:
			overflow += 1
			continue
		_playback.push_opus_packet(frame[0] as PackedByteArray, 0, frame[1] as int)
	match jitter.gate(_playback.queue_length_frames()):
		SpikeVoiceJitter.Gate.START:
			_playback.mark_end_opus_stream(true)
		SpikeVoiceJitter.Gate.STOP:
			_playback.mark_end_opus_stream(false)


func queue_ms() -> float:
	if _playback == null:
		return 0.0
	return _playback.queue_length_frames() * 1000.0 / SpikeVoiceSource.OPUS_RATE


func stats() -> String:
	var j := jitter
	return (
		"recv=%d late=%d fec=%d lost=%d resets=%d underruns=%d overflow=%d queue_ms=%.0f"
		% [j.received, j.late, j.fec, j.lost, j.resets, j.underruns, overflow, queue_ms()]
	)
