extends GdUnitTestSuite
## The ship engine's tripped breakers (BreakersProblem, #1461; GDD §8 "Tripped breakers"): the
## boards and orders per stage, the order told to every peer, the chain switched on in order inside
## each green window, the short circuit (too early, out of order) knocking only the presser down,
## a too-late chain unwinding, refused uses, the timer's blast, the demands and the check; on
## FixtureEngineKindModes with the real kind.

const PEERS: Array[int] = [1, 2]
const ALL := 1
const SECOND := 2
const RAMP := FixtureEngineKindModes.RAMP_TICKS
const GREEN := FixtureEngineKindModes.GREEN_TICKS


func _game(seed_value: int = 7) -> Match:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.breakers()]
	return FixtureEngineKindModes.in_round(FixtureEngineKindModes.of(kinds), PEERS, seed_value)


func _kind(game: Match) -> BreakersProblem:
	return FixtureEngineModes.type_of(game.mode).kinds[0] as BreakersProblem


## ALL starts the engine, which is then set on `stage`; the ticks run until `count` problems are
## open (at most `most`). Returns them in opening order.
func _open(game: Match, stage: int, count: int = 1, most: int = 40) -> Array[EngineProblem]:
	FixtureEngineModes.start(game, ALL)
	var task_state := FixtureEngineModes.state_of(game)
	task_state.stage = stage
	for i in most:
		if task_state.problems.size() >= count:
			break
		FixtureModes.run_ticks(game, 1)
	return task_state.problems.duplicate()


## The BreakerChain events `peer` received for `problem` (another problem may open meanwhile).
func _chain(game: Match, peer: int, problem: EngineProblem) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for chain: Dictionary in FixtureEngineModes.dicts(game, peer, &"BreakerChain"):
		if chain["problem"] == problem.id:
			found.append(chain)
	return found


func _order(problem: EngineProblem) -> PackedInt32Array:
	return (problem.data as BreakersProblem.Data).order


## The board each breaker of `problem`'s order is on.
func _boards_of(game: Match, problem: EngineProblem) -> Array[int]:
	var groups := _kind(game).breakers_of(game.state, FixtureEngineModes.task_of(game))
	var found: Array[int] = []
	for breaker: int in _order(problem):
		for board: int in groups:
			if groups[board].has(breaker):
				found.append(board)
	return found


func test_each_breaker_belongs_to_the_board_nearest_it() -> void:
	var game := _game()
	var task_state := FixtureEngineModes.state_of(game)
	var groups := _kind(game).breakers_of(game.state, FixtureEngineModes.task_of(game))
	var boards := task_state.sites[0]
	assert_int(groups.size()).is_equal(2)
	for b in boards.size():
		var group := groups[boards[b]]
		assert_int(group.size()).is_equal(BreakersProblem.BREAKERS_PER_BOARD)
		for breaker: int in group:
			var spot := game.state.stations[breaker].position
			var own := FixtureEngineKindModes.BOARDS[b]
			var other := FixtureEngineKindModes.BOARDS[1 - b]
			assert_bool(spot.distance_to(own) < spot.distance_to(other)).is_true()


func test_stage_one_trips_two_breakers_of_one_board_and_tells_every_peer() -> void:
	var game := _game()
	var problems := _open(game, 1, 2)
	assert_int(problems.size()).is_equal(2)
	for problem: EngineProblem in problems:
		assert_int(problem.stations.size()).is_equal(1)
		assert_int(_order(problem).size()).is_equal(2)
		var boards := _boards_of(game, problem)
		assert_array(boards).is_equal([problem.stations[0], problem.stations[0]])
	# The two problems hold the two boards.
	assert_int(problems[0].stations[0]).is_not_equal(problems[1].stations[0])
	var told: Array[Dictionary] = []
	for problem: EngineProblem in problems:
		told.append({"problem": problem.id, "breakers": _order(problem), "next": 0, "since": -1})
	for peer: int in PEERS:
		assert_array(FixtureEngineModes.dicts(game, peer, &"BreakerChain")).is_equal(told)


func test_stage_two_trips_four_with_one_change_of_side() -> void:
	var game := _game()
	var problem := _open(game, 2)[0]
	assert_int(problem.stations.size()).is_equal(2)
	var boards := _boards_of(game, problem)
	assert_int(boards.size()).is_equal(4)
	assert_int(boards[0]).is_equal(boards[1])
	assert_int(boards[2]).is_equal(boards[3])
	assert_int(boards[1]).is_not_equal(boards[2])


