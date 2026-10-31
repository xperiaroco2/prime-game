extends GdUnitTestSuite
## The ship engine's fail (core/tasks/ship_engine.gd, #1453; GDD §8): a problem's timer that runs
## out blasts through the ship, knocking down every living player aboard, clearing the open
## problems and dropping the engine one stage (stage 1 restarts stage 1). A seeded Match of
## FixtureEngineModes, asserted on events and views.

const PEERS: Array[int] = [1, 2, 3]
const BLAST_NAMES: Array[StringName] = [
	&"EngineBlast", &"KnockedDown", &"ZoneProgress", &"TaskState", &"EngineProblemFixed"
]


func _round(mode: GameMode = FixtureEngineModes.basic()) -> Match:
	return FixtureEngineModes.in_round(mode, PEERS)


## Runs ticks, fixing nothing, until the next blast; at most `most` ticks.
func _to_blast(game: Match, most: int = 400) -> void:
	var blasts := FixtureEngineModes.dicts(game, 1, &"EngineBlast").size()
	for i in most:
		FixtureModes.run_ticks(game, 1)
		if FixtureEngineModes.dicts(game, 1, &"EngineBlast").size() > blasts:
			return


func _knocked(game: Match, peer: int) -> Array[int]:
	var found: Array[int] = []
	for knocked: Dictionary in FixtureEngineModes.dicts(game, peer, &"KnockedDown"):
		found.append(knocked["peer"] as int)
	return found


