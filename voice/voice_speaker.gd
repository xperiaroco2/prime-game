class_name VoiceSpeaker
extends AudioStreamPlayer3D
## One remote speaker's voice on the listener (E40, E41, D12; the M5 ADR §1.5): an
## AudioStreamPlayer3D on the Voice bus with ATTENUATION_DISABLED, so Godot fades it linearly to
## silence at `max_distance`, the cutoff its owner gives (set_cutoff()); a VoiceJitter that orders
## the frames and decides what to decode; and the codec's VoicePlayback that decodes and plays.
## client/'s VoiceViews puts it at the speaker's mouth on its RemotePlayerBody, feeds it only
## frames the host sent, gives it the phase's cutoff and fades or flushes it: the speaker itself
## never reads the phase, the life fold or a session (E46 (a): voice/ uses nothing outside
## itself). Godot measures the distance from the current AudioListener3D (the ears), and mixes a
## 3D player only while the world has a Camera3D (observed on 4.7.2 headless, not in the docs;
## voice_views_audio_test's far camera).
##
## A fade (fade_out()) lowers the player's volume to silence over VoiceJitter.FADE_USEC, then the
## jitter says FLUSH and the playback's queue is emptied, so the audio already queued does not
## play on (the spike heard it 2.7 m past the cutoff). flush_now() empties it at once.
## The owner may lower it further by `extra_db` (client/'s occlusion muffle, M5-7) and move it to
## another bus; the speaker adds `extra_db` to the fade's volume and never decides it.

## The bus every voice plays on (D15).
const BUS := &"Voice"
## The quietest volume a fade sets, in dB: silence for the mix, finite for the player.
const SILENT_DB := -80.0
## Godot reads a max_distance of 0 as "no limit": a cutoff of 0 sets this instead, so nothing
## plays farther than a millimetre (the owner also drops every frame then).
const SILENT_DISTANCE_M := 0.001

var jitter := VoiceJitter.new()
## Decoded frames that did not fit the playback's queue, dropped (VoicePlayback.push() does not
## check for room).
var overflow := 0
## Frames handed to the playback, and the microseconds spent in those pushes (the decodes).
var decodes := 0
var decode_usec := 0
## The owner's volume offset in dB, added to the fade's (0 or below: client/'s muffle).
var extra_db := 0.0

var _codec: VoiceCodec
var _playback: VoicePlayback
var _cutoff_m := 0.0


## Debug numbers of one speaker for the F3 overlay (E47): no peer id or name, which the owner
## replaces with an index of first arrival.
class Stats:
	extends RefCounted
	## The index of first arrival the owner gives, from 1.
	var index := 0
	var queue_ms := 0
	var prebuffer_ms := 0
	var received := 0
	var late := 0
	var lost := 0
	var concealed := 0
	var stale := 0
	var underruns := 0
	var overflow := 0
	## The mean time of one decode, in microseconds.
	var decode_us := 0


## A speaker playing through `codec`: its stream now, its playback once in the tree.
func _init(codec: VoiceCodec) -> void:
	_codec = codec
	name = "VoiceSpeaker"
	bus = BUS
	attenuation_model = ATTENUATION_DISABLED
	set_cutoff(0.0)
	if codec.available():
		stream = codec.new_stream()


func _ready() -> void:
	if stream != null:
		_playback = _codec.playback_of(self)


## The distance in metres at which the voice fades to silence (the phase's hearing radius); 0
## silences it.
func set_cutoff(metres: float) -> void:
	_cutoff_m = maxf(metres, 0.0)
	max_distance = _cutoff_m if _cutoff_m > 0.0 else SILENT_DISTANCE_M


func cutoff() -> float:
	return _cutoff_m


## Whether it can play: the codec was available and the player is in the tree.
func can_play() -> bool:
	return _playback != null


## Takes one relayed frame (VoiceJitter.push()).
func push(seq: int, tick: int, frame: PackedByteArray, arrival_usec: int) -> void:
	jitter.push(seq, tick, frame, arrival_usec)


## Once a frame: decodes what the jitter buffer says, then starts, stops or flushes the playback,
## and sets the fade's volume.
func step(now_usec: int) -> void:
	if _playback == null:
		return
	var room_needed := _frame_audio_frames()
	for decode: VoiceJitter.Decode in jitter.update(_playback.queued_usec(), now_usec):
		if _playback.free_frames() < room_needed:
			overflow += 1
			continue
		var started := Time.get_ticks_usec()
		_playback.push(decode.frame, decode.conceal)
		decode_usec += Time.get_ticks_usec() - started
		decodes += 1
	match jitter.command():
		VoiceJitter.Command.START:
			_playback.set_running(true)
		VoiceJitter.Command.STOP:
			_playback.set_running(false)
		VoiceJitter.Command.FLUSH:
			_playback.flush()
	volume_db = maxf(linear_to_db(jitter.gain(now_usec)) + minf(extra_db, 0.0), SILENT_DB)


## Fades the voice out over VoiceJitter.FADE_USEC from `now_usec`, then flushes it; frames
## arriving meanwhile are dropped.
func fade_out(now_usec: int) -> void:
	jitter.fade_out(now_usec)


## Whether a fade runs.
func fading() -> bool:
	return jitter.fading()


## Empties the held frames and the playback's queue at once.
func flush_now() -> void:
	jitter.flush()
	if _playback != null:
		_playback.flush()
	volume_db = maxf(minf(extra_db, 0.0), SILENT_DB)


## Whether anything plays or waits to: a run, frames held, or audio queued.
func is_active() -> bool:
	if jitter.running or jitter.pending_frames() > 0:
		return true
	return _playback != null and _playback.queued_frames() > 0


## The audio queued in the playback, in microseconds.
func queued_usec() -> int:
	return _playback.queued_usec() if _playback != null else 0


## Its debug numbers, with `index` as the owner's index of first arrival.
func stats(index: int) -> Stats:
	var out := Stats.new()
	out.index = index
	out.queue_ms = roundi(queued_usec() / 1000.0)
	out.prebuffer_ms = roundi(jitter.prebuffer_usec / 1000.0)
	out.received = jitter.received
	out.late = jitter.late
	out.lost = jitter.lost
	out.concealed = jitter.concealed
	out.stale = jitter.stale
	out.underruns = jitter.underruns
	out.overflow = overflow
	out.decode_us = roundi(float(decode_usec) / decodes) if decodes > 0 else 0
	return out


## One codec frame's audio in the playback's audio frames.
func _frame_audio_frames() -> int:
	return ceili(float(_playback.sample_rate()) * VoiceCodec.FRAME_USEC / VoicePlayback.USEC)
