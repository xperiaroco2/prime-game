extends GdUnitTestSuite
## ModeCheck on the bar (#1390; ARCHITECTURE §9.4.2, §9.4.5): the fixture bar passes; the tap, a
## station kind no task type owns (StationTicks), has its rules checked like a task type's, so a
## take without AtStation is refused; a lobby phase that accepts the intent the mug drinks on
## (UseSecondary, #1438) must run DrunkTicks; Drink, StationTicks and the PlayerRules drunk scale
## bound their data.


func test_the_fixture_bar_passes() -> void:
	assert_array(Array(ModeCheck.run(FixtureBar.mode()).errors)).is_empty()


func test_the_tap_is_a_station_kind_of_the_mode() -> void:
	var made := FixtureBar.mode()
	var kinds := Stations.kinds_in(made).map(func(kind: StationKind) -> String: return kind.id)
	assert_array(kinds).contains(["tap"])


func test_a_tap_take_without_at_station_is_refused() -> void:
	var made := FixtureBar.mode()
	var tap := (
		Stations.kinds_in(made).filter(func(kind: StationKind) -> bool: return kind.id == &"tap")[0]
		as StationKind
	)
	tap.actions[0].conditions = [StationInSight.new()] as Array[Condition]
	var errors := Array(ModeCheck.run(made).errors)
	assert_array(errors.filter(_mentions("station kind tap"))).is_not_empty()


func test_a_lobby_drink_without_drunk_ticks_is_refused() -> void:
	var made := FixtureBar.mode()
	var lobby := made.find_phase(&"lobby")
	var kept: Array[TickSystem] = []
	for system: TickSystem in lobby.tick_systems:
		if not system is DrunkTicks:
			kept.append(system)
	lobby.tick_systems = kept
	var errors := Array(ModeCheck.run(made).errors)
	assert_array(errors.filter(_mentions("lists no DrunkTicks"))).has_size(1)
	assert_array(errors.filter(_mentions("accepts UseSecondary, which drinks"))).has_size(1)


func test_the_check_follows_the_drink_rule_s_trigger() -> void:
	# #1438: the mug drinks on UseSecondary, so a hall phase that accepts Use alone needs no
	# DrunkTicks; moved to Use, the same Drink needs them where Use is accepted.
	var made := FixtureBar.mode()
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		var kept: Array[TickSystem] = []
		for system: TickSystem in spec.tick_systems:
			if not system is DrunkTicks:
				kept.append(system)
		spec.tick_systems = kept
		for accept: AcceptSpec in spec.accepts.duplicate():
			if accept.intent == Intents.USE_SECONDARY:
				spec.accepts.erase(accept)
	assert_array(Array(DrunkCheck.problems(made))).is_empty()
	made.find_item_kind(&"mug").actions[0].trigger = Intents.USE
	var found := Array(DrunkCheck.problems(made))
	assert_array(found).has_size(2)
	assert_array(found.filter(_mentions("accepts Use, which drinks"))).has_size(2)


func test_a_dispensed_kind_capped_below_two_per_player_and_one_is_refused() -> void:
	var made := FixtureBar.mode()
	var least := 2 * made.max_players + 1
	assert_array(Array(DispenserCapCheck.problems(made))).is_empty()
	made.find_item_kind(&"mug").max_items = least - 1
	var errors := Array(ModeCheck.run(made).errors)
	assert_array(errors.filter(_mentions("station kind tap gives mug"))).has_size(1)
	made.find_item_kind(&"mug").max_items = least
	assert_array(Array(ModeCheck.run(made).errors)).is_empty()


func test_a_dispensed_kind_of_the_old_cap_12_is_refused_with_ten_players() -> void:
	var made := FixtureBar.mode()
	made.max_players = 10
	made.find_item_kind(&"mug").max_items = 12
	var errors := Array(DispenserCapCheck.problems(made))
	assert_array(errors).has_size(1)
	assert_str(errors[0]).contains("below 21 (2 x 10 players + 1)")
	made.find_item_kind(&"mug").max_items = 21
	assert_array(Array(DispenserCapCheck.problems(made))).is_empty()


func test_drink_bounds_its_data() -> void:
	var made := FixtureBar.mode()
	var drink := _drink_of(made)
	drink.amount = FixtureBar.MAX + 1
	assert_array(Array(ModeCheck.run(made).errors).filter(_mentions("amount"))).is_not_empty()
	drink.amount = FixtureBar.AMOUNT
	drink.empty_kind.max_items = 0
	assert_array(Array(ModeCheck.run(made).errors).filter(_mentions("max_items"))).is_not_empty()


func test_a_drink_in_a_mode_with_no_drunk_scale_is_refused() -> void:
	var made := FixtureBar.mode()
	made.player_rules.drunk_max = 0
	made.player_rules.drunk_too_much_at = 0
	made.player_rules.drunk_point_s = 0.0
	assert_array(Array(ModeCheck.run(made).errors).filter(_mentions("no bar"))).is_not_empty()


func test_the_drunk_scale_is_bounded() -> void:
	var rules := FixtureModes.player_rules()
	assert_array(Array(rules.check(null))).is_empty()
	rules.drunk_max = 256
	rules.drunk_too_much_at = 300
	rules.drunk_point_s = 0.0
	var found := Array(rules.check(null))
	for field: String in ["drunk_max", "drunk_too_much_at", "drunk_point_s"]:
		assert_array(found.filter(_mentions(field))).is_not_empty()


func test_station_ticks_needs_a_kind_with_a_spawn_tag() -> void:
	var placing := StationTicks.new()
	assert_array(Array(placing.check(null))).is_not_empty()
	placing.kind = StationKind.new()
	placing.kind.id = &"tap"
	assert_array(Array(placing.check(null))).is_not_empty()


func _drink_of(made: GameMode) -> Drink:
	return made.find_item_kind(&"mug").actions[0].effects[0] as Drink


func _mentions(text: String) -> Callable:
	return func(line: Variant) -> bool: return str(line).contains(text)