func test_a_timer_out_on_stage_two_knocks_down_everyone_aboard_and_drops_to_stage_one() -> void:
	var mode := FixtureEngineModes.basic()
	var game := _round(mode)
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.play_to(game, 1, 2)
	FixtureItemModes.stand(game, 1, FixtureEngineModes.ABOARD)
	FixtureItemModes.stand(game, 2, FixtureEngineModes.INSIDE_LOW)
	FixtureItemModes.stand(game, 3, Vector3(10, 0, 5))
	_to_blast(game)
	assert_array(FixtureEngineModes.dicts(game, 3, &"EngineBlast")).is_equal([{"stage": 1}])
	assert_array(_knocked(game, 3)).is_equal([1, 2])
	assert_int(game.state.player(3).life).is_equal(PlayerState.Life.ALIVE)
	assert_array(FixtureEngineModes.stream(game, 3, BLAST_NAMES).slice(-4)).is_equal(
		[&"EngineBlast", &"KnockedDown", &"KnockedDown", &"ZoneProgress"]
	)
	assert_int(task_state.stage).is_equal(1)
	assert_int(task_state.charge).is_equal(0)
	assert_array(task_state.problems).is_empty()
	var bar := FixtureEngineModes.dicts(game, 3, &"ZoneProgress")
	assert_dict(bar[-1]).is_equal(
		{
			"station": task_state.console,
			"ticks": 0,
			"needed": 3 * FixtureEngineModes.STAGE_TICKS,
			"counting": false,
			"tick": game.ticked_through()
		}
	)
	# The cleared problems were the kinds' to forget; no TaskState went back.
	var calls := (
		FixtureEngineModes.stub_of(mode, 0).calls + FixtureEngineModes.stub_of(mode, 1).calls
	)
	(
		assert_bool(calls.any(func(call: String) -> bool: return call.begins_with("cleared ")))
		. is_true()
	)
	assert_int(FixtureEngineModes.dicts(game, 3, &"TaskState").size()).is_equal(1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_fail_on_stage_one_restarts_stage_one_and_the_engine_goes_on() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	_to_blast(game)
	assert_array(FixtureEngineModes.dicts(game, 2, &"EngineBlast")).is_equal([{"stage": 1}])
	assert_int(task_state.stage).is_equal(1)
	assert_int(task_state.spawned).is_equal(0)
	assert_int(task_state.schedule.size()).is_equal(2)
	assert_int(task_state.stage_start).is_equal(game.ticked_through() + 1)
	FixtureEngineModes.play_to(game, 2, 4)
	assert_bool(task_state.done).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_downed_and_those_outside_are_spared() -> void:
	var game := _round()
	FixtureEngineModes.start(game, 1)
	for peer: int in [1, 2]:
		FixtureItemModes.stand(game, peer, FixtureEngineModes.ABOARD)
	_to_blast(game)
	assert_array(_knocked(game, 3)).is_equal([1, 2])
	# Peers 1 and 2 still lie downed (10 s), peer 3 came aboard: the next blast takes 3 alone.
	FixtureItemModes.stand(game, 3, FixtureEngineModes.ABOARD)
	_to_blast(game)
	assert_int(FixtureEngineModes.dicts(game, 3, &"EngineBlast").size()).is_equal(2)
	assert_int(game.state.player(1).life).is_equal(PlayerState.Life.DOWNED)
	assert_array(_knocked(game, 3)).is_equal([1, 2, 3])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_fail_on_stage_three_drops_to_two_and_credits_each_stage_once() -> void:
	var game := _round()
	var task_state := FixtureEngineModes.state_of(game)
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.play_to(game, 1, 3)
	_to_blast(game)
	assert_array(FixtureEngineModes.dicts(game, 1, &"EngineBlast")).is_equal([{"stage": 2}])
	assert_int(task_state.stage).is_equal(2)
	assert_int(task_state.charge).is_equal(FixtureEngineModes.STAGE_TICKS)
	FixtureEngineModes.play_to(game, 2, 4)
	assert_bool(task_state.done).is_true()
	var done: Array[int] = []
	for state: Dictionary in FixtureEngineModes.dicts(game, 1, &"TaskState"):
		done.append(state["done"] as int)
	assert_array(done).is_equal([0, 3, 3, 3])
	# One at the deal (DealTasks), then one per stage at the end.
	assert_int(FixtureEngineModes.dicts(game, 1, &"TaskProgress").size()).is_equal(4)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_fix_in_the_deadline_tick_saves_the_problem() -> void:
	var game := _one_problem_open()
	var problem := FixtureEngineModes.state_of(game).problems[0]
	FixtureModes.run_ticks(game, problem.deadline - 1 - game.ticked_through())
	FixtureEngineModes.use(game, 2, problem.stations[0])
	FixtureModes.run_ticks(game, 5)
	assert_array(FixtureEngineModes.dicts(game, 1, &"EngineBlast")).is_empty()
	assert_array(FixtureEngineModes.dicts(game, 1, &"EngineProblemFixed")).is_equal(
		[{"problem": problem.id}]
	)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_deadline_tick_blows_without_a_fix() -> void:
	var game := _one_problem_open()
	var problem := FixtureEngineModes.state_of(game).problems[0]
	FixtureModes.run_ticks(game, problem.deadline - 1 - game.ticked_through())
	assert_array(FixtureEngineModes.dicts(game, 1, &"EngineBlast")).is_empty()
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureEngineModes.dicts(game, 1, &"EngineBlast").size()).is_equal(1)
	# The use one tick late finds no problem.
	FixtureEngineModes.use(game, 2, problem.stations[0])
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 2)).is_equal([StationUsable.UNAVAILABLE])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_engine_s_events_reach_the_living_and_the_downed_alike() -> void:
	var game := _round()
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.play_to(game, 1, 2)
	FixtureItemModes.stand(game, 2, FixtureEngineModes.ABOARD)
	_to_blast(game)
	var names: Array[StringName] = [
		&"EngineProblemOpened", &"EngineProblemFixed", &"EngineBlast", &"ZoneProgress"
	]
	var seen := _events(game, 1, names)
	assert_bool(seen.is_empty()).is_false()
	for peer: int in [2, 3]:
		assert_array(_events(game, peer, names)).is_equal(seen)
	for event: Dictionary in seen:
		assert_bool(event.has("peer")).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


## A round whose stages spawn one problem each, that one open.
func _one_problem_open() -> Match:
	var mode := FixtureEngineModes.basic()
	FixtureEngineModes.type_of(mode).stage_problems = PackedInt32Array([1, 1, 1])
	var game := _round(mode)
	FixtureEngineModes.start(game, 1)
	while FixtureEngineModes.state_of(game).problems.is_empty():
		FixtureModes.run_ticks(game, 1)
	return game


func _events(game: Match, peer: int, names: Array[StringName]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events:
		if event.event_name() in names:
			found.append(event.to_dict())
	return found
