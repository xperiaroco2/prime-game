extends GdUnitTestSuite
## A guard, not a test of #1398's rules: the pinball has two flippers and nothing else a player can
## do at the table (no nudge, no TILT; #1398). It fails when a new part joins core/pinball/, when
## a rule holding a pinball part sits on an intent other than Interact and Flippers, or when an
## intent, an event or a wire row is named for a nudge or a tilt; a change that adds one is a
## design change the engineer approves first, and updates this list.

const PARTS: Array[StringName] = [
	&"EndPinball",
	&"Pinball",
	&"PinballSeated",
	&"PinballTarget",
	&"PinballTicks",
	&"PinballUsable",
	&"SetFlippers",
	&"UsePinball",
]


func test_core_pinball_holds_only_the_known_parts() -> void:
	var found: Array[StringName] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = entry["path"]
		if path.begins_with("res://core/pinball/"):
			found.append(entry["class"] as StringName)
	assert_array(found).contains_exactly_in_any_order(PARTS)


func test_only_interact_and_flippers_rules_hold_a_pinball_part() -> void:
	var made := FixturePinball.mode()
	var triggers: Dictionary[StringName, bool] = {}
	for rule: Rule in _all_rules(made):
		var parts: Array = []
		parts.append_array(rule.conditions)
		parts.append_array(rule.effects)
		for part: Variant in parts:
			if _is_pinball_part(part):
				triggers[rule.trigger] = true
	assert_array(triggers.keys()).contains_exactly_in_any_order(
		[Intents.INTERACT, Intents.FLIPPERS]
	)


func test_no_intent_event_or_wire_row_is_named_for_a_nudge_or_a_tilt() -> void:
	var names: Array[String] = []
	for intent: StringName in Intents.ALL:
		names.append(str(intent))
	for row: WireRow in WireSchema.game(true).rows():
		names.append(str(row.name))
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if (entry["path"] as String).begins_with("res://core/"):
			names.append(str(entry["class"]))
	for named: String in names:
		var lower := named.to_lower()
		(
			assert_bool(lower.contains("nudge") or lower.contains("tilt"))
			. override_failure_message(named)
			. is_false()
		)


func _all_rules(made: GameMode) -> Array[Rule]:
	var found: Array[Rule] = []
	found.append_array(made.actions)
	for kind: StationKind in Stations.kinds_in(made):
		found.append_array(kind.actions)
	return found


static func _is_pinball_part(part: Variant) -> bool:
	return (
		part is PinballUsable or part is PinballSeated or part is UsePinball or part is SetFlippers
	)
