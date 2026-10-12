extends GdUnitTestSuite
## StationUsable (the Generator ADR's GE2, #796; the cooking ADR's CE11, #780; ARCHITECTURE
## §9.4.1): a task type's use_problem refuses a use only with a reason it lists in use_reasons(),
## each one of StationUsable.REASONS, whose §9.4.1 row says what it reveals; the refusal is that
## reason. A reason outside either list is a match error and refused `unavailable`. A negated
## StationUsable answers `not_allowed`, never the type's reason. TaskType's defaults refuse every
## use `unavailable`, list only it, use nothing and emit nothing.

const P1 := 1
const NEAR := Vector3(0, 0, 19.1)


func test_the_reasons_are_the_ones_architecture_describes() -> void:
	# A new reason needs its row in §9.4.1 (what it reveals) first, then this list.
	assert_array(StationUsable.REASONS).is_equal(
		[&"unavailable", &"wrong_item", &"empty_hand", &"two_handed"]
	)
	# The two it shares with the item conditions are theirs (one wire id each).
	assert_str(StationUsable.EMPTY_HAND).is_equal(HoldsItem.EMPTY_HAND)
	assert_str(StationUsable.TWO_HANDED).is_equal(HandNotTwoHanded.TWO_HANDED)


func test_a_reason_of_the_list_is_the_refusal() -> void:
	var mode := FixtureStationModes.basic()
	FixtureStationModes.type_of(mode).problem = StationUsable.UNAVAILABLE
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_each_reason_a_type_lists_is_its_refusal() -> void:
	for reason: StringName in StationUsable.REASONS:
		var mode := FixtureStationModes.basic()
		var type := FixtureStationModes.type_of(mode)
		type.reasons = StationUsable.REASONS.duplicate()
		type.problem = reason
		var game := FixtureStationModes.in_round(mode, [P1])
		FixtureItemModes.stand(game, P1, NEAR)
		FixtureStationModes.interact(game, P1, 1)
		assert_array(FixtureModes.rejections(game, P1)).is_equal([reason])
		assert_array(FixtureModes.notes(game)).is_empty()
		assert_array(Array(game.diagnostics)).is_empty()


func test_a_reason_the_type_does_not_list_is_an_error_and_refused_unavailable() -> void:
	# wrong_item is one of REASONS, but this type lists only the default.
	var mode := FixtureStationModes.basic()
	FixtureStationModes.type_of(mode).problem = StationUsable.WRONG_ITEM
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(Array(game.diagnostics)).has_size(1)
	assert_str(game.diagnostics[0]).contains("wrong_item")


func test_a_reason_outside_the_list_is_an_error_and_refused_unavailable() -> void:
	var mode := FixtureStationModes.basic()
	FixtureStationModes.type_of(mode).problem = &"saboteur_nearby"
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(Array(game.diagnostics)).has_size(1)
	assert_str(game.diagnostics[0]).contains("saboteur_nearby")


func test_a_reason_in_the_types_list_but_outside_reasons_is_still_an_error() -> void:
	# A mode that skipped ModeCheck (the type lists the reason after the match started):
	# StationUsable.REASONS does not have it, so it is still held to both lists.
	var mode := FixtureStationModes.basic()
	var type := FixtureStationModes.type_of(mode)
	var game := FixtureStationModes.in_round(mode, [P1])
	type.reasons = [StationUsable.UNAVAILABLE, &"saboteur_nearby"]
	type.problem = &"saboteur_nearby"
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(Array(game.diagnostics)).has_size(1)
	assert_str(game.diagnostics[0]).contains("saboteur_nearby")


func test_a_use_problem_that_answers_empty_the_second_time_is_still_refused() -> void:
	# use_problem should be a query that changes nothing; one that is not must not turn a refused
	# intent into an applied one with no Rejected.
	var mode := FixtureStationModes.basic()
	var type := FixtureStationModes.type_of(mode)
	type.problem = StationUsable.UNAVAILABLE
	type.empty_after_first_ask = true
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureModes.notes(game)).is_empty()


func test_a_negated_station_usable_answers_not_allowed() -> void:
	# `not StationUsable` before the plain one: a use the type takes is refused not_allowed; one it
	# refuses passes the negated condition and gets the type's reason from the plain one.
	for problem: StringName in [&"", StationUsable.WRONG_ITEM]:
		var mode := FixtureStationModes.basic()
		var type := FixtureStationModes.type_of(mode)
		type.reasons = [StationUsable.UNAVAILABLE, StationUsable.WRONG_ITEM]
		type.problem = problem
		var negated := StationUsable.new()
		negated.negate = true
		type.panel.actions[0].conditions = [
			AtStation.new(), StationInSight.new(), negated, StationUsable.new()
		]
		var game := FixtureStationModes.in_round(mode, [P1])
		FixtureItemModes.stand(game, P1, NEAR)
		FixtureStationModes.interact(game, P1, 1)
		var expected := &"not_allowed" if problem.is_empty() else &"wrong_item"
		assert_array(FixtureModes.rejections(game, P1)).is_equal([expected])
		assert_array(Array(game.diagnostics)).is_empty()


func test_a_task_type_takes_no_use_by_default() -> void:
	var plain := TaskType.new()
	plain.id = &"plain"
	plain.description = "A type with the defaults."
	assert_str(plain.use_problem(null, null, null)).is_equal("unavailable")
	assert_array(plain.use_reasons()).is_equal([&"unavailable"])
	assert_array(plain.use_emits()).is_empty()
