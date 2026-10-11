extends GdUnitTestSuite
## StationUsable (the Generator ADR's GE2, #796; ARCHITECTURE §9.4.1): a task type's use_problem
## refuses a use only with a reason of StationUsable.REASONS, each of which §9.4.1 says what it
## reveals; a reason outside the list is a match error and refused `unavailable`. TaskType's
## defaults refuse every use `unavailable`, use nothing and emit nothing.

const P1 := 1
const NEAR := Vector3(0, 0, 19.1)


func test_the_reasons_are_the_ones_architecture_describes() -> void:
	# A new reason needs its row in §9.4.1 (what it reveals) first, then this list.
	assert_array(StationUsable.REASONS).is_equal([&"unavailable"])


func test_a_reason_of_the_list_is_the_refusal() -> void:
	var mode := FixtureStationModes.basic()
	FixtureStationModes.type_of(mode).problem = StationUsable.UNAVAILABLE
	var game := FixtureStationModes.in_round(mode, [P1])
	FixtureItemModes.stand(game, P1, NEAR)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


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


func test_a_task_type_takes_no_use_by_default() -> void:
	var mode := FixtureStationModes.basic()
	var plain := TaskType.new()
	plain.id = &"plain"
	plain.description = "A type with the defaults."
	assert_str(plain.use_problem(null, null, null)).is_equal("unavailable")
	assert_array(plain.use_emits()).is_empty()
	var game := FixtureStationModes.in_round(mode, [P1])
	var station: StationState = game.state.stations[1]
	plain.use_station(null, null, station)
	assert_array(FixtureModes.notes(game)).is_empty()
