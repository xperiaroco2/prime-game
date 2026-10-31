extends GdUnitTestSuite
## The ship's engine's run (core/tasks/ship_engine.gd, #1453; GDD §8): the start, three stages of
## 2, 4 and 6 problems at seeded moments, the bar that stops while one is open, a stage passing,
## and the end. A seeded Match of FixtureEngineModes, asserted on events and views.

const PEERS: Array[int] = [1, 2]


func _round(seed_value: int = 7) -> Match:
	return FixtureEngineModes.in_round(FixtureEngineModes.basic(), PEERS, {}, {}, seed_value)


func test_the_start_three_stages_of_two_four_and_six_problems_and_the_end() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	var console := task_state.console
	FixtureEngineModes.start(game, 1)
	assert_array(FixtureEngineModes.dicts(game, 2, &"ButtonPressed")).is_equal(
		[{"station": console}]
	)
	assert_bool(task_state.started).is_true()
	assert_int(task_state.stage).is_equal(1)
	FixtureEngineModes.play_to(game, 1, 2)
	assert_int(FixtureEngineModes.dicts(game, 2, &"EngineProblemOpened").size()).is_equal(2)
	assert_int(task_state.charge).is_equal(FixtureEngineModes.STAGE_TICKS)
	FixtureEngineModes.play_to(game, 1, 3)
	assert_int(FixtureEngineModes.dicts(game, 2, &"EngineProblemOpened").size()).is_equal(6)
	FixtureEngineModes.play_to(game, 1, 4)
	assert_bool(task_state.done).is_true()
	assert_int(FixtureEngineModes.dicts(game, 2, &"EngineProblemOpened").size()).is_equal(12)
	assert_int(FixtureEngineModes.dicts(game, 2, &"EngineProblemFixed").size()).is_equal(12)
	assert_array(FixtureEngineModes.dicts(game, 2, &"EngineBlast")).is_empty()
	var needed := 3 * FixtureEngineModes.STAGE_TICKS
	var bar := FixtureEngineModes.dicts(game, 2, &"ZoneProgress")
	assert_dict(bar[-1]).is_equal(
		{
			"station": console,
			"ticks": needed,
			"needed": needed,
			"counting": false,
			"tick": game.ticked_through()
		}
	)
	# GE13 (a): the three stages at once at the end, never before.
	var states := FixtureEngineModes.dicts(game, 2, &"TaskState")
	assert_int(states.size()).is_equal(4)
	assert_int(states[0]["done"]).is_equal(0)
	for i in range(1, 4):
		assert_int(states[i]["done"]).is_equal(3)
		assert_int(states[i]["total"]).is_equal(3)
	assert_bool(Tasks.all_done(game.state)).is_true()
	for station_id: int in task_state.stations:
		assert_bool(game.state.stations[station_id].done).is_true()
	FixtureEngineModes.use(game, 1, console)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 1)).is_equal([StationUsable.UNAVAILABLE])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_engine_waits_for_its_start() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	FixtureModes.run_ticks(game, 200)
	assert_array(FixtureEngineModes.dicts(game, 1, &"EngineProblemOpened")).is_empty()
	assert_int(task_state.charge).is_equal(0)
	# An idle site takes no use.
	FixtureEngineModes.use(game, 1, task_state.sites[0][0])
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 1)).is_equal([StationUsable.UNAVAILABLE])
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.use(game, 2, task_state.console)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 2)).is_equal([StationUsable.UNAVAILABLE])
	assert_int(FixtureEngineModes.dicts(game, 1, &"ButtonPressed").size()).is_equal(1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_problems_open_at_their_drawn_moments_spread_over_the_stage() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	var schedule := task_state.schedule.duplicate()
	var from := task_state.stage_start
	assert_int(schedule.size()).is_equal(2)
	var opened: Array[int] = []
	if not task_state.problems.is_empty():
		opened.append(game.ticked_through())
	for i in FixtureEngineModes.STAGE_TICKS:
		var opened_before := task_state.problems.size()
		FixtureModes.run_ticks(game, 1)
		for k in task_state.problems.size() - opened_before:
			opened.append(game.ticked_through())
	var expected: Array[int] = []
	for moment: int in schedule:
		assert_int(moment).is_between(0, FixtureEngineModes.STAGE_TICKS - 1)
		expected.append(from + moment)
	assert_array(opened).is_equal(expected)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_moments_follow_the_seed() -> void:
	var first := _schedule_of(7)
	assert_array(_schedule_of(7)).is_equal(first)
	var seen: Dictionary[String, bool] = {}
	for seed_value in range(1, 11):
		seen[str(_schedule_of(seed_value))] = true
	assert_int(seen.size()).is_greater(1)


func test_an_open_problem_stops_the_bar_until_it_is_fixed() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	while task_state.problems.is_empty():
		FixtureModes.run_ticks(game, 1)
	var held := task_state.charge
	FixtureModes.run_ticks(game, 10)
	assert_int(task_state.charge).is_equal(held)
	assert_bool(task_state.running).is_false()
	var bar := FixtureEngineModes.dicts(game, 2, &"ZoneProgress")
	assert_bool(bar[-1]["counting"]).is_false()
	assert_int(bar[-1]["ticks"]).is_equal(held)
	FixtureEngineModes.fix_all(game, 1)
	FixtureEngineModes.play_to(game, 1, 2)
	assert_int(task_state.stage).is_equal(2)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_bar_restarts_when_the_last_problem_is_fixed_and_the_window_ends() -> void:
	var mode := FixtureEngineModes.basic()
	FixtureEngineModes.type_of(mode).stage_problems = PackedInt32Array([1, 1, 1])
	var game := FixtureEngineModes.in_round(mode, PEERS)
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	while task_state.problems.is_empty():
		FixtureModes.run_ticks(game, 1)
	var stopped := FixtureEngineModes.dicts(game, 2, &"ZoneProgress").size()
	FixtureEngineModes.fix_all(game, 1)
	assert_bool(task_state.running).is_true()
	FixtureModes.run_ticks(game, ZoneTask.WINDOW_TICKS + 1)
	# The restart went out, held to its window's end: the clients' bar counts again.
	var bar := FixtureEngineModes.dicts(game, 2, &"ZoneProgress")
	assert_int(bar.size()).is_greater(stopped)
	assert_bool(bar[stopped]["counting"]).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_site_holds_one_problem_and_a_stage_short_of_sites_waits() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.play_to(game, 1, 3)
	# Stage 3's six problems on five sites: the sixth waits for a free one.
	for i in FixtureEngineModes.STAGE_TICKS + 1:
		FixtureModes.run_ticks(game, 1)
		var held: Array[int] = []
		for problem: EngineProblem in task_state.problems:
			for station_id: int in problem.stations:
				assert_bool(held.has(station_id)).is_false()
				held.append(station_id)
	assert_int(task_state.problems.size()).is_equal(5)
	assert_int(task_state.spawned).is_equal(5)
	FixtureEngineModes.use(game, 1, task_state.problems[0].stations[0])
	FixtureModes.run_ticks(game, 1)
	assert_int(task_state.spawned).is_equal(6)
	assert_int(task_state.problems.size()).is_equal(5)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kind_is_told_of_its_problems_and_can_span_several_sites() -> void:
	var mode := FixtureEngineModes.basic()
	FixtureEngineModes.stub_of(mode, 1).spans = 2
	var game := FixtureEngineModes.in_round(mode, PEERS)
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.play_to(game, 1, 4)
	var spanned := 0
	for opened: Dictionary in FixtureEngineModes.dicts(game, 1, &"EngineProblemOpened"):
		var stations := opened["stations"] as PackedInt32Array
		if stations.size() == 2:
			spanned += 1
			assert_bool(task_state.sites[1].has(stations[0])).is_true()
			assert_bool(stations[0] < stations[1]).is_true()
	assert_int(spanned).is_greater(0)
	var calls := FixtureEngineModes.stub_of(mode, 0).calls
	assert_bool(calls.is_empty()).is_false()
	assert_str(calls[0]).starts_with("opened ")
	assert_bool(task_state.done).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_no_stage_dealt_is_done_at_the_deal() -> void:
	var game := FixtureEngineModes.in_round(
		FixtureEngineModes.basic(0), PEERS, {}, {&"engine_stages": 0}
	)
	var task_state := FixtureEngineModes.state_of(game)
	assert_bool(task_state.done).is_true()
	assert_bool(task_state.is_done()).is_true()
	var bar := FixtureEngineModes.dicts(game, 1, &"ZoneProgress")
	assert_int(bar[0]["ticks"]).is_equal(bar[0]["needed"])
	FixtureEngineModes.use(game, 1, task_state.console)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 1)).is_equal([StationUsable.UNAVAILABLE])
	assert_array(Array(game.diagnostics)).is_empty()


func _schedule_of(seed_value: int) -> PackedInt32Array:
	var game := _round(seed_value)
	FixtureEngineModes.start(game, 1)
	return FixtureEngineModes.state_of(game).schedule.duplicate()
