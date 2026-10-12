class_name ItemTargetCheck
extends RefCounted
## The part of ModeCheck about an intent that names an item and about GiveItem (the cooking ADR's
## CE1 and CE2, #770; ARCHITECTURE §9.2): static checks that return their errors, run for ModeCheck.


## An item kind's target_actions run only for an intent naming one of its items, which names no
## station: a UseStation, AtStation, StationInSight or StationUsable there finds none and always
## refuses (a dead rule, #379).
static func target_rules(owner: String, rules: Array[Rule]) -> PackedStringArray:
	var found := PackedStringArray()
	for rule: Rule in rules:
		if rule == null:
			continue
		# Untyped: a duplicate of the typed conditions would refuse the effects.
		var parts: Array = []
		parts.append_array(rule.conditions)
		parts.append_array(rule.effects)
		for part: Variant in parts:
			if (
				part is UseStation
				or part is AtStation
				or part is StationInSight
				or part is StationUsable
			):
				var text := "%s: rule %s holds %s, which finds a station, and an intent naming an item"
				text += " names none"
				found.append(
					(
						text
						% [
							owner,
							rule.trigger,
							((part as Object).get_script() as Script).get_global_name()
						]
					)
				)
	return found


## A GiveItem gives at the rule's target: only an action on an intent that names a station or an
## item (Interact) has one; a reaction, a win condition or a row has no actor and no target. And the
## host, not the content, checks that the actor may reach the target (GiveItem.required_conditions):
## an item kind's target_actions (`at_item`) hold ItemOnGround, InReach and InSight, any other rule
## AtStation and StationInSight, each not negated and in that order (ADR §2's refusal order).
static func give_rule(owner: String, rule: Rule, at_item: bool) -> PackedStringArray:
	var found := PackedStringArray()
	var gives := false
	for effect: RuleEffect in rule.effects:
		gives = gives or effect is GiveItem
	if not gives:
		return found
	if not Stations.names_station(rule.trigger):
		var text := "%s: rule %s gives an item at the rule's target" % [owner, rule.trigger]
		text += ", which only an intent naming one (%s) has" % [ModeCheck.station_intents()]
		found.append(text)
		return found
	var last := -1
	for required: Script in GiveItem.required_conditions(at_item):
		var at := _index_of(rule, required)
		if at < 0:
			var lacks := "%s: rule %s gives an item, which requires the condition %s, which it lacks"
			found.append(lacks % [owner, rule.trigger, required.get_global_name()])
		elif at < last:
			var order := "%s: rule %s holds %s before a condition that must come first (ADR §2)"
			found.append(order % [owner, rule.trigger, required.get_global_name()])
		last = maxi(last, at)
	return found


## The index of the first condition of `condition_class` in `rule` that is not negated, or -1.
static func _index_of(rule: Rule, condition_class: Script) -> int:
	for i in rule.conditions.size():
		var condition := rule.conditions[i]
		if (
			condition != null
			and not condition.negate
			and is_instance_of(condition, condition_class)
		):
			return i
	return -1


## A row's actions run with no actor, so a GiveItem among them (no target to give from) is an error.
static func row_action(
	from: StringName, outcome: StringName, action: RuleEffect
) -> PackedStringArray:
	var errors := PackedStringArray()
	if action is GiveItem:
		errors.append(
			(
				"row %s, %s gives an item, which only a player's intent naming a target can"
				% [from, outcome]
			)
		)
	return errors
