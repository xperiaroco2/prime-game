class_name TwoVoipCodec
extends VoiceCodec
## The game's codec: Opus through the TwoVoIP addon v6.5 (the voice ADR; v6.6 crashes on import),
## with the M1 spike's settings: 48 kHz, mono, 960-sample (20 ms) frames, 24 kbit/s, complexity 5,
## RNNoise or no denoiser (E34, E38, the M5 ADR §1.3).
##
## No script names an addon class: this one reaches the addon only through ClassDB by class name
## and Object.call with typed results, so the project parses and runs where the extension is not
## loaded (CI on Linux, a clone before the addon's download); available() is then false. The class
## names are constructor arguments defaulting to TwoVoIP's, so a test passes a missing one and sees
## the codec unavailable on Windows too, where the addon is installed. The addon's methods are
## named as the spike used them (`git show
## origin/voice/16-m1-spike-measure-voice-latency-cpu-cost:spike/voice/<file>`): the engine's API
## dump does not hold them. tests/unit/voice/voice_addon_names_test.gd fails on any project script
## that names an addon class as an identifier.

const ENCODER_CLASS := &"TwovoipOpusEncoder"
const STREAM_CLASS := &"AudioStreamOpus"
const PLAYBACK_CLASS := &"AudioStreamPlaybackOpus"
const OPUS_RATE := 48000
const CHANNELS := 1

var _encoder_class: StringName
var _stream_class: StringName
var _playback_class: StringName


func _init(
	encoder_class: StringName = ENCODER_CLASS,
	stream_class: StringName = STREAM_CLASS,
	playback_class: StringName = PLAYBACK_CLASS
) -> void:
	_encoder_class = encoder_class
	_stream_class = stream_class
	_playback_class = playback_class


func available() -> bool:
	return (
		ClassDB.class_exists(_encoder_class)
		and ClassDB.can_instantiate(_encoder_class)
		and ClassDB.class_exists(_stream_class)
		and ClassDB.can_instantiate(_stream_class)
		and ClassDB.class_exists(_playback_class)
	)


func new_encoder() -> VoiceEncoder:
	if not available():
		return null
	var encoder := ClassDB.instantiate(_encoder_class) as Object
	if encoder == null:
		return null
	return TwoVoipEncoder.new(encoder, _encoder_class)


func new_stream() -> AudioStream:
	if not available():
		return null
	var stream := ClassDB.instantiate(_stream_class) as AudioStream
	if stream == null:
		return null
	stream.call(&"set_opus_sample_rate", OPUS_RATE)
	stream.call(&"set_opus_channels", CHANNELS)
	return stream


func playback_of(player: AudioStreamPlayer3D) -> VoicePlayback:
	if not available() or not player.is_inside_tree():
		return null
	if player.stream == null or not player.stream.is_class(_stream_class):
		return null
	var playback := TwoVoipPlayback.new(player, _playback_class)
	if not playback.bound():
		return null
	return playback
