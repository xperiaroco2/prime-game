class_name PhaseSpec
extends ContentPart
## One phase of a game mode (ARCHITECTURE §3.1, §9.3): the phase class with its settings, the
## intents it accepts and from whom, its tick systems in order, whether it checks the win
## conditions, whether the match clock runs, its voice rule, its level and whether snapshots are
## sent. On each entry Match creates a fresh object of `phase_class` (a Phase) and drops it on
## exit (§9.1).

## Which level the phase plays in: none, the mode's lobby, or the match's map.
enum Level { NONE, LOBBY, MAP }

@export var id: StringName
## A script extending Phase.
@export var phase_class: Script
## The phase class's settings, in seconds and whole numbers (Countdown: `seconds`).
@export var settings: Dictionary[StringName, float] = {}
@export var accepts: Array[AcceptSpec] = []
@export var tick_systems: Array[TickSystem] = []
@export var checks_wins := false
@export var clock_runs := false
## Null: nobody hears anybody.
@export var voice_rule: VoiceRule
@export var level := Level.NONE
@export var snapshots := false


## A fresh phase object, or null when `phase_class` is missing or not a Phase.
func create_phase() -> Phase:
	var script := phase_class as GDScript
	if script == null or not script.can_instantiate():
		return null
	var created: Variant = script.new()
	if created is Phase:
		var phase: Phase = created
		phase.spec = self
		return phase
	return null


## The flags of AcceptSpec.From under which `intent` is accepted; 0 when it is not.
func senders_of(intent: StringName) -> int:
	var flags := 0
	for entry: AcceptSpec in accepts:
		if entry != null and entry.intent == intent:
			flags |= entry.from
	return flags


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a phase has no id")
	var phase := create_phase()
	if phase == null:
		found.append("phase %s: phase_class is not a script extending Phase" % id)
	else:
		for message: String in phase.check_settings(settings):
			found.append("phase %s: %s" % [id, message])
	for entry: AcceptSpec in accepts:
		if entry == null:
			found.append("phase %s: an empty accepts entry" % id)
		elif not Intents.ALL.has(entry.intent):
			found.append("phase %s accepts %s, which is no intent" % [id, entry.intent])
		elif entry.from == 0:
			found.append("phase %s accepts %s from nobody" % [id, entry.intent])
	return found
