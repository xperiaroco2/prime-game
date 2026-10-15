class_name PhotoFlashes
extends Node3D
## The photo camera's flash (#785, photo P6; the photo ADR §1.1 row 7, §3.3, §4, PD15; ARCHITECTURE
## §9.5.22): for each ShotTaken an OmniLight3D pulse at the camera's lens (its station's marker plus
## `lens_m`, the client's own copy of the mode's eye height, as PhotoTask's lens), held on until its
## shot is released. release(shot) is the call the picture's render (P8, #787) makes once its
## queued render of that shot has drawn: this light is that render's flash (the ADR's §3.3), so it
## stays on until then. A pulse lasts at least PULSE_S, so the live view sees it even when the
## render draws in the next frame, and ends at HOLD_LIMIT_S unreleased: the fallback for a shot no
## render ever releases (a headless client renders nothing, PhotoPictures, #787).
##
## What it may show (per-peer filtering, the M4 ADR's §3 items 5 and 10): ShotTaken reaches everyone
## (a shot is public, the record names no shooter), and the flash is seen only where the eye
## reaches: `shadow_enabled` and a short `omni_range` (RANGE_M). A light without shadows passes
## through walls: it would light a room behind one, showing a flash where no eye sees the camera.
## It draws no mesh, sprite or marker, so nothing of it shows through the level; its
## `light_cull_mask` stays every layer (the photo layer P8 adds included). It plays no sound: the
## shutter is WorldSounds' (SoundChooser.SHUTTER).

## How far the flash lights, in metres: a room's reach around the lens. Placeholder, "not a
## decision".
const RANGE_M := 4.0
## How bright the flash is. Placeholder, "not a decision".
const ENERGY := 6.0
## The shortest pulse, in seconds, released or not. Placeholder, "not a decision".
const PULSE_S := 0.1
## The longest pulse, in seconds: the fallback ends an unreleased flash here. Placeholder, "not a
## decision".
const HOLD_LIMIT_S := 1.0


## One flash: its light, how long it has been on, and whether its shot was released.
class Flash:
	extends RefCounted
	var light: OmniLight3D
	var age := 0.0
	var released := false


var model: ClientModel
## How far above a camera's marker its lens is: the client's own copy of the mode's eye height
## (ItemWorld sets it).
var lens_m := 0.0

## The flashes on, by shot id.
var _flashes: Dictionary[int, Flash] = {}
var _started := 0


## The session's events (ItemWorld forwards them): a ShotTaken at a camera the model knows
## starts its flash; a recycled shot id ends the older flash first.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name != &"ShotTaken" or model == null:
		return
	var camera: ClientModel.Station = model.stations.get(fields["station"] as int)
	if camera == null:
		return
	var shot := fields["shot"] as int
	_end(shot)
	var flash := Flash.new()
	flash.light = OmniLight3D.new()
	flash.light.name = "Flash%d" % _started
	flash.light.omni_range = RANGE_M
	flash.light.light_energy = ENERGY
	flash.light.shadow_enabled = true
	flash.light.position = camera.position + Vector3.UP * lens_m
	add_child(flash.light)
	_flashes[shot] = flash
	_started += 1


## The render of `shot` has drawn (P8): its flash ends now, or at PULSE_S if it is younger. Nothing
## for a shot with no flash on.
func release(shot: int) -> void:
	var flash: Flash = _flashes.get(shot)
	if flash == null:
		return
	flash.released = true
	if flash.age >= PULSE_S:
		_end(shot)


## Ages every flash by `seconds`, ending each released one past PULSE_S and each past HOLD_LIMIT_S.
func advance(seconds: float) -> void:
	for shot: int in _flashes.keys():
		var flash := _flashes[shot]
		flash.age += seconds
		if (flash.released and flash.age >= PULSE_S) or flash.age >= HOLD_LIMIT_S:
			_end(shot)


## The light of `shot`'s flash while it is on, else null (tests; the render's light, P8).
func light_of(shot: int) -> OmniLight3D:
	var flash: Flash = _flashes.get(shot)
	return flash.light if flash != null else null


## How many flashes are on.
func lit() -> int:
	return _flashes.size()


## How many flashes were started (tests).
func started() -> int:
	return _started


## Ends every flash (the session ended).
func clear() -> void:
	for shot: int in _flashes.keys():
		_end(shot)


func _process(delta: float) -> void:
	advance(delta)


func _end(shot: int) -> void:
	var flash: Flash = _flashes.get(shot)
	if flash == null:
		return
	_flashes.erase(shot)
	flash.light.visible = false
	flash.light.queue_free()
