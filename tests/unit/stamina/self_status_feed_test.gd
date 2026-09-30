extends GdUnitTestSuite
## SelfStatusFeed (ARCHITECTURE §4.2, §7.1): SelfStatus to that player only, on change, at most once
## per tick with the tick's final numbers, and again after ResetMatch.

const P1 := 1
const P2 := 2
const NORTH := Vector3(0, 0, 1)


func test_it_goes_only_to_that_player() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(1)
	assert_dict(statuses[0].to_dict()).is_equal(
		{"health": 100000, "stamina": 100000, "sprint_available": true}
	)
	assert_array(FixtureMoves.statuses(game, P2)).is_empty()


func test_it_is_sent_only_on_change() -> void:
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.steps(game, P1, 5, Vector3.ZERO)
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(1)
	FixtureMoves.steps(game, P1, 3, NORTH * 0.3, FixtureMoves.sprinting())
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(4)


func test_it_is_sent_at_most_once_per_tick_with_the_final_numbers() -> void:
	var mode := FixtureModes.basic()
	var cost := StaminaCost.new()
	cost.amount = 25
	mode.actions[0].conditions = [cost]
	var game := FixtureModes.in_round(mode, [P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.claim(game, P1, player.position + NORTH * 0.3, FixtureMoves.sprinting())
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	FixtureModes.run_ticks(game, 1)
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(seen + 1)
	assert_int(statuses.back().stamina).is_equal(74000)


func test_a_change_by_a_transition_in_a_tick_goes_out_in_that_tick() -> void:
	var mode := FixtureModes.basic()
	# The clock ends in a tick, the crew wins, and the row to End tires P1 on the way.
	mode.reactions = [FixtureModes.rule(Facts.CLOCK_ENDED, [], [FixtureBump.of(&"crew_win")])]
	mode.transitions[1].actions.append(FixtureTire.of(P1, 30))
	var game := FixtureModes.in_round(mode, [P1])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	game.state.clock_ticks_left = 2
	FixtureModes.run_ticks(game, 2)
	assert_str(String(game.phase_id())).is_equal("end")
	var last: SelfStatusEvent = FixtureMoves.statuses(game, P1).back()
	assert_int(last.stamina).is_equal(70000)
	var sent := game.emitted().filter(
		func(e: EmittedEvent) -> bool: return e.event is SelfStatusEvent
	)
	assert_int((sent.back() as EmittedEvent).tick).is_equal(game.ticked_through())


func test_it_is_sent_again_after_reset_match() -> void:
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.steps(game, P1, 2, Vector3.ZERO)
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(1)
	game.state.reset_match()
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(2)
	assert_int(statuses.back().stamina).is_equal(100000)
