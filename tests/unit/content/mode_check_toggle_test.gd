extends GdUnitTestSuite
## ModeCheck on world toggles (#1295; ARCHITECTURE §9.4.2, §9.4.3): a ToggleStation's rule holds
## AtStation and StationInSight on an intent naming a station; a ToggleStation only in a toggle
## kind's rule; a toggle kind sharing a spawn tag with another kind; PlaceToggles' own check; a
## toggle key with a space.


func test_a_toggle_rule_without_sight_is_refused() -> void:
	var made := FixtureToggles.mode()
	var cover := _kind(made, &"cover")
	cover.actions[0].conditions = [AtStation.new()] as Array[Condition]
	assert_str(_errors(made)).contains("requires the condition StationInSight")


func test_a_toggle_in_a_role_rule_is_refused() -> void:
	var made := FixtureToggles.mode()
	made.actions.append(
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new()] as Array[Condition],
			[ToggleStation.new()] as Array[RuleEffect]
		)
	)
	assert_str(_errors(made)).contains("mode.actions: rule Interact flips a world toggle")


func test_two_toggle_kinds_on_one_spawn_tag_are_refused() -> void:
	var made := FixtureToggles.mode()
	_kind(made, &"bottle").spawn_tag = &"book"
	assert_str(_errors(made)).contains("share spawn tag book")


func test_place_toggles_with_a_kind_that_cannot_toggle_is_refused() -> void:
	var made := FixtureToggles.mode()
	_kind(made, &"breaker").actions = []
	assert_str(_errors(made)).contains("breaker, which holds no ToggleStation rule")


func test_a_toggle_key_with_a_space_is_refused() -> void:
	var made := FixtureToggles.mode()
	_kind(made, &"cover").toggle_key = &"manhole cover"
	assert_str(_errors(made)).contains("toggle_key 'manhole cover' holds a space")


static func _kind(made: GameMode, id: StringName) -> StationKind:
	for kind: StationKind in Stations.toggle_kinds(made):
		if kind.id == id:
			return kind
	return null


static func _errors(made: GameMode) -> String:
	return "\n".join(ModeCheck.run(made).errors)
