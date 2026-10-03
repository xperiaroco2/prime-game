class_name VoiceToneMicrophone
extends VoiceMicrophone
## A test tone in place of the microphone (debug builds only, the M5 ADR's E47 and §6): one PC has
## one microphone, so in the one-PC listening test a second window speaks this tone, as the M1
## spike's tone client did. A steady sine with a slow swell, easy to tell apart, delivered in real
## time from `clock`; after a long frame it skips ahead instead of bursting. It is not speech, so
## the sender starts its encoder without the denoiser, which would remove it.

const RATE := 48000
const HZ := 440.0
## The swell: the amplitude moves between SWELL_LOW and 1 times AMPLITUDE at SWELL_HZ. At its
## lowest it stays over the default voice-activity threshold, so the tone holds the gate open.
const AMPLITUDE := 0.25
const SWELL_LOW := 0.75
const SWELL_HZ := 2.0
## The most frames it holds back: five 20 ms chunks.
const MAX_BACKLOG := 4800

## The clock in microseconds: Time.get_ticks_usec() unless a test sets one.
var clock := Callable()

var _open := false
var _started_usec := 0
## Frames delivered since the start.
var _read := 0


func devices() -> PackedStringArray:
	return PackedStringArray(["test tone"])


func open(_device: String) -> Error:
	_open = true
	_started_usec = _now()
	_read = 0
	return OK


func close() -> void:
	_open = false


func mix_rate() -> int:
	return RATE


func frames_available() -> int:
	if not _open:
		return 0
	var due := int(float(_now() - _started_usec) * RATE / 1000000.0)
	# After a long frame, skip ahead rather than deliver a burst.
	_read = maxi(_read, due - MAX_BACKLOG)
	return maxi(due - _read, 0)


func read(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	for i: int in frames:
		var t := float(_read + i) / RATE
		var swell := SWELL_LOW + (1.0 - SWELL_LOW) * (0.5 + 0.5 * sin(TAU * SWELL_HZ * t))
		var v := AMPLITUDE * swell * sin(TAU * HZ * t)
		out[i] = Vector2(v, v)
	_read += frames
	return out


func is_device() -> bool:
	return false


func _now() -> int:
	return clock.call() as int if clock.is_valid() else Time.get_ticks_usec()
