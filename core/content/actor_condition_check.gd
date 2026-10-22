class_name ActorConditionCheck
extends RefCounted
## The part of ModeCheck about the conditions of the rules that run for no player (#1249, out of
## mode_check.gd to keep it under lint's 1000 lines; ARCHITECTURE §9.1, §9.2): a static check that
## returns its findings, run for ModeCheck. A reaction runs, and a win condition is checked, for no
## player (actor 0, which has no PlayerState; §9.2): a condition that reads the actor
## (Condition.reads_actor_state) tests no player there, so its answer never changes. A cost of that
## kind always refuses, so its reaction would silently never run its effects (#283) and its win
## condition never hold (#299). A negated cost in a win condition passes for actor 0 (a win
## condition pays nothing), so it gets the condition's words; in a reaction only ModeCheck's
## "negates a cost" error. A condition that reads no actor may still read the rule's target, which
## nothing supplies there (#379).


## The errors of `mode`'s reactions and win conditions that hold a condition reading the actor, or
## the rule's target where nothing supplies one.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	# ModeCheck.run starts every error with the mode's file (#1253).
	var where := "the mode"
	for index: int in mode.reactions.size():
		var rule := mode.reactions[index]
		if rule == null:
			continue
		var owner := "mode.reactions[%d]: the reaction on %s of %s" % [index, rule.trigger, where]
		for condition: Condition in rule.conditions:
			# A negated cost passes for actor 0 and is never paid: ModeCheck's "negates a cost"
			# covers it, and the reaction would run.
			if condition is Cost and condition.negate:
				continue
			var error := _actor_error(
				owner, condition, "a reaction runs", "the reaction never runs"
			)
			if error.is_empty():
				error = _target_error(owner, condition, rule.trigger)
			if not error.is_empty():
				found.append(error)
	for index: int in mode.win_conditions.size():
		var win := mode.win_conditions[index]
		if win == null:
			continue
		var owner := "mode.win_conditions[%d]: the win condition %s of %s" % [index, win.id, where]
		for condition: Condition in win.conditions:
			var error := _actor_error(
				owner, condition, "a win condition is checked", "the win condition never holds"
			)
			if error.is_empty():
				error = _target_error(owner, condition, &"")
			if not error.is_empty():
				found.append(error)
	return found


## The error for `condition` of `owner` when it reads the rule's target (Condition.needs_target)
## and nothing supplies one (#379), else "": a reaction has only its fact `fact`, which may carry
## it (Condition.target_facts); a win condition (`fact` empty) has no intent, channel or fact. A
## condition that also reads the actor got that error already, and gets no second one.
static func _target_error(owner: String, condition: Condition, fact: StringName) -> String:
	if condition == null or not condition.needs_target():
		return ""
	var why_none := "a win condition is checked with no intent, channel or fact to supply one"
	if not fact.is_empty():
		if condition.target_facts().has(fact):
			return ""
		why_none = "a reaction runs with no intent or channel and its fact %s supplies none" % fact
	return (
		(
			"%s holds the condition %s, which reads the rule's target: %s, so the condition"
			+ " finds no target and its answer never changes"
		)
		% [owner, _class_of(condition), why_none]
	)


## The error for `condition` of `owner` when it reads the actor, else "". A cost that is not
## negated always refuses actor 0; any other such condition passes always or never.
static func _actor_error(
	owner: String, condition: Condition, runs: String, never: String
) -> String:
	if condition == null or not condition.reads_actor_state():
		return ""
	if condition is Cost and not condition.negate:
		return (
			(
				"%s holds the cost %s, which reads the actor's player state: %s for no player"
				+ " (actor 0), so the cost always refuses and %s"
			)
			% [owner, _class_of(condition), runs, never]
		)
	return (
		(
			"%s holds the condition %s, which reads the actor: %s for no player (actor 0), so"
			+ " the condition tests no player and its answer never changes"
		)
		% [owner, _class_of(condition), runs]
	)


## The global class name of `condition`'s script; for a script without a class_name (an inner
## class), "a <the nearest named class it extends> with no class_name".
static func _class_of(condition: Condition) -> String:
	var script := condition.get_script() as Script
	if not script.get_global_name().is_empty():
		return String(script.get_global_name())
	while script != null and script.get_global_name().is_empty():
		script = script.get_base_script()
	var base := script.get_global_name() if script != null else &"Condition"
	return "a %s with no class_name" % base
