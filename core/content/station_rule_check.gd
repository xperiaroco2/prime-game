class_name StationRuleCheck
extends RefCounted
## The part of ModeCheck about stations (#1249, out of mode_check.gd to keep it under lint's 1000
## lines; ARCHITECTURE §9.1, §9.4.1): static checks that return their findings, run for ModeCheck.
## A station's rule (the Generator ADR's GE2, #796; the car repair ADR's RE9, #805) and the order
## of its conditions; the hand item never owning an intent that names a station; two station kinds
## of the mode's task types with one id or one spawn tag (ZE3 of the zone task ADR).


## A station's rule (the Generator ADR's GE2, #796): a UseStation only on an intent that names a
## station, with AtStation, StationInSight and StationUsable (UseStation.required_conditions); and
## a StationUsable only after AtStation and StationInSight, so its reason only ever tells about a
## station the actor has in reach and in sight (§9.4.1). A HoldStation only on an intent that names
## a station too (the car repair ADR's RE9, #805; its required conditions ModeCheck's
## _check_channel_rule's).
static func rule_problems(owner: String, rule: Rule) -> PackedStringArray:
	var found := PackedStringArray()
	var uses_station := false
	var holds := false
	for effect: RuleEffect in rule.effects:
		uses_station = uses_station or effect is UseStation or effect is HoldStation
		holds = holds or effect is HoldStation
		if effect is HoldStation and not Stations.names_station(rule.trigger):
			found.append(
				(
					"%s: rule %s holds a station, which only an intent naming one (%s) can"
					% [owner, rule.trigger, ModeCheck.station_intents()]
				)
			)
	if holds:
		found.append_array(_hold_order(owner, rule))
	if not uses_station and not Stations.names_station(rule.trigger):
		# A dead rule (#379): on an intent with no station they find none and always refuse.
		for condition: Condition in rule.conditions:
			if _is_station_condition(condition):
				(
					found
					. append(
						(
							"%s: rule %s holds %s, which finds a station only on an intent naming one (%s)"
							% [
								owner,
								rule.trigger,
								(condition.get_script() as Script).get_global_name(),
								ModeCheck.station_intents()
							]
						)
					)
				)
				break
	for effect: RuleEffect in rule.effects:
		if not effect is UseStation:
			continue
		if not Stations.names_station(rule.trigger):
			found.append(
				(
					"%s: rule %s uses a station, which only an intent naming one (%s) can"
					% [owner, rule.trigger, ModeCheck.station_intents()]
				)
			)
		for required: Script in (effect as UseStation).required_conditions():
			# Not held: no condition of that class that is not negated (a negated one passes
			# exactly where the required one would refuse).
			if _index_of(rule, required) < 0:
				(
					found
					. append(
						(
							"%s: rule %s uses a station, which requires the condition %s, which it lacks"
							% [owner, rule.trigger, required.get_global_name()]
						)
					)
				)
	# A negated StationUsable too: its not_allowed answers by the same use_problem.
	var usable := _index_of(rule, StationUsable, true)
	if usable < 0:
		return found
	for before: Script in [AtStation, StationInSight]:
		var at := _index_of(rule, before)
		if at < 0 or at > usable:
			(
				found
				. append(
					(
						(
							"%s: rule %s holds StationUsable without %s before it: its reason would tell"
							+ " about a station out of reach or out of sight"
						)
						% [owner, rule.trigger, before.get_global_name()]
					)
				)
			)
	return found


## The hand item never owns an intent that names a station (GE2): the station's kind, the role
## and the mode do, so §9.2's order (the hand item's, the role's, the mode's) holds for every other
## intent, and a later item cannot silently override or lose to a station.
static func hand_item_problems(owner: String, rules: Array[Rule]) -> PackedStringArray:
	var found := PackedStringArray()
	for rule: Rule in rules:
		if rule != null and Stations.names_station(rule.trigger):
			found.append(
				(
					(
						"%s: rule %s names a station, which a hand item never owns: the station's"
						+ " kind, the role or the mode does (§9.2)"
					)
					% [owner, rule.trigger]
				)
			)
	return found


## Two station kinds of the mode's task types with one id or one spawn tag (ZE3 of the zone task
## ADR): each task type places its stations on markers of its kind's tag without asking whether a
## station stands there already, so two kinds on one tag would share spots, and Demands counts
## palette colours per kind id. One entry per StationKind property of a task type, not per kind:
## one kind held by two properties (a zone and a circle) would share spots the same way.
static func kind_problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var paths: Array[String] = []
	var kinds: Array[StationKind] = []
	for i in mode.task_types.size():
		var type := mode.task_types[i]
		if type == null:
			continue
		var held := type.station_kinds()
		var names := Stations.property_names_of(type)
		for k in held.size():
			# The default finder is the reflection: its k-th kind is the k-th property's.
			var name := names[k] if names.size() == held.size() else "station_kinds()[%d]" % k
			paths.append("mode.task_types[%d].%s" % [i, name])
			kinds.append(held[k])
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var pair := "%s and %s" % [paths[i], paths[j]]
			if kinds[i] == kinds[j]:
				found.append("%s hold one station kind, %s" % [pair, kinds[i].id])
				continue
			if not kinds[i].id.is_empty() and kinds[i].id == kinds[j].id:
				found.append("%s: two station kinds with the id %s" % [pair, kinds[i].id])
			if not kinds[i].spawn_tag.is_empty() and kinds[i].spawn_tag == kinds[j].spawn_tag:
				found.append(
					(
						"%s: station kinds %s and %s share spawn tag %s"
						% [pair, kinds[i].id, kinds[j].id, kinds[i].spawn_tag]
					)
				)
	return found


## A HoldStation's rule holds StationInSight (a station's cylinder can reach through a thin wall,
## GE4: the re-check only runs the rule's own conditions, so a hold started through one would go
## on), and ChannelFree only after AtStation and StationInSight: its `busy` tells that another
## player holds the station, which only a player with the station in reach and in sight may hear
## (§9.4.1). A missing AtStation or ChannelFree is ModeCheck's _check_channel_rule's.
static func _hold_order(owner: String, rule: Rule) -> PackedStringArray:
	var found := PackedStringArray()
	var free := _index_of(rule, ChannelFree)
	if _index_of(rule, StationInSight) < 0:
		found.append(
			(
				(
					"%s: rule %s holds a station without StationInSight: a station behind a wall"
					+ " could be held through it"
				)
				% [owner, rule.trigger]
			)
		)
	if free < 0:
		return found
	for before: Script in [AtStation, StationInSight]:
		var at := _index_of(rule, before)
		if at > free or (at < 0 and before == StationInSight):
			found.append(
				(
					(
						"%s: rule %s holds ChannelFree without %s before it: its busy would tell"
						+ " about a station out of reach or out of sight"
					)
					% [owner, rule.trigger, before.get_global_name()]
				)
			)
	return found


## The index of the first condition of `condition_class` in `rule` that is not negated (or, with
## `negated_too`, any), or -1.
static func _index_of(rule: Rule, condition_class: Script, negated_too := false) -> int:
	for i in rule.conditions.size():
		var condition := rule.conditions[i]
		if (
			condition != null
			and (negated_too or not condition.negate)
			and is_instance_of(condition, condition_class)
		):
			return i
	return -1


## Whether `condition` is one of the three that look for the station an intent names.
static func _is_station_condition(condition: Condition) -> bool:
	return condition is AtStation or condition is StationInSight or condition is StationUsable
