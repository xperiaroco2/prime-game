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


## A new bus `bus_name` sending to `send`, with `effect`'s bus effect on it; null (nothing made)
## when `effect` names no engine bus effect with that parameter (usable()).
static func make(effect: VoiceEffect, bus_name: StringName, send: StringName) -> VoiceEffectBus:
	if not usable(effect):
		return null
	var made := ClassDB.instantiate(effect.bus_effect) as AudioEffect
	for key: Variant in effect.settings:
		made.set(StringName(str(key)), effect.settings[key])
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	AudioServer.add_bus_effect(index, made)
	var bus := VoiceEffectBus.new()
	bus.name = AudioServer.get_bus_name(index)
	bus.effect = effect
	bus._made = made
	return bus


## Whether `effect` names an engine class that is a bus effect, can be made, and has `parameter`.
static func usable(effect: VoiceEffect) -> bool:
	if effect == null or effect.bus_effect == &"" or effect.parameter == &"":
		return false
	var named := effect.bus_effect
	if not ClassDB.class_exists(named) or not ClassDB.is_parent_class(named, BUS_EFFECT_BASE):
		return false
	if not ClassDB.can_instantiate(named):
		return false
	var probe := ClassDB.instantiate(named) as AudioEffect
	return probe != null and probe.get(effect.parameter) != null


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
