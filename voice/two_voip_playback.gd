class_name TwoVoipPlayback
extends VoicePlayback
## TwoVoipCodec's playback: the addon's Opus playback of one AudioStreamPlayer3D, reached only by
## Object.call (TwoVoipCodec says why). The calls are the M1 spike's (`voice_speaker.gd`):
## `push_opus_packet(packet, 0, fec)` (v6.5 returns nothing), `queue_length_frames()`,
## `available_space_frames()`, and `mark_end_opus_stream(on)`, which the spike called with false to
## hold a fresh playback until its prebuffer filled and with true to play it. flush() stops and
## plays the player again for a fresh playback, as the spike shows no call that empties the queue
## (M5-3's round trip checks it).

const OPUS_RATE := 48000

var _player: AudioStreamPlayer3D
var _class: StringName
var _playback: AudioStreamPlayback


## Starts `player`, whose stream is the addon's, and holds its playback of class
## `playback_class`. A null player wraps no player (`playback` then comes from the caller, as in
## the round-trip script, and flush() only holds it).
func _init(
	player: AudioStreamPlayer3D, playback_class: StringName, playback: AudioStreamPlayback = null
) -> void:
	_player = player
	_class = playback_class
	_playback = playback
	if _player != null:
		_bind()
	elif _playback != null and not _playback.is_class(_class):
		_playback = null
	set_running(false)


## Whether a playback of the addon's class is held.
func bound() -> bool:
	return _playback != null


func push(frame: PackedByteArray, conceal: bool) -> void:
	if _playback != null:
		_playback.call(&"push_opus_packet", frame, 0, 1 if conceal else 0)


func queued_frames() -> int:
	if _playback == null:
		return 0
	var frames: int = _playback.call(&"queue_length_frames")
	return frames


func free_frames() -> int:
	if _playback == null:
		return 0
	var frames: int = _playback.call(&"available_space_frames")
	return frames


func set_running(on: bool) -> void:
	if _playback != null:
		_playback.call(&"mark_end_opus_stream", on)


func flush() -> void:
	if _player != null:
		_player.stop()
		_bind()
	set_running(false)


func sample_rate() -> int:
	return OPUS_RATE


func _bind() -> void:
	_player.play()
	_playback = _player.get_stream_playback()
	if _playback != null and not _playback.is_class(_class):
		_playback = null
