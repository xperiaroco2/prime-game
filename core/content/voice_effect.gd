class_name VoiceEffect
extends ContentPart
## How a drunk speaker's voice sounds to the players who hear it (#1392; GDD §3 Base mode, "The
## bar"; ARCHITECTURE §6, §9.4.5): one number (`parameter`) of one bus effect (`bus_effect`, the
## engine's class name), which each listener's client makes on that speaker's own bus and moves
## with the speaker's strength (VoiceRule.effect_strength, 0 to 255 from the public drunk value):
## `rest + swing * strength / 255 * sin(2 pi wobble_hz t)`, or `rest + swing * strength / 255` when
## `wobble_hz` is 0 (value_at). At strength 0 the listener makes nothing. A voice rule holds one as
## its `drunk_effect`.
##
## core/ holds only the names and the numbers, as data: the client makes the effect
## (VoiceEffectBus, client/audio/). Another sound is another class and parameter in the mode's data,
## no code, as long as one number scaled by the strength is enough. The class defaults change
## nothing: the mode's data writes every field (§9.5).

## The bounds of `rest` and `swing`: wide enough for a ratio, decibels or hertz.
const MAX_VALUE := 20000.0
## The fastest wobble, in hertz.
const MAX_WOBBLE_HZ := 5.0
## The strength at which the full swing applies (the wire's U8, VoiceRule.MAX_STRENGTH).
const FULL_STRENGTH := 255

## The effect's name in the mode (a wire id, checked by ModeCheck).
@export var id: StringName = &""
## The engine class of the bus effect the listener makes, by name.
@export var bus_effect: StringName = &""
## The property of that effect that moves with the strength.
@export var parameter: StringName = &""
## The parameter at strength 0, and at each zero of the wobble.
@export var rest := 0.0
## How far the parameter moves from `rest` at full strength.
@export var swing := 0.0
## How often the parameter wobbles around `rest`, in hertz, 0 to MAX_WOBBLE_HZ; 0 holds it steady
## at `rest + swing * strength / 255`.
@export var wobble_hz := 0.0
## Other properties of the effect, set once when it is made (name -> value).
@export var settings: Dictionary = {}


## The parameter for a speaker of `strength` (0 to 255, clamped) at `seconds` on the listener's
## clock.
func value_at(strength: int, seconds: float) -> float:
	var scaled := swing * clampi(strength, 0, FULL_STRENGTH) / float(FULL_STRENGTH)
	if wobble_hz <= 0.0:
		return rest + scaled
	return rest + scaled * sin(TAU * wobble_hz * seconds)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if bus_effect == &"":
		found.append("bus_effect is empty")
	if parameter == &"":
		found.append("parameter is empty")
	for key: Variant in settings:
		if not (key is String or key is StringName) or str(key).is_empty():
			found.append("settings has the key %s, which is not a property name" % str(key))
	append_found(
		found,
		[
			out_of_bounds("rest", rest, -MAX_VALUE, MAX_VALUE),
			out_of_bounds("swing", swing, -MAX_VALUE, MAX_VALUE),
			out_of_bounds("wobble_hz", wobble_hz, 0.0, MAX_WOBBLE_HZ),
		]
	)
	return found
