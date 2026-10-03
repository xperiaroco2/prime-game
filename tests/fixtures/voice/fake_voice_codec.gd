class_name FakeVoiceCodec
extends VoiceCodec
## The tests' codec (E34, the M5 ADR §1.3): 8 kHz mono µ-law (FakeMuLaw), so a 20 ms frame is 160
## bytes, played through an AudioStreamGenerator. Headless tests use it where the game uses
## TwoVoipCodec, so no test loads the addon.

const RATE := FakeMuLaw.RATE
const FRAME_SAMPLES := FakeMuLaw.FRAME_SAMPLES
## The generator's buffer: room for 25 frames.
const BUFFER_SECONDS := 0.5

## Set false to stand in for a machine without the codec.
var is_available := true


func available() -> bool:
	return is_available


func new_encoder() -> VoiceEncoder:
	return FakeVoiceEncoder.new() if is_available else null


func new_stream() -> AudioStream:
	if not is_available:
		return null
	var stream := AudioStreamGenerator.new()
	stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	stream.mix_rate = RATE
	stream.buffer_length = BUFFER_SECONDS
	return stream


func playback_of(player: AudioStreamPlayer3D) -> VoicePlayback:
	if not is_available or not player.is_inside_tree():
		return null
	if not player.stream is AudioStreamGenerator:
		return null
	return FakeVoicePlayback.new(player)
