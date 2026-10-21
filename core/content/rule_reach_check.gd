class_name RuleReachCheck
extends RefCounted
## The part of ModeCheck about who takes an accepted intent (#1236; ARCHITECTURE §9.2): static
## checks that return their findings, run for ModeCheck. Match._dispatch hands an accepted intent
## to the phase's class if it handles it (Phase.handles), else MoveClaim to the movement rule, and
## only then to the rules. So an action on MoveClaim, or on an intent the class of every phase that
## accepts it handles (SetReady in a mode whose only phase accepting it is the lobby), is never
## reached: an error. A reaction with no effects changes nothing: a warning, since test fixtures
## hold such reactions as placeholders. An action with no effects is no finding: applying it stops
## its actor's channel, which is what the shipped StopRaise action (no effects) is for.


## Whether an accepted `intent` is taken by someone: the phase's class, the movement rule, or one
## of `rules` (every rule on it among the mode's owners).
static func handled(phase: Phase, intent: StringName, rules: Array[Rule]) -> bool:
	return phase.handles(intent) or intent == Intents.MOVE_CLAIM or not rules.is_empty()


## The intents some phase accepts and every phase that accepts them hands to its class; a phase
## whose class cannot be made counts as handing none (_check_phases reports it).
static func taken_by_phases(mode: GameMode) -> Array[StringName]:
	var accepted: Array[StringName] = []
	var to_rules: Array[StringName] = []
	for spec: PhaseSpec in mode.phases:
		if spec == null:
			continue
		var phase := spec.create_phase()
		for entry: AcceptSpec in spec.accepts:
			if entry == null:
				continue
			if not accepted.has(entry.intent):
				accepted.append(entry.intent)
			if (
				(phase == null or not phase.handles(entry.intent))
				and not to_rules.has(entry.intent)
			):
				to_rules.append(entry.intent)
	var taken: Array[StringName] = []
	for intent: StringName in accepted:
		if not to_rules.has(intent):
			taken.append(intent)
	return taken


## The error for an action (`on_intent`: its owner's triggers are intents) that is never reached;
## `taken`: taken_by_phases().
static func unreached(
	owner: String, rule: Rule, on_intent: bool, taken: Array[StringName]
) -> PackedStringArray:
	var found := PackedStringArray()
	if not on_intent:
		return found
	if rule.trigger == Intents.MOVE_CLAIM:
		found.append(
			"%s: rule on %s is never reached: the movement rule takes it" % [owner, rule.trigger]
		)
	elif taken.has(rule.trigger):
		found.append(
			(
				"%s: rule on %s is never reached: the class of every phase that accepts it takes it"
				% [owner, rule.trigger]
			)
		)
	return found


## The warning for a reaction (not `on_intent`) with no effects.
static func no_effects(owner: String, rule: Rule, on_intent: bool) -> PackedStringArray:
	var found := PackedStringArray()
	if not on_intent and rule.effects.is_empty():
		found.append("%s: rule %s holds no effects, so it changes nothing" % [owner, rule.trigger])
	return found
