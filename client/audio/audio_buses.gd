class_name AudioBuses
extends RefCounted
## The game's audio buses (the M5 ADR §1.7, E43 (a), D15): Voice (the players' voices), Effects
## (the world sounds) and Music (the dead's lift music), each sending to Master, made in code when
## the game starts, never from an editor-made bus layout, so a merge cannot drop a bus unseen and
## tests make them the same way. The Esc menu's sliders (M5-6) set their volumes; these defaults
## are placeholders, "not a decision". No ducking.

const MASTER := &"Master"
## The players' voices: VoiceSpeaker's bus.
const VOICE := VoiceSpeaker.BUS
const EFFECTS := &"Effects"
const MUSIC := &"Music"
## The buses made here, in order, and each one's default volume in dB.
const DEFAULT_DB: Dictionary[StringName, float] = {VOICE: 0.0, EFFECTS: -6.0, MUSIC: -14.0}


## Makes every bus that is missing, at its default volume, sending to Master; a bus that exists
## keeps its volume (a slider moved it). Safe to call again.
static func ensure() -> void:
	for bus: StringName in DEFAULT_DB:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, MASTER)
		AudioServer.set_bus_volume_db(index, DEFAULT_DB[bus])


## The index of `bus`, or -1 when it was not made.
static func index_of(bus: StringName) -> int:
	return AudioServer.get_bus_index(bus)
