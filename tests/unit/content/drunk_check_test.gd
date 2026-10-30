extends GdUnitTestSuite
## ModeCheck on the bar (#1390; ARCHITECTURE §9.4.2, §9.4.5): the fixture bar passes; the tap, a
## station kind no task type owns (StationTicks), has its rules checked like a task type's, so a
## take without AtStation is refused; a lobby phase that accepts Use, which drinks, must run
## DrunkTicks; Drink, StationTicks and the PlayerRules drunk scale bound their data.


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


func test_a_lobby_use_without_drunk_ticks_is_refused() -> void:
	var made := FixtureBar.mode()
	var lobby := made.find_phase(&"lobby")
	var kept: Array[TickSystem] = []
	for system: TickSystem in lobby.tick_systems:
		if not system is DrunkTicks:
			kept.append(system)
	lobby.tick_systems = kept
	var errors := Array(ModeCheck.run(made).errors)
	assert_array(errors.filter(_mentions("lists no DrunkTicks"))).has_size(1)


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
