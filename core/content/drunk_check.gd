class_name DrunkCheck
extends RefCounted
## ModeCheck's checks of the bar (#1390; ARCHITECTURE §9.4.2, §9.4.5): a mode whose item kinds'
## rules hold a Drink lists DrunkTicks in every phase on the lobby's level that accepts the intent
## such a rule's trigger names (the mug's: UseSecondary, #1438), so a drunk value raised there
## always falls again; Drink's and PlayerRules' own checks bound the numbers. A mode with no Drink
## needs nothing.


## The problems of `mode`'s bar, empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var triggers := _drinking_triggers(mode)
	for phase: PhaseSpec in mode.phases:
		if phase == null or phase.level != PhaseSpec.Level.LOBBY:
			continue
		var decays := false
		for system: TickSystem in phase.tick_systems:
			decays = decays or system is DrunkTicks
		if decays:
			continue
		for trigger: StringName in triggers:
			if phase.senders_of(trigger) == 0:
				continue
			var why := "accepts %s, which drinks (Drink), and lists no DrunkTicks" % trigger
			found.append("phase %s %s: nobody would sober up there" % [phase.id, why])
	return found


## The triggers of `mode`'s item kinds' rules that run a Drink, each once, in order.
static func _drinking_triggers(mode: GameMode) -> Array[StringName]:
	var found: Array[StringName] = []
	for kind: ItemKind in mode.item_kinds:
		if kind == null:
			continue
		for rule: Rule in kind.actions:
			if rule == null or found.has(rule.trigger):
				continue
			for effect: RuleEffect in rule.effects:
				if effect is Drink:
					found.append(rule.trigger)
					break
	return found
