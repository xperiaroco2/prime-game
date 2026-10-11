extends GdUnitTestSuite
## ModeCheck on station rules (the Generator ADR's GE2, #796; ARCHITECTURE §9.2): a station kind's
## rules trigger only on an intent that names a station; a hand item never owns one; a UseStation
## runs only on such an intent, with AtStation, StationInSight and StationUsable, StationUsable
## after the other two; a role-owned or role-gated UseStation whose type's use_emits() reaches
## everyone warns that it reveals the role, in a mode with no channel too. Each found on
## FixtureStationModes with one thing wrong.

const PANEL := "station kind panel.actions"


func test_the_station_fixtures_pass() -> void:
	for mode: GameMode in [FixtureStationModes.basic(), FixtureStationModes.plain()]:
		var check := ModeCheck.run(mode)
		assert_array(Array(check.errors)).is_empty()
		assert_array(Array(check.warnings)).is_empty()


func test_an_item_kinds_interact_rule_is_refused() -> void:
	var mode := FixtureStationModes.basic()
	var rule := FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("knife")])
	mode.find_item_kind(&"knife").actions.append(rule)
	var error := (
		"item kind knife.actions: rule Interact names a station, which a hand item never owns:"
		+ " the station's kind, the role or the mode does (§9.2)"
	)
	assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])
	# Match refuses the mode, as for every ModeCheck error.
	var game := FixtureModes.create(mode)
	assert_bool(game.start(0)).is_false()


func test_a_station_kinds_rule_triggers_only_on_an_intent_naming_a_station() -> void:
	var mode := FixtureStationModes.basic()
	_panel(mode).actions.append(FixtureModes.rule(Intents.USE, [], [FixtureNote.of("panel")]))
	_expect(mode, '%s: trigger Use is not one of [&"Interact"]' % PANEL)


func test_a_use_station_on_an_intent_naming_no_station_is_refused() -> void:
	var mode := FixtureStationModes.basic()
	var rule := FixtureStationModes.use_rule()
	rule.trigger = Intents.USE
	mode.actions.append(rule)
	_expect(mode, "mode.actions: rule Use uses a station, which only an intent naming one")


func test_a_use_station_needs_each_of_its_conditions() -> void:
	for missing: Script in [AtStation, StationInSight, StationUsable]:
		var mode := FixtureStationModes.basic()
		var rule := _panel(mode).actions[0]
		var kept: Array[Condition] = []
		for condition: Condition in rule.conditions:
			if condition.get_script() != missing:
				kept.append(condition)
		rule.conditions = kept
		var errors := Array(ModeCheck.run(mode).errors)
		assert_str(" ".join(errors)).contains(
			(
				"%s: rule Interact uses a station, which requires the condition %s, which it lacks"
				% [PANEL, missing.get_global_name()]
			)
		)
		# Without AtStation or StationInSight, StationUsable also has nothing before it.
		assert_array(errors).has_size(1 if missing == StationUsable else 2)


func test_station_usable_comes_after_reach_and_sight() -> void:
	var mode := FixtureStationModes.basic()
	var rule := _panel(mode).actions[0]
	rule.conditions = [
		HandNotTwoHanded.new(), StationUsable.new(), AtStation.new(), StationInSight.new()
	]
	var errors := Array(ModeCheck.run(mode).errors)
	assert_array(errors).has_size(2)
	assert_str(" ".join(errors)).contains(
		"%s: rule Interact holds StationUsable without AtStation before it" % PANEL
	)
	assert_str(" ".join(errors)).contains("holds StationUsable without StationInSight before it")


func test_a_role_gated_station_rule_whose_use_reaches_everyone_warns_with_no_channel() -> void:
	# plain() has no channel, so only the use's public event can reveal the role.
	var mode := FixtureStationModes.plain()
	_panel(mode).actions[0].conditions.push_front(FixtureRoleGate.new())
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).contains_exactly(
		[
			(
				(
					"%s: rule Interact is role-owned or role-gated and emits an event to everyone,"
					+ " which reveals the actor's role"
				)
				% PANEL
			)
		]
	)
	# The control: the warning comes from the type's use_emits(), which UseStation's emits() lacks.
	FixtureStationModes.type_of(mode).quiet = true
	assert_array(Array(ModeCheck.run(mode).warnings)).is_empty()


func test_a_role_owned_use_station_counts_every_task_types_use_emits() -> void:
	var mode := FixtureStationModes.plain()
	mode.find_role(&"crew").actions = [FixtureStationModes.use_rule()]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	(
		assert_str(" ".join(check.warnings))
		. contains(
			"role crew.actions: rule Interact is role-owned or role-gated and emits an event to everyone"
		)
	)
	FixtureStationModes.type_of(mode).quiet = true
	assert_array(Array(ModeCheck.run(mode).warnings)).is_empty()


func _panel(mode: GameMode) -> StationKind:
	return FixtureStationModes.type_of(mode).panel


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	assert_array(Array(errors)).has_size(1)
	assert_str(" ".join(errors)).contains(fragment)
