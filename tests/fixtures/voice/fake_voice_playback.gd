class_name FakeVoicePlayback
extends VoicePlayback
## FakeVoiceCodec's playback: decoded frames wait here while held and go into the player's
## AudioStreamGenerator while running, so a held playback's queue stays exact whether or not the
## audio driver mixes. Concealment repeats the last decoded frame at half its amplitude.

## Frames pushed, and those of them concealed.
var pushed := 0
var concealed := 0
var running := false

var _player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _capacity := 0
## Decoded audio held until running.
var _held := PackedVector2Array()
var _last := PackedVector2Array()


## Starts `player`, whose stream came from FakeVoiceCodec.new_stream(), held.
func _init(player: AudioStreamPlayer3D) -> void:
	_player = player
	_bind()


func push(frame: PackedByteArray, conceal: bool) -> void:
	pushed += 1
	var audio := PackedVector2Array()
	if conceal:
		concealed += 1
		audio = _last.duplicate()
		for i: int in audio.size():
			audio[i] *= 0.5
		if audio.is_empty():
			audio.resize(FakeMuLaw.FRAME_SAMPLES)
	else:
		audio = FakeMuLaw.decode_frame(frame)
		_last = audio
	_held.append_array(audio)
	_feed()


func queued_frames() -> int:
	return _held.size() + _capacity - _playback.get_frames_available()


func free_frames() -> int:
	return maxi(0, _playback.get_frames_available() - _held.size())


func set_running(on: bool) -> void:
	running = on
	_feed()


func flush() -> void:
	_player.stop()
	_held.clear()
	_bind()


func sample_rate() -> int:
	return FakeMuLaw.RATE


func _bind() -> void:
	running = false
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_capacity = _playback.get_frames_available()


func _feed() -> void:
	if not running or _held.is_empty():
		return
	var room := mini(_held.size(), _playback.get_frames_available())
	_playback.push_buffer(_held.slice(0, room))
	_held = _held.slice(room)
