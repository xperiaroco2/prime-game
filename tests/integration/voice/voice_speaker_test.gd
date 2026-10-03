extends GdUnitTestSuite
## VoiceSpeaker's guard on the playback's room (the M5 ADR §1.3): VoicePlayback.push() does not
## check for room, so the speaker checks free_frames() before each push and drops (and counts in
## `overflow`) a decoded frame that does not fit. A real AudioStreamPlayer3D in the tree with the
## fake codec, whose playback here reports the room a test gives it.


## The fake codec's playback with the room a test sets.
class TightPlayback:
	extends FakeVoicePlayback
	var room := 0

	func free_frames() -> int:
		return room


## The fake codec handing out a TightPlayback, kept for the test.
class TightCodec:
	extends FakeVoiceCodec
	var made: TightPlayback

	func playback_of(player: AudioStreamPlayer3D) -> VoicePlayback:
		made = TightPlayback.new(player)
		return made


const STEP_USEC := 20000

var _now := 1000000
var _seq := 0


func before_test() -> void:
	AudioBuses.ensure()


func test_a_frame_that_does_not_fit_the_playback_is_dropped_and_counted() -> void:
	var codec := TightCodec.new()
	var speaker: VoiceSpeaker = auto_free(VoiceSpeaker.new(codec))
	add_child(speaker)
	speaker.set_cutoff(8.0)
	var playback := codec.made
	assert_object(playback).is_not_null()
	# No room: whatever the jitter buffer decodes is dropped and counted, never pushed.
	_talk(speaker, 10, 10)
	assert_int(speaker.overflow).is_greater(0)
	assert_int(playback.pushed).is_equal(0)
	assert_int(speaker.decodes).is_equal(0)
	assert_int(speaker.stats(1).overflow).is_equal(speaker.overflow)
	# Room again: the next frames are pushed, and the count stays.
	var dropped := speaker.overflow
	playback.room = 1 << 20
	_talk(speaker, 10, 11)
	assert_int(speaker.overflow).is_equal(dropped)
	assert_int(playback.pushed).is_greater(0)
	assert_int(speaker.decodes).is_equal(playback.pushed)


## `count` frames stamped at `tick`, one every STEP_USEC, the speaker stepping after each.
func _talk(speaker: VoiceSpeaker, count: int, tick: int) -> void:
	var frame := PackedByteArray()
	frame.resize(FakeVoiceCodec.FRAME_SAMPLES)
	for i: int in count:
		speaker.push(_seq, tick, frame, _now)
		_seq += 1
		_now += STEP_USEC
		speaker.step(_now)
