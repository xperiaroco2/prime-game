class_name VoiceEffectBus
extends RefCounted
## One drunk speaker's own bus (#1392; ARCHITECTURE §4.7.15, §6): made in code while its voice
## sounds drunk, holding one bus effect built from the mode's VoiceEffect (its `bus_effect` class,
## its `settings`), whose `parameter` VoiceViews moves each physics frame (VoiceEffect.value_at of
## the speaker's strength and the clock). It sends to the clear Voice bus or, behind the level, to
## VoiceMuffled, so the muffle and the Voice slider still apply on top. VoiceViews removes it at
## strength 0 and when the speaker goes: a sober voice plays on Voice and costs nothing.
##
## Buses are the AudioServer's, one set per process, and remove_bus shifts every later index: the
## bus is always found by its name, unique per VoiceViews and peer, never by a kept index.

## Every such bus's name starts so.
const PREFIX := "VoiceDrunk_"
## The engine class a bus effect extends.
const BUS_EFFECT_BASE := &"AudioEffect"

## The bus's name.
var name: StringName
## The mode's effect it was made from.
var effect: VoiceEffect

var _made: AudioEffect


## A new bus `bus_name` sending to `send`, with `from`'s bus effect on it; null (nothing made)
## when `from` names no engine bus effect with that parameter (usable()).
static func make(from: VoiceEffect, bus_name: StringName, send: StringName) -> VoiceEffectBus:
	if not usable(from):
		return null
	var built := ClassDB.instantiate(from.bus_effect) as AudioEffect
	for key: Variant in from.settings:
		built.set(StringName(str(key)), from.settings[key])
	AudioServer.add_bus()
	var at := AudioServer.bus_count - 1
	AudioServer.set_bus_name(at, bus_name)
	AudioServer.set_bus_send(at, send)
	AudioServer.add_bus_effect(at, built)
	var bus := VoiceEffectBus.new()
	bus.name = AudioServer.get_bus_name(at)
	bus.effect = from
	bus._made = built
	return bus


## Whether `candidate` names an engine class that is a bus effect, can be made, and has `parameter`.
static func usable(candidate: VoiceEffect) -> bool:
	if candidate == null or candidate.bus_effect == &"" or candidate.parameter == &"":
		return false
	var named := candidate.bus_effect
	if not ClassDB.class_exists(named) or not ClassDB.is_parent_class(named, BUS_EFFECT_BASE):
		return false
	if not ClassDB.can_instantiate(named):
		return false
	var probe := ClassDB.instantiate(named) as AudioEffect
	return probe != null and probe.get(candidate.parameter) != null


## The bus's index now, or -1 once it is gone.
func index() -> int:
	return AudioServer.get_bus_index(name)


## The bus effect on it.
func made() -> AudioEffect:
	return _made


## Sends to `send` and sets the parameter for `strength` at `seconds`; false when the bus is gone
## (then the caller drops this one).
func apply(strength: int, send: StringName, seconds: float) -> bool:
	var at := index()
	if at < 0:
		return false
	if AudioServer.get_bus_send(at) != send:
		AudioServer.set_bus_send(at, send)
	_made.set(effect.parameter, effect.value_at(strength, seconds))
	return true


## Removes the bus; again, nothing.
func release() -> void:
	var at := index()
	if at >= 0:
		AudioServer.remove_bus(at)
