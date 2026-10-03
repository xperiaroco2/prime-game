class_name FakeMicrophone
extends VoiceMicrophone
## The tests' microphone: a device list, a rate and an opening result a test sets, and frames a test
## pushes as if captured. No test opens the machine's microphone (voice/CLAUDE.md).

var names := PackedStringArray(["Default", "Headset Microphone", "Microphone Array"])
var rate := 48000
## What open() returns.
var open_result := OK
## The device of the latest open(), and how many times it opened and closed.
var opened_device := ""
var opens := 0
var closes := 0
var is_open := false
## Called with no arguments as the device opens (a test checks what was saved by then).
var on_open := Callable()

var _waiting := PackedVector2Array()


func devices() -> PackedStringArray:
	return names


func open(device: String) -> Error:
	opened_device = device
	opens += 1
	if on_open.is_valid():
		on_open.call()
	is_open = open_result == OK
	return open_result


func close() -> void:
	closes += 1
	is_open = false
	_waiting.clear()


func mix_rate() -> int:
	return rate


func frames_available() -> int:
	return _waiting.size()


func read(frames: int) -> PackedVector2Array:
	var out := _waiting.slice(0, frames)
	_waiting = _waiting.slice(frames)
	return out


## Captures `frames` frames at `level` (both channels), as if the device recorded them.
func capture(frames: int, level: float) -> void:
	var more := PackedVector2Array()
	more.resize(frames)
	more.fill(Vector2(level, level))
	if is_open:
		_waiting.append_array(more)


## Captures `chunks` 20 ms chunks at `level`.
func capture_chunks(chunks: int, level: float) -> void:
	capture(chunks * int(rate / 50.0), level)
