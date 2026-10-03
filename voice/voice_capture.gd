class_name VoiceCapture
extends RefCounted
## The microphone (the M5 ADR §1.1, E36 as amended): the device list, the chosen device opened, and
## every frame as many 20 ms chunks at the device's rate as it holds, each with its age. Off (D11)
## is a closed capture. client/ decides what to open (VoiceSender, VoiceControl) and keeps the
## settings; this class reads samples, through a VoiceMicrophone (the machine's, a test tone in
## debug builds, a fake in tests).
##
## The "opening" mark: Godot 4.7.2 freezes on a microphone with more than two channels (#22) and
## cannot tell the channel count beforehand. Before a device opens, `mark_changed` names it, and the
## caller writes the mark to the settings file at once; once the first second of samples arrived
## (or the device closed or failed cleanly) `mark_changed` gives "" and the caller clears it. At
## the next start a mark still set means the last opening never finished (the game froze or was
## killed): the caller then keeps that device closed until the player picks a microphone, with
## FROZE_TEXT (froze_text()). The #22 laptop freezes at most once.

## Names the device whose opening started, or "" once it finished (settled, closed or failed).
signal mark_changed(device: String)

## How long the first samples must keep arriving before the opening counts as finished.
const SETTLE_USEC := 1000000
## The line for a device that never finished opening at the last start (greybox words, #150).
const FROZE_TEXT := (
	'The microphone "%s" did not finish opening at the last start: the game may have frozen on'
	+ " it. Godot 4.7.2 reads only mono or stereo microphones (#22), and a laptop's microphone"
	+ " array can freeze it. It stays closed until you pick a microphone below; a headset"
	+ " microphone avoids it."
)


## One 20 ms chunk of stereo frames at the device's rate.
class Chunk:
	extends RefCounted
	var frames: PackedVector2Array
	## How long its first frame had waited in the device's buffer when it was read, in µs.
	var age_usec := 0

	func _init(with_frames: PackedVector2Array, age: int) -> void:
		frames = with_frames
		age_usec = age


var microphone := VoiceMicrophone.new()
## The device open (VoiceMicrophone.DEFAULT_DEVICE for the Windows default); "" while closed.
var device := ""
## Why the last open() failed; "" after a success.
var error := ""

var _rate := 0
## Frames read since the opening; SETTLE_USEC of them finish it.
var _read := 0
var _settling := false


## The microphone's devices, the Windows default first, each once.
func devices() -> PackedStringArray:
	var names := PackedStringArray()
	if microphone.is_device():
		names.append(VoiceMicrophone.DEFAULT_DEVICE)
	for name: String in microphone.devices():
		if not names.has(name):
			names.append(name)
	return names


## Opens `name` (VoiceMicrophone.DEFAULT_DEVICE for the Windows default; any name for a source
## that is no device, the test tone) and closes what was open. False with `error` set when the
## device is gone or refused (Windows' microphone privacy, a device in use).
func open(name: String) -> bool:
	close()
	error = ""
	if microphone.is_device() and not devices().has(name):
		error = 'no microphone named "%s" (unplugged?)' % name
		return false
	var marks := microphone.is_device()
	if marks:
		_settling = true
		_read = 0
		mark_changed.emit(name)
	var code := microphone.open(name)
	if code != OK:
		error = (
			'the microphone "%s" did not open: %s (Windows\' microphone privacy settings?)'
			% [name, error_string(code)]
		)
		_finish_opening()
		return false
	_rate = microphone.mix_rate()
	if _rate < 1000:
		microphone.close()
		error = 'the microphone "%s" reports a rate of %d Hz' % [name, _rate]
		_finish_opening()
		return false
	device = name
	return true


## Closes the device; a clean close also finishes its opening.
func close() -> void:
	if not device.is_empty():
		microphone.close()
	device = ""
	_rate = 0
	_finish_opening()


func is_open() -> bool:
	return not device.is_empty()


## Whether the open device has not yet delivered its first second (its mark is still set).
func is_settling() -> bool:
	return _settling


## The open device's rate in Hz; 0 while closed.
func rate() -> int:
	return _rate


## Frames in one 20 ms chunk at the device's rate; 0 while closed.
func chunk_frames() -> int:
	return int(_rate / 50.0)


## Every whole chunk of `frames` frames waiting, oldest first; none while closed. Reading the first
## second's worth finishes the opening.
func read(frames: int) -> Array[Chunk]:
	var out: Array[Chunk] = []
	if not is_open() or frames <= 0:
		return out
	var waiting := microphone.frames_available()
	while waiting >= frames:
		var age := int(float(waiting) * 1000000.0 / _rate)
		out.append(Chunk.new(microphone.read(frames), age))
		waiting -= frames
		_read += frames
	if _settling and float(_read) * 1000000.0 / _rate >= SETTLE_USEC:
		_finish_opening()
	return out


## The line for a device whose opening never finished at the last start.
static func froze_text(name: String) -> String:
	return FROZE_TEXT % name


func _finish_opening() -> void:
	if not _settling:
		return
	_settling = false
	mark_changed.emit("")
