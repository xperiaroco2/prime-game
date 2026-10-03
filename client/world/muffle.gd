class_name Muffle
extends RefCounted
## How muffled one voice is (the M5 ADR §1.6, D13 (a); ARCHITECTURE §6), pure: VoiceViews keeps
## one per speaker and moves it each physics frame by its ray from the ears to the mouth, and
## WorldSounds sets one per sound by its ray as the sound starts. Behind the level a sound is
## QUIET_DB quieter (the player's own `volume_db`) and duller (a muffled bus: AudioBuses'
## low-pass near 1 kHz). The quiet eases over EASE_SEC, so a door jamb's edge does not click; the
## bus follows the eased amount with a margin each way (DULL_ON, DULL_OFF), so a ray that flickers
## at an edge does not flip the bus each frame. It only lowers and dulls: it never makes anything
## louder or audible that would not play.
##
## Why a muffled bus for the dullness and the player's volume for the quiet (measured headless
## under the Dummy driver, M5-7): Godot's own attenuation filter on an AudioStreamPlayer3D is a
## high shelf whose depth grows with the distance fade and with `volume_db`, so its muffle of a
## 400 Hz tone measured 7.7 dB at 0.5 m and 12.7 dB at 6 m; a bus low-pass at 1 kHz dulls the
## same at every distance.

## D13 (a): 8 dB quieter behind the level. A placeholder, "not a decision".
const QUIET_DB := -8.0
## The quiet eases in and out over this long (the M5 ADR §1.6: 100 ms).
const EASE_SEC := 0.1
## The eased amount at which the sound moves to the muffled bus, and back to the clear one.
const DULL_ON := 0.75
const DULL_OFF := 0.25

## 0 clear, 1 fully muffled; eased between.
var amount := 0.0
## Whether the last frame moved it (an audible speaker): a speaker heard again after a silence
## starts at its ray's answer rather than easing from a stale one.
var following := false

var _dulled := false


## Moves toward muffled (`behind`: the ray hit the level) or clear by `delta` seconds of the
## ease; the first frame after rest() jumps straight there.
func follow(behind: bool, delta: float) -> void:
	var target := 1.0 if behind else 0.0
	if not following:
		amount = target
	else:
		amount = move_toward(amount, target, delta / EASE_SEC)
	following = true
	if amount >= DULL_ON:
		_dulled = true
	elif amount <= DULL_OFF:
		_dulled = false


## Not followed this frame (silent, fading, or no ears): the next follow() jumps.
func rest() -> void:
	following = false


## The volume offset in dB for the player: 0 clear, QUIET_DB muffled.
func volume_db() -> float:
	return QUIET_DB * amount


## Whether the player plays on the muffled bus (dulled): from DULL_ON on the way in until
## DULL_OFF on the way out.
func dulled() -> bool:
	return _dulled


## The bus for a sound whose clear bus is `clear`: its muffled bus once dulled.
func bus_for(clear: StringName) -> StringName:
	return AudioBuses.muffled_of(clear) if dulled() else clear


## The one ray (E42 (a)): whether level geometry lies between the ears `from` and the sound `to`,
## on the world layer only (SightHider.sees: never a player's capsule, and a hit within its slack
## of the sound, the floor under a put-down package, does not count).
static func blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	return not SightHider.sees(space, from, to)
