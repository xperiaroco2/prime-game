extends GdUnitTestSuite
## ModeCheck on the photo booth (#1396; ARCHITECTURE §9.4.2, §9.4.5, §9.5.29): the fixture booth
## passes; StartBooth stands only in a station kind's Interact rule with AtStation and
## StationInSight; a mode with one lists BoothTicks, only on the lobby's level; a row out of a
## BoothTicks phase into one without holds StopBooth; StartBooth bounds its numbers and its strip.


func _mentions(text: String) -> Callable:
	return func(line: String) -> bool: return line.contains(text)


func _errors(made: GameMode) -> Array:
	return Array(ModeCheck.run(made).errors)


func _without_booth_ticks(spec: PhaseSpec) -> void:
	var kept: Array[TickSystem] = []
	for system: TickSystem in spec.tick_systems:
		if not system is BoothTicks:
			kept.append(system)
	spec.tick_systems = kept


func test_the_fixture_booth_passes() -> void:
	assert_array(_errors(FixtureBooth.mode())).is_empty()


func test_a_press_without_at_station_is_refused() -> void:
	var made := FixtureBooth.mode()
	var start := FixtureBooth.start_in(made)
	for kind: StationKind in Stations.kinds_in(made):
		if kind.id == &"booth":
			kind.actions[0].conditions = [StationInSight.new()] as Array[Condition]
	assert_object(start).is_not_null()
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("lacks the condition AtStation"))).has_size(1)


func test_a_start_booth_on_another_trigger_is_refused() -> void:
	var made := FixtureBooth.mode()
	for kind: StationKind in Stations.kinds_in(made):
		if kind.id == &"booth":
			kind.actions[0].trigger = Intents.USE
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("not Interact"))).has_size(1)


func test_a_start_booth_outside_a_station_is_refused() -> void:
	var made := FixtureBooth.mode()
	var start := FixtureBooth.start_of(made.find_item_kind(&"strip"))
	made.actions.append(
		FixtureModes.rule(Intents.INTERACT, [] as Array[Condition], [start] as Array[RuleEffect])
	)
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("only a station's rule can"))).has_size(1)


func test_a_booth_with_no_booth_ticks_is_refused() -> void:
	var made := FixtureBooth.mode()
	_without_booth_ticks(made.find_phase(&"lobby"))
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("no phase lists BoothTicks"))).has_size(1)


func test_booth_ticks_off_the_lobby_s_level_is_refused() -> void:
	var made := FixtureBooth.mode()
	var round_spec: PhaseSpec = null
	for phase: PhaseSpec in made.phases:
		if phase.level != PhaseSpec.Level.LOBBY and round_spec == null:
			round_spec = phase
	round_spec.tick_systems.append(BoothTicks.new())
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("off the lobby's level"))).has_size(1)


func test_a_row_out_of_the_booth_s_clock_without_stop_booth_is_refused() -> void:
	var made := FixtureBooth.mode()
	for row: Transition in made.transitions:
		var kept: Array[RuleEffect] = []
		for action: RuleEffect in row.actions:
			if not action is StopBooth:
				kept.append(action)
		row.actions = kept
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("without StopBooth"))).is_not_empty()
	assert_array(found.filter(_mentions("row lobby, all_ready"))).has_size(1)


func test_start_booth_bounds_its_numbers_and_its_strip() -> void:
	var made := FixtureBooth.mode()
	var start := FixtureBooth.start_in(made)
	start.frames = StartBooth.MAX_FRAMES + 1
	start.countdown_s = 0.0
	start.gap_s = StartBooth.COUNTDOWN_HIGH_S + 1
	made.find_item_kind(&"strip").max_items = 0
	var errors := _errors(made)
	for field: String in ["frames", "countdown_s", "gap_s", "must be one-handed and set max_items"]:
		assert_array(errors.filter(_mentions(field))).is_not_empty()


func test_a_mode_without_a_booth_needs_nothing() -> void:
	assert_array(Array(BoothCheck.problems(FixtureLobbyHands.mode()))).is_empty()


func test_a_row_out_of_the_booth_s_clock_with_other_actions_but_no_stop_booth_is_refused() -> void:
	var made := FixtureBooth.mode()
	for row: Transition in made.transitions:
		var kept: Array[RuleEffect] = [ResetMatch.new()]
		for action: RuleEffect in row.actions:
			if not action is StopBooth:
				kept.append(action)
		row.actions = kept
	var found := Array(BoothCheck.problems(made))
	assert_array(found.filter(_mentions("row lobby, all_ready"))).has_size(1)
	assert_array(found.filter(_mentions("without StopBooth"))).is_not_empty()
