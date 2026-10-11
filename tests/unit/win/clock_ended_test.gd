extends GdUnitTestSuite
## ClockEnded and the dissidents' "time up" (ARCHITECTURE §3.3, §3.4, §9.4, §9.5): the clock
## reaching its end with a subtask not done is a dissident win, on the tick the round's
## PhaseChanged announced, with 0 dissidents too; a delivery in the last tick counts, because the
## tick's commands come before its clock step. Driven through seeded matches of FixtureWinModes,
## asserted on the events and on view_of.

const P1 := 1
const P2 := 2
const P3 := 3


func test_the_clock_ending_with_a_subtask_not_done_is_a_dissident_win() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2, P3])
	var crew := FixtureDealModes.players_of(game, &"crew")
	FixtureWinModes.deliver(game, crew[0], 0)
	var end := FixtureWinModes.announced_end(game, P1)
	FixtureWinModes.run_through(game, end - 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.clock_ended).is_false()
	FixtureWinModes.run_through(game, end)
	assert_bool(game.state.clock_ended).is_true()
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("dissidents")
	for peer: int in [P1, P2, P3]:
		var ended := game.view_of(peer).events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		assert_dict(ended[0].to_dict()).is_equal(
			{
				"side": &"dissidents",
				"reason": &"time_up",
				"numbers": {&"time": FixtureWinModes.MINUTES * 60}
			}
		)
	var at := game.emitted().filter(
		func(e: EmittedEvent) -> bool: return e.event is MatchEndedEvent
	)
	assert_int((at[0] as EmittedEvent).tick).is_equal(end)
	assert_array(Array(game.diagnostics)).is_empty()


func test_with_no_dissidents_the_clock_ending_is_still_a_dissident_win() -> void:
	# The engineer's decision (MVP rules): with 0 dissidents the crew loses when time is up.
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2], {&"dissidents": 0})
	assert_array(FixtureDealModes.players_of(game, &"dissident")).is_empty()
	FixtureWinModes.run_through(game, FixtureWinModes.announced_end(game, P1))
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("dissidents")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"dissidents"])


func test_a_delivery_in_the_last_tick_counts() -> void:
	# The commands of a tick come before its clock step (§3.3): the last package put down on the
	# end tick finishes every task before the clock ends, and the crew wins.
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var crew := FixtureDealModes.players_of(game, &"crew")[0]
	FixtureWinModes.hold_over_circle(game, crew, 0)
	var end := FixtureWinModes.announced_end(game, P1)
	FixtureWinModes.run_through(game, end - 1)
	FixtureItemModes.stand(game, crew, game.state.player(crew).position - Vector3(1, 0, 0))
	FixtureItemModes.put_down(game, crew, Vector3.RIGHT)
	assert_int(game.ticked_through()).is_equal(end - 1)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.run_ticks(game, 1)
	assert_str(game.state.winner).is_equal("crew")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"crew"])
	# End's clock does not run: the clock never reached its end.
	assert_bool(game.state.clock_ended).is_false()


func test_a_delivery_after_the_end_tick_is_too_late() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var crew := FixtureDealModes.players_of(game, &"crew")[0]
	FixtureWinModes.hold_over_circle(game, crew, 0)
	FixtureWinModes.run_through(game, FixtureWinModes.announced_end(game, P1))
	assert_str(game.state.winner).is_equal("dissidents")
	FixtureItemModes.stand(game, crew, game.state.player(crew).position - Vector3(1, 0, 0))
	FixtureItemModes.put_down(game, crew, Vector3.RIGHT, 5)
	assert_array(FixtureModes.rejections(game, crew)).is_equal([&"not_accepted"])
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"dissidents"])


func test_the_condition_fails_until_the_clock_has_ended() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2])
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	var clock := ClockEnded.new()
	assert_bool(clock.passes(ctx)).is_false()
	game.state.clock_ended = true
	assert_bool(clock.passes(ctx)).is_true()


func test_without_start_clock_the_clock_never_ends() -> void:
	var mode := FixtureWinModes.basic(2)
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.pop_back()
	var game := FixtureWinModes.in_round(mode, [P1, P2])
	assert_int(FixtureWinModes.announced_end(game, P1)).is_equal(-1)
	FixtureModes.run_ticks(game, FixtureWinModes.CLOCK_TICKS + 20)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.clock_ended).is_false()
