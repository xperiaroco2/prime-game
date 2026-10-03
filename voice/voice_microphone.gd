class_name VoiceMicrophone
extends RefCounted
## Where VoiceCapture reads its samples (the M5 ADR §1.1, E36): this base is the machine's
## microphone through Godot 4.7's AudioServer input API, as the M1 spike used it (the device list,
## `input_device`, `set_input_device_active`, `get_input_frames_available`, `get_input_frames`,
## `get_input_mix_rate`); `audio/driver/enable_input` must be on. Tests use a fake one in
## tests/fixtures/voice/ and never open a microphone; debug builds can use VoiceToneMicrophone.
##
## Godot 4.7.2's WASAPI driver reads only mono or stereo microphones and cannot tell a device's
## channel count beforehand: opening a 4-channel laptop array freezes the game (#22). VoiceCapture's
## "opening" mark keeps such a device from being opened again at the next start.

## The Windows default input device, the first name of Godot's device list.
const DEFAULT_DEVICE := "Default"


## The input devices' names, the Windows default first.
func devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


## Opens the device named `device` (DEFAULT_DEVICE for the Windows default) and starts reading it.
func open(device: String) -> Error:
	if AudioServer.input_device != device:
		AudioServer.input_device = device
	return AudioServer.set_input_device_active(true)


func close() -> void:
	AudioServer.set_input_device_active(false)


## The device's rate in Hz; Godot gives its frames as stereo at this rate.
func mix_rate() -> int:
	return int(AudioServer.get_input_mix_rate())


## How many frames wait to be read.
func frames_available() -> int:
	return AudioServer.get_input_frames_available()


## The next `frames` frames, oldest first.
func read(frames: int) -> PackedVector2Array:
	return AudioServer.get_input_frames(frames)


## Whether this source stands for a real microphone, whose opening can freeze the game (#22).
func is_device() -> bool:
	return true
