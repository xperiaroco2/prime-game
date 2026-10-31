class_name BoothCheck
extends RefCounted
## ModeCheck's checks of the photo booth (#1396; ARCHITECTURE §9.4.2, §9.4.5, §9.5.28): a StartBooth
## stands only in a station kind's Interact rule, after AtStation and StationInSight, not negated
## (the host checks the press's reach and sight, as GiveItem.required_conditions); a mode with one
## lists BoothTicks in some phase (else every press is refused), and only in phases on the lobby's
## level (the booth is a hall toy, #1396); and every row from a phase that
## lists BoothTicks to one that does not holds a StopBooth, so no session outlives its clock.
## StartBooth's own check bounds its numbers and its strip kind. A mode with no StartBooth and no
## BoothTicks needs nothing.


## The problems of `mode`'s booth, empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var starts := false
	for kind: StationKind in Stations.kinds_in(mode):
		for rule: Rule in kind.actions:
			if rule != null and _starts(rule):
				starts = true
				found.append_array(_station_rule("station kind %s" % kind.id, rule))
	_misplaced("mode.actions", mode.actions, found)
	_misplaced("mode.reactions", mode.reactions, found)
	for role: GameRole in mode.roles:
		if role != null:
			_misplaced("role %s.actions" % role.id, role.actions, found)
	for kind: ItemKind in mode.item_kinds:
		if kind != null:
			_misplaced("item kind %s.actions" % kind.id, kind.actions, found)
			_misplaced("item kind %s.target_actions" % kind.id, kind.target_actions, found)
	var ticking := PackedStringArray()
	for phase: PhaseSpec in mode.phases:
		if BoothTicks.listed_in(phase):
			ticking.append(String(phase.id))
			if phase.level != PhaseSpec.Level.LOBBY:
				found.append("phase %s lists BoothTicks off the lobby's level" % phase.id)
	if starts and ticking.is_empty():
		found.append("a station starts the booth (StartBooth), and no phase lists BoothTicks")
	for row: Transition in mode.transitions:
		if row == null or not ticking.has(String(row.from)) or ticking.has(String(row.to)):
			continue
		var stops := false
		for action: RuleEffect in row.actions:
			stops = stops or action is StopBooth
		if not stops:
			var text := "row %s, %s leaves BoothTicks for %s without StopBooth: a session would"
			found.append((text + " outlive its clock") % [row.from, row.outcome, row.to])
	return found


static func _starts(rule: Rule) -> bool:
	for effect: RuleEffect in rule.effects:
		if effect is StartBooth:
			return true
	return false


## A station kind's rule that starts the booth: Interact, with AtStation and StationInSight.
static func _station_rule(owner: String, rule: Rule) -> PackedStringArray:
	var found := PackedStringArray()
	if rule.trigger != Intents.INTERACT:
		found.append("%s: StartBooth runs on %s, not Interact" % [owner, rule.trigger])
	for required: Script in GiveItem.required_conditions(false):
		var holds := false
		for condition: Condition in rule.conditions:
			holds = (
				holds
				or (
					condition != null
					and not condition.negate
					and is_instance_of(condition, required)
				)
			)
		if not holds:
			var lacks := "%s: rule %s starts the booth and lacks the condition %s"
			found.append(lacks % [owner, rule.trigger, required.get_global_name()])
	return found


## A StartBooth anywhere but a station kind's rule has no booth to start at.
static func _misplaced(owner: String, rules: Array[Rule], found: PackedStringArray) -> void:
	for rule: Rule in rules:
		if rule != null and _starts(rule):
			found.append(
				(
					"%s: rule %s starts the booth, which only a station's rule can"
					% [owner, rule.trigger]
				)
			)
