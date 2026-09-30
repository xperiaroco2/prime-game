extends GdUnitTestSuite
## ModeCheck without layouts (ARCHITECTURE §9.1): each kind of error, found on a copy of the
## fixture mode with one thing wrong.


func test_the_fixture_mode_passes() -> void:
	var check := ModeCheck.run(FixtureModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_an_undeclared_setting() -> void:
	var mode := FixtureModes.basic()
	var bump := FixtureBump.of(&"x")
	bump.count_setting = &"nope"
	mode.actions[0].effects.append(bump)
	_expect(mode, "count_setting names setting nope, which the mode does not declare")
	bump.count_setting = &"knives"
	_expect_none(mode)


func test_an_undeclared_side() -> void:
	var mode := FixtureModes.basic()
	mode.roles[0].side = &"pirates"
	_expect(mode, "role crew names side pirates, which the mode does not declare")
	mode = FixtureModes.basic()
	mode.win_conditions[0].side = &"pirates"
	_expect(mode, "win condition crew names side pirates")


func test_an_undeclared_first_phase_or_row_phase() -> void:
	var mode := FixtureModes.basic()
	mode.transitions[0].to = &"nowhere"
	_expect(mode, "the row lobby, all_ready goes to nowhere, which is not a phase")
	mode = FixtureModes.basic()
	mode.transitions[1].from = &"nowhere"
	_expect(mode, "a row from nowhere, which is not a phase")


func test_an_outcome_a_phase_can_report_needs_a_row() -> void:
	var mode := FixtureModes.basic()
	mode.transitions.remove_at(2)
	_expect(mode, "phase end can report back, which has no transition row")
	mode = FixtureModes.basic()
	mode.transitions.remove_at(1)
	_expect(mode, "phase round can report won, which has no transition row")
	mode = FixtureModes.basic()
	mode.actions[0].effects.append(FixtureReport.of(&"meeting_called"))
	_expect(mode, "phase round can report meeting_called, which has no transition row")


func test_a_row_for_an_outcome_its_phase_never_reports() -> void:
	var mode := FixtureModes.basic()
	mode.transitions.append(FixtureModes.row(&"lobby", &"back", &"end", []))
	_expect(mode, "the row lobby, back: phase lobby never reports back")


func test_two_rows_for_one_outcome() -> void:
	var mode := FixtureModes.basic()
	mode.transitions.append(FixtureModes.row(&"end", &"back", &"round", []))
	_expect(mode, "two rows for end, back")


func test_an_accepted_intent_nobody_handles() -> void:
	var mode := FixtureModes.basic()
	mode.phases[1].accepts.append(AcceptSpec.of(Intents.PICK_UP, AcceptSpec.From.LIVING))
	_expect(mode, "phase round accepts PickUp, which neither its class nor any rule handles")
	var knife := ItemKind.new()
	knife.id = &"knife"
	knife.spawn_tag = &"knife"
	knife.actions = [FixtureModes.rule(Intents.PICK_UP, [], [])]
	mode.item_kinds = [knife]
	_expect_none(mode)


func test_an_unknown_intent_or_a_sender_nobody_matches() -> void:
	var mode := FixtureModes.basic()
	mode.phases[1].accepts.append(AcceptSpec.of(&"Hit", AcceptSpec.From.LIVING))
	_expect(mode, "phase round accepts Hit, which is no intent")
	mode = FixtureModes.basic()
	mode.phases[1].accepts[0].from = 0
	_expect(mode, "phase round accepts Use from nobody")


func test_rules_with_wrong_or_repeated_triggers() -> void:
	var mode := FixtureModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], []))
	_expect(mode, "mode.actions: two rules on Use")
	mode = FixtureModes.basic()
	mode.reactions = [FixtureModes.rule(Intents.USE, [], [])]
	_expect(mode, "mode.reactions: trigger Use is not one of")
	mode = FixtureModes.basic()
	mode.actions = [FixtureModes.rule(Facts.ITEM_RESTED, [], [])]
	_expect(mode, "mode.actions: trigger item_rested is not one of")


func test_a_negated_cost() -> void:
	var mode := FixtureModes.basic()
	var cost := FixtureCost.of(&"uses", 1)
	cost.negate = true
	mode.actions[0].conditions = [cost]
	_expect(mode, "mode.actions: rule Use negates a cost")


func test_numbers_out_of_bounds() -> void:
	var mode := FixtureModes.basic()
	mode.player_rules.health = 0
	_expect(mode, "health is 0, outside 1 to 1000")
	mode = FixtureModes.basic()
	mode.settings[0].default_value = 11
	_expect(mode, "setting knives default_value is 11, outside 0 to 10")
	mode = FixtureModes.basic()
	mode.phases[2].settings[&"go_after_ticks"] = 5000.0
	_expect(mode, "phase end: go_after_ticks is 5000, outside 0 to 1000")
	mode = FixtureModes.basic()
	mode.phases[2].settings[&"typo"] = 1.0
	_expect(mode, "phase end: unknown setting typo")


func test_repeated_ids() -> void:
	var mode := FixtureModes.basic()
	mode.roles.append(FixtureModes.role(&"crew", &"crew", false))
	_expect(mode, "two roles with the id crew")


func test_empty_entries_and_missing_parts() -> void:
	var mode := FixtureModes.basic()
	mode.actions.append(null)
	_expect(mode, "mode.actions has an empty entry")
	mode = FixtureModes.basic()
	mode.first_phase = &""
	_expect(mode, "first_phase  is not a phase of the mode")
	mode = FixtureModes.basic()
	mode.phases[0].phase_class = GameMode
	_expect(mode, "phase lobby: phase_class is not a script extending Phase")
	mode = FixtureModes.basic()
	mode.player_rules = null
	_expect(mode, "the mode has no player_rules")


func test_a_role_owned_public_event_is_a_warning_not_an_error() -> void:
	var mode := FixtureModes.basic()
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("seen")])]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).has_size(1)
	var private_note := FixtureNote.of("private")
	private_note.to_actor = true
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [private_note])]
	# The note's class could go to everyone, so the check still warns: it looks at the class.
	assert_array(Array(ModeCheck.run(mode).warnings)).has_size(1)
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureModes.place(&"x")])]
	assert_array(Array(ModeCheck.run(mode).warnings)).has_size(1)
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureBump.of(&"x")])]
	assert_array(Array(ModeCheck.run(mode).warnings)).is_empty()


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