func test_a_drawn_order_never_repeats_a_breaker_over_twenty_seeds() -> void:
	for seed_value in 20:
		for stage: int in [2, 3]:
			var game := _game(seed_value + 1)
			var problem := _open(game, stage)[0]
			var order := _order(problem)
			assert_int(order.size()).is_equal(2 * stage)
			var seen: Dictionary[int, bool] = {}
			for breaker: int in order:
				seen[breaker] = true
			(
				assert_int(seen.size())
				. override_failure_message("seed %d stage %d: %s" % [seed_value + 1, stage, order])
				. is_equal(order.size())
			)


func test_stage_three_trips_six_alternating_sides() -> void:
	var game := _game()
	var problem := _open(game, 3)[0]
	var boards := _boards_of(game, problem)
	assert_int(boards.size()).is_equal(6)
	for i in 5:
		assert_int(boards[i]).is_not_equal(boards[i + 1])


func test_a_later_stage_with_one_board_free_trips_that_board_only() -> void:
	var game := _game()
	var first := _open(game, 1)[0]
	var task_state := FixtureEngineModes.state_of(game)
	task_state.stage = 2
	for i in 40:
		if task_state.problems.size() >= 2:
			break
		FixtureModes.run_ticks(game, 1)
	var second := task_state.problems[1]
	assert_int(second.stations.size()).is_equal(1)
	assert_int(second.stations[0]).is_not_equal(first.stations[0])
	var boards := _boards_of(game, second)
	assert_int(boards.size()).is_equal(4)
	assert_int(boards.count(second.stations[0])).is_equal(4)


func test_the_chain_in_order_inside_each_green_window_fixes_it() -> void:
	var game := _game()
	var problem := _open(game, 2)[0]
	var order := _order(problem)
	var at := FixtureEngineKindModes.press(game, ALL, order[0])
	# Its green starts after the ramp; the next goes on there, then at the window's last tick.
	FixtureEngineKindModes.press_at(game, SECOND, order[1], at + RAMP)
	FixtureEngineKindModes.press_at(game, ALL, order[2], at + RAMP + RAMP + GREEN)
	at = at + RAMP + RAMP + GREEN
	FixtureEngineKindModes.press_at(game, SECOND, order[3], at + RAMP + 5)
	# The open, then one chain per breaker on, each counting one more.
	var chain := _chain(game, SECOND, problem)
	assert_int(chain.size()).is_equal(5)
	for i in 5:
		assert_int(chain[i]["problem"]).is_equal(problem.id)
		assert_array(chain[i]["breakers"]).is_equal(order)
		assert_int(chain[i]["next"]).is_equal(i)
	assert_int(chain[0]["since"]).is_equal(-1)
	assert_int(chain[4]["since"]).is_equal(at + RAMP + 5)
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()
	assert_array(FixtureEngineModes.dicts(game, ALL, &"EngineProblemFixed")).has_size(1)
	assert_array(FixtureEngineModes.dicts(game, ALL, &"KnockedDown")).is_empty()


func test_too_early_is_a_short_circuit_knocking_down_the_presser_only() -> void:
	var game := _game()
	var problem := _open(game, 1)[0]
	var order := _order(problem)
	var at := FixtureEngineKindModes.press(game, ALL, order[0])
	# Still yellow: the last tick of its ramp.
	FixtureEngineKindModes.press_at(game, SECOND, order[1], at + RAMP - 1)
	var down := FixtureEngineModes.dicts(game, ALL, &"KnockedDown")
	assert_int(down.size()).is_equal(1)
	assert_int(down[0]["peer"]).is_equal(SECOND)
	assert_bool(game.state.player(ALL).is_alive()).is_true()
	assert_array(_chain(game, ALL, problem)).has_size(2)
	# Nothing else changed: the chain goes on from the first breaker.
	assert_int((problem.data as BreakersProblem.Data).next).is_equal(1)
	FixtureEngineKindModes.press_at(game, ALL, order[1], at + RAMP)
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()


func test_a_breaker_out_of_order_is_a_short_circuit() -> void:
	var game := _game()
	var problem := _open(game, 1)[0]
	var order := _order(problem)
	FixtureEngineKindModes.press(game, ALL, order[1])
	var down := FixtureEngineModes.dicts(game, SECOND, &"KnockedDown")
	assert_int(down.size()).is_equal(1)
	assert_int(down[0]["peer"]).is_equal(ALL)
	assert_array(_chain(game, SECOND, problem)).has_size(1)
	assert_int((problem.data as BreakersProblem.Data).next).is_equal(0)


