class_name VoiceCodec
extends RefCounted
## The codec boundary (E34, the M5 ADR §1.3): what client/ and the rest of voice/ use to encode a
## speaker's chunks and to play a speaker's frames, without naming the codec. The game's codec is
## TwoVoipCodec, which reaches the TwoVoIP addon only by class name, so every script parses where
## the addon is absent; there available() is false and voice is unavailable while the game runs.
## Tests use the fake codec in tests/fixtures/voice/ and never load the addon. This base is a codec
## that is never available.
##
## Frames are 20 ms (E38): E7's voice bucket refills 50 a second and the relay keeps the newest 5
## per poll, so a shorter frame changes both.

## One frame's length, in microseconds.
const FRAME_USEC := 20000


## Whether this codec can encode and play on this machine.
func available() -> bool:
	return false


## A fresh encoder for one microphone, or null when the codec is not available.
func new_encoder() -> VoiceEncoder:
	return null


## A stream for one speaker's AudioStreamPlayer3D, or null when the codec is not available.
func new_stream() -> AudioStream:
	return null


## Starts `player`, whose stream came from new_stream() and which is inside the tree, and returns
## its playback held until VoiceJitter starts it; null when the codec is not available or the
## player's stream is not this codec's.
func playback_of(_player: AudioStreamPlayer3D) -> VoicePlayback:
	return null
