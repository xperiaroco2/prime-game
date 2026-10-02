class_name VoicePlayback
extends RefCounted
## The decoding side of the codec boundary (E34, the M5 ADR §1.3): the playback of one speaker's
## player, which decodes frames into a queue of audio that the player plays while running.
## VoiceJitter decides what to push and when to run; this class only does it. A codec subclasses
## it (TwoVoipCodec's playback, the tests' fake); this base plays nothing.
##
## "Frames" in queued_frames() and free_frames() are audio frames (one sample per channel) at
## sample_rate(), as Godot counts them, not codec frames.

## Microseconds in a second, for queued_usec().
const USEC := 1000000


## Decodes `frame` into the queue. With `conceal` it decodes the frame before it instead, from
## the in-band FEC data `frame` carries if any, else by the codec's concealment; the caller then
## pushes `frame` again without `conceal` for its own slot (the M5 ADR §1.3). push() does not check
## for room: the caller checks free_frames() first and drops (and counts) a frame that does not fit.
func push(_frame: PackedByteArray, _conceal: bool) -> void:
	pass


## Audio frames decoded and not yet played.
func queued_frames() -> int:
	return 0


## Audio frames the queue still has room for; the caller checks it before each push().
func free_frames() -> int:
	return 0


## Plays the queue (true) or holds it (false).
func set_running(_on: bool) -> void:
	pass


## Empties the queue at once and holds the playback, so audio already queued does not play on
## (the spike measured it playing 2.7 m past the cutoff).
func flush() -> void:
	pass


## The rate of queued_frames() and free_frames(), in audio frames a second.
func sample_rate() -> int:
	return 0


## The audio queued, in microseconds, as VoiceJitter takes it.
func queued_usec() -> int:
	var rate := sample_rate()
	if rate <= 0:
		return 0
	return int(float(queued_frames()) * USEC / rate)