func test_too_late_the_one_before_trips_again_and_the_chain_unwinds() -> void:
	var game := _game()
	var problem := _open(game, 2)[0]
	var order := _order(problem)
	var at := FixtureEngineKindModes.press(game, ALL, order[0])
	var second := at + RAMP
	FixtureEngineKindModes.press_at(game, ALL, order[1], second)
	# Its window's last tick passes: it trips again, and the first is green from then on.
	var late := second + RAMP + GREEN + 1
	FixtureEngineKindModes.run_to(game, late)
	# The open, two on, then the unwind: one on, its window green from `late`.
	var chain := _chain(game, SECOND, problem)
	assert_int(chain.size()).is_equal(4)
	assert_dict(chain[3]).is_equal(
		{"problem": problem.id, "breakers": order, "next": 1, "since": late - RAMP}
	)
	var data := problem.data as BreakersProblem.Data
	assert_int(data.next).is_equal(1)
	# The first one's fresh window ends a whole green later: then it trips too.
	FixtureEngineKindModes.run_to(game, late + GREEN + 1)
	chain = _chain(game, SECOND, problem)
	assert_int(chain.size()).is_equal(5)
	assert_dict(chain[4]).is_equal(
		{"problem": problem.id, "breakers": order, "next": 0, "since": -1}
	)
	assert_int(data.next).is_equal(0)
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_true()


func test_a_late_chain_goes_on_from_the_one_before_in_its_fresh_window() -> void:
	var game := _game()
	var problem := _open(game, 2)[0]
	var order := _order(problem)
	var at := FixtureEngineKindModes.press(game, ALL, order[0])
	FixtureEngineKindModes.press_at(game, ALL, order[1], at + RAMP)
	var late := at + RAMP + RAMP + GREEN + 1
	FixtureEngineKindModes.run_to(game, late)
	# The first is green now: the second goes on again at once.
	FixtureEngineKindModes.press_at(game, ALL, order[1], late + 1)
	assert_int((problem.data as BreakersProblem.Data).next).is_equal(2)
	assert_array(FixtureEngineModes.dicts(game, ALL, &"KnockedDown")).is_empty()


func test_a_board_and_a_breaker_already_on_or_not_tripped_are_refused() -> void:
	var game := _game()
	var problem := _open(game, 1)[0]
	var order := _order(problem)
	FixtureEngineKindModes.press(game, ALL, problem.stations[0])
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")
	FixtureEngineKindModes.press(game, ALL, order[0])
	FixtureEngineKindModes.press(game, ALL, order[0])
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")
	var groups := _kind(game).breakers_of(game.state, FixtureEngineModes.task_of(game))
	var healthy := -1
	for breaker: int in groups[problem.stations[0]]:
		if not order.has(breaker):
			healthy = breaker
	FixtureEngineKindModes.press(game, ALL, healthy)
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")
	assert_array(FixtureEngineModes.dicts(game, ALL, &"KnockedDown")).is_empty()
	assert_array(FixtureEngineModes.dicts(game, ALL, &"Rejected")).has_size(3)


func test_its_timer_blows_the_engine() -> void:
	var game := _game()
	var problem := _open(game, 1)[0]
	FixtureEngineKindModes.run_to(game, problem.deadline)
	assert_int(problem.deadline - problem.opened).is_equal(FixtureEngineKindModes.BREAKERS_TICKS)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"EngineBlast")).has_size(1)
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()


func test_it_demands_exactly_four_breakers_a_board() -> void:
	var kind := FixtureEngineKindModes.breakers()
	var demands := Demands.new(null)
	kind.add_demands(demands)
	assert_int(demands.markers[&"breaker_board"]).is_equal(2)
	assert_int(demands.markers[&"breaker"]).is_equal(8)
	assert_bool(demands.exact.has(&"breaker")).is_true()
	assert_bool(demands.exact.has(&"breaker_board")).is_true()


func test_the_check() -> void:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.breakers()]
	var mode := FixtureEngineKindModes.of(kinds)
	var kind := kinds[0] as BreakersProblem
	assert_array(Array(kind.check(mode))).is_empty()
	kind.green_seconds = 0.0
	assert_str(" ".join(kind.check(mode))).contains("green_seconds")
	kind.green_seconds = FixtureEngineKindModes.GREEN_SECONDS
	kind.trips = PackedInt32Array([2, 4])
	assert_str(" ".join(kind.check(mode))).contains("one size")
	kind.trips = PackedInt32Array([2, 4, 9])
	assert_str(" ".join(kind.check(mode))).contains("trips")
	kind.trips = PackedInt32Array([2, 4, 6])
	kind.side_changes = PackedInt32Array([0, 0, 0])
	# Six on one board: more than it holds.
	assert_str(" ".join(kind.check(mode))).contains("more than 4")
	kind.side_changes = PackedInt32Array([0, 1, 5])
	kind.fixtures = []
	assert_str(" ".join(kind.check(mode))).contains("one fixture")
	assert_array(kind.use_emits()).contains([BreakerChainEvent, KnockedDownEvent])
