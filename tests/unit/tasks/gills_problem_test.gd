extends GdUnitTestSuite
## The ship engine's overheat (GillsProblem, #1461; GDD §8): the white bar's run, a press flipping
## the slit under it at the tick the host applies it, an open slit shutting again, five open fixing
## it, a press without a problem refused, the timer's blast, and the check; on
## FixtureEngineKindModes with the real kind.

const PEERS: Array[int] = [1, 2]
const ALL := 1
const SECOND := 2


func _game(seed_value: int = 7) -> Match:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.gills()]
	return FixtureEngineKindModes.in_round(FixtureEngineKindModes.of(kinds), PEERS, seed_value)


func _kind(game: Match) -> GillsProblem:
	return FixtureEngineModes.type_of(game.mode).kinds[0] as GillsProblem


## The tick in step `step` of the bar of `problem` (its first tick plus `offset`).
func _in_step(problem: EngineProblem, step: int, offset: int = 0) -> int:
	return problem.opened + step * FixtureEngineKindModes.STEP_TICKS + offset


func test_the_bar_runs_one_to_five_and_back_to_two_one_step_at_a_time() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var kind := _kind(game)
	var seen: Array[int] = []
	for step in 10:
		seen.append(kind.bar_slit(problem, _in_step(problem, step)))
	assert_array(seen).is_equal([0, 1, 2, 3, 4, 3, 2, 1, 0, 1])
	# A step's last tick is still that step; the next tick is the next slit.
	assert_int(kind.bar_slit(problem, _in_step(problem, 1, -1))).is_equal(0)
	assert_int(kind.bar_slit(problem, _in_step(problem, 1))).is_equal(1)


func test_a_press_flips_the_slit_under_the_bar_at_the_tick_the_host_applies_it() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var button := problem.stations[0]
	# The last tick of step 0: slit 0; the first tick of step 1: slit 1.
	var at := _in_step(problem, 1, -1)
	FixtureEngineKindModes.press_at(game, ALL, button, at)
	FixtureEngineKindModes.press_at(game, SECOND, button, at + 1)
	var flipped := FixtureEngineKindModes.since(game, ALL, &"GillFlipped", problem.opened - 1)
	assert_array(flipped).is_equal(
		[
			{"station": button, "slit": 0, "open": true},
			{"station": button, "slit": 1, "open": true},
		]
	)
	# Every peer gets the same, and no event names the presser.
	assert_array(flipped).is_equal(
		FixtureEngineKindModes.since(game, SECOND, &"GillFlipped", problem.opened - 1)
	)


func test_a_press_on_an_open_slit_shuts_it_again() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var button := problem.stations[0]
	FixtureEngineKindModes.press_at(game, ALL, button, _in_step(problem, 0, 1))
	# Step 8 is slit 0 again: it shuts.
	FixtureEngineKindModes.press_at(game, ALL, button, _in_step(problem, 8, 1))
	var flipped := FixtureEngineKindModes.since(game, ALL, &"GillFlipped", problem.opened - 1)
	assert_array(flipped).is_equal(
		[
			{"station": button, "slit": 0, "open": true},
			{"station": button, "slit": 0, "open": false},
		]
	)
	assert_bool(GillsProblem.is_open(problem, 0)).is_false()
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_true()


func test_five_open_slits_fix_it() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var button := problem.stations[0]
	for step in 5:
		FixtureEngineKindModes.press_at(game, ALL, button, _in_step(problem, step, 1))
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()
	var names := FixtureEngineModes.stream(
		game, SECOND, [&"GillFlipped", &"EngineProblemFixed", &"EngineBlast"]
	)
	assert_array(names.slice(-2)).is_equal([&"GillFlipped", &"EngineProblemFixed"])
	assert_int(names.count(&"GillFlipped")).is_equal(5)
	assert_int(names.count(&"EngineBlast")).is_equal(0)
	# The fixed button takes no more presses.
	FixtureEngineKindModes.press(game, ALL, button)
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")


func test_a_button_without_a_problem_is_refused() -> void:
	var game := _game()
	FixtureEngineModes.start(game, ALL)
	var task_state := FixtureEngineModes.state_of(game)
	assert_array(task_state.problems).is_empty()
	FixtureEngineKindModes.press(game, ALL, task_state.sites[0][0])
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")
	assert_array(FixtureEngineModes.dicts(game, ALL, &"GillFlipped")).is_empty()


func test_its_timer_blows_the_engine() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	FixtureEngineKindModes.press_at(game, ALL, problem.stations[0], _in_step(problem, 0, 1))
	FixtureEngineKindModes.run_to(game, problem.deadline)
	assert_int(problem.deadline - problem.opened).is_equal(FixtureEngineKindModes.GILLS_TICKS)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"EngineBlast")).has_size(1)
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()


func test_the_check() -> void:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.gills()]
	var mode := FixtureEngineKindModes.of(kinds)
	assert_array(Array(kinds[0].check(mode))).is_empty()
	var kind := kinds[0] as GillsProblem
	kind.step_seconds = 0.0
	assert_array(Array(kind.check(mode))).has_size(1)
	assert_str(kind.check(mode)[0]).contains("step_seconds")
	assert_array(GillsProblem.new().use_emits()).is_equal([GillFlippedEvent])
