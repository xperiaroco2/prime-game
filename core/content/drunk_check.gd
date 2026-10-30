class_name DrunkCheck
extends RefCounted
## ModeCheck's checks of the bar (#1390; ARCHITECTURE §9.4.2, §9.4.5): a mode whose item kinds' Use
## rules hold a Drink lists DrunkTicks in every phase on the lobby's level that accepts Use, so a
## drunk value raised there always falls again; Drink's and PlayerRules' own checks bound the
## numbers. A mode with no Drink needs nothing.


## The problems of `mode`'s bar, empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if not _drinks(mode):
		return found
	for phase: PhaseSpec in mode.phases:
		if phase == null or phase.level != PhaseSpec.Level.LOBBY:
			continue
		if phase.senders_of(&"Use") == 0:
			continue
		var decays := false
		for system: TickSystem in phase.tick_systems:
			decays = decays or system is DrunkTicks
		if not decays:
			var why := "accepts Use, which drinks (Drink), and lists no DrunkTicks"
			found.append("phase %s %s: nobody would sober up there" % [phase.id, why])
	return found


## Whether a Use rule of one of `mode`'s item kinds runs a Drink.
static func _drinks(mode: GameMode) -> bool:
	for kind: ItemKind in mode.item_kinds:
		if kind == null:
			continue
		for rule: Rule in kind.actions:
			if rule == null:
				continue
			for effect: RuleEffect in rule.effects:
				if effect is Drink:
					return true
	return false
