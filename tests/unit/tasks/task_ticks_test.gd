extends GdUnitTestSuite
## TaskTicks (ARCHITECTURE §3.3, §9.4): every tick of a phase that lists it, the tick of each of
## the mode's task types that has one, in the mode's order. None ticks in the MVP;
## FixtureTickingTaskType stands in for #36.

const P1 := 1


func test_it_runs_each_ticking_task_type_in_the_modes_order_every_tick() -> void:
	var mode := _mode()
	var game := FixtureModes.in_round(mode, [P1])
	assert_str(game.phase_id()).is_equal("round")
	var from := game.ticked_through() + 1
	FixtureModes.run_ticks(game, 2)
	(
		assert_array(FixtureModes.notes(game))
		. is_equal(
			[
				_note(&"zone_a", from),
				_note(&"zone_b", from),
				_note(&"zone_a", from + 1),
				_note(&"zone_b", from + 1),
			]
		)
	)


func test_it_does_not_run_in_a_phase_that_does_not_list_it() -> void:
	var game := FixtureModes.started(_mode(), [P1])
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureModes.run_ticks(game, 3)
	assert_array(FixtureModes.notes(game)).is_empty()


func test_without_a_ticking_task_type_it_does_nothing() -> void:
	var mode := FixtureModes.basic()
	mode.find_phase(&"round").tick_systems = [TaskTicks.new()]
	var game := FixtureModes.in_round(mode, [P1])
	var emitted_before := game.emitted().size()
	FixtureModes.run_ticks(game, 2)
	assert_int(game.emitted().size()).is_equal(emitted_before)
	assert_array(Array(game.diagnostics)).is_empty()


func test_delivery_has_no_tick() -> void:
	assert_bool(Delivery.new().has_tick()).is_false()


func test_the_mode_check_accepts_it() -> void:
	assert_array(Array(ModeCheck.run(_mode()).errors)).is_empty()


## The fixture mode with, in order, a task type that does not tick and two that do, and TaskTicks
## in Round.
func _mode() -> GameMode:
	var mode := FixtureModes.basic()
	mode.task_types = [
		FixtureTaskType.new(),
		FixtureTickingTaskType.of(&"zone_a"),
		FixtureTickingTaskType.of(&"zone_b"),
	]
	mode.find_phase(&"round").tick_systems = [TaskTicks.new()]
	return mode


func _note(type_id: StringName, at_tick: int) -> String:
	return "tick %s %d tick of task type %s" % [type_id, at_tick, type_id]
