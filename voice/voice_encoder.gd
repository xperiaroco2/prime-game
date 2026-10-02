class_name VoiceEncoder
extends RefCounted
## One speaker's encoder behind the codec boundary (E34, the M5 ADR §1.3): every 20 ms chunk of
## microphone frames the microphone delivers goes through encode(), whether or not the gate sends
## the frame, so the codec's and the denoiser's state stay continuous (§1.2). A codec subclasses
## it (TwoVoipCodec's encoder, the tests' fake); this base encodes nothing.


## Prepares the encoder for chunks of `input_rate` Hz stereo frames, as Godot's microphone API
## gives them; `denoise` turns noise suppression on where the codec has it (RNNoise). Returns ""
## on success, else an error text for the Voice tab.
func start(_input_rate: int, _denoise: bool) -> String:
	return "no voice codec"


## How many input frames one encode() takes: 20 ms at the input rate. 0 before start().
func chunk_frames() -> int:
	return 0


## One encoded frame of the 20 ms `chunk`, or an empty array on failure.
func encode(_chunk: PackedVector2Array) -> PackedByteArray:
	return PackedByteArray()
