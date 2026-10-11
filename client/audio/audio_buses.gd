class_name AudioBuses
extends RefCounted
## The game's audio buses (the M5 ADR §1.7, E43 (a), D15): Voice (the players' voices), Effects
## (the world sounds), Music (the dead's lift music) and UI (the Toy buttons' click, #525), each
## sending to Master, made in code when the game starts, never from an editor-made bus layout, so a
## merge cannot drop a bus unseen and tests make them the same way. The Esc menu's sliders (M5-6)
## set the volumes of Master, Voice, Effects and Music; UI has no slider of its own (Master's
## applies). These defaults are placeholders, "not a decision". No ducking.
##
## Each of Voice and Effects has a muffled bus (the M5 ADR §1.6, D13 (a), M5-7), made after it and
## sending to it, so its slider still applies: an AudioEffectLowPassFilter at LOW_PASS_HZ, nothing
## else. A sound behind the level plays there, the 8 dB quieter on its own player (Muffle).

const MASTER := &"Master"
## The players' voices: VoiceSpeaker's bus.
const VOICE := VoiceSpeaker.BUS
const EFFECTS := &"Effects"
const MUSIC := &"Music"
## The UI's click (UiSounds).
const UI := &"UI"
## The buses made here, in order, and each one's default volume in dB.
const DEFAULT_DB: Dictionary[StringName, float] = {
	VOICE: 0.0, EFFECTS: -6.0, MUSIC: -14.0, UI: -6.0
}
const VOICE_MUFFLED := &"VoiceMuffled"
const EFFECTS_MUFFLED := &"EffectsMuffled"
## Each muffled bus and the bus it sends to.
const MUFFLED: Dictionary[StringName, StringName] = {VOICE_MUFFLED: VOICE, EFFECTS_MUFFLED: EFFECTS}
## D13 (a): the muffle's low-pass, near 1 kHz. A placeholder, "not a decision".
const LOW_PASS_HZ := 1000.0


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
	for bus: StringName in MUFFLED:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, MUFFLED[bus])
		var low_pass := AudioEffectLowPassFilter.new()
		low_pass.cutoff_hz = LOW_PASS_HZ
		AudioServer.add_bus_effect(index, low_pass)


## The muffled bus of `bus` (Voice or Effects); `bus` itself when it has none.
static func muffled_of(bus: StringName) -> StringName:
	for muffled: StringName in MUFFLED:
		if MUFFLED[muffled] == bus:
			return muffled
	return bus


## The index of `bus`, or -1 when it was not made.
static func index_of(bus: StringName) -> int:
	return AudioServer.get_bus_index(bus)
