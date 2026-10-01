extends GdUnitTestSuite
## StartClock (ARCHITECTURE §3.2, §3.3, §9.4): the last action of the deal's row sets the match
## clock to the `minutes_setting` in host ticks and emits RoundStarted (everyone) with the start
## tick, after PlayersPlaced; the round's PhaseChanged announces the clock's end. A new round
## after End -> Lobby starts a fresh clock. Its mode check needs a setting of at least 1 minute. A
## forced clock (ForceClock, debug builds only: the bot scenarios' clock_s) replaces it, in seconds.

const P1 := 1
const P2 := 2
const P3 := 3


func test_the_deal_starts_the_clock_and_everyone_learns_the_start_tick() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2, P3])
	var start := game.ticked_through() + 1
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.clock_ticks_left).is_equal(FixtureWinModes.CLOCK_TICKS)
	assert_bool(game.state.clock_ended).is_false()
	for peer: int in [P1, P2, P3]:
		var view := game.view_of(peer)
		var started := view.events_named(&"RoundStarted")
		assert_int(started.size()).is_equal(1)
		assert_dict(started[0].to_dict()).is_equal({"start_tick": start})
		# The last action of the row: after the placement, before the round's PhaseChanged.
		var names := view.event_names()
		var at := names.find(&"RoundStarted")
		assert_int(at).is_greater(names.rfind(&"PlayersPlaced"))
		assert_str(String(names[at + 1])).is_equal("PhaseChanged")
		# The clock's first step is the start tick's own, so it ends CLOCK_TICKS - 1 ticks later.
		assert_int(FixtureWinModes.announced_end(game, peer)).is_equal(
			start + FixtureWinModes.CLOCK_TICKS - 1
		)


func test_the_setting_gives_the_length_in_minutes() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2], {&"match_duration": 3})
	assert_int(game.state.clock_ticks_left).is_equal(3 * 60 * Ticks.RATE)
	FixtureModes.run_ticks(game, 10)
	assert_int(game.state.clock_ticks_left).is_equal(3 * 60 * Ticks.RATE - 10)


func test_a_new_round_after_the_lobby_starts_a_fresh_clock() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2])
	FixtureWinModes.run_through(game, FixtureWinModes.announced_end(game, P1))
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.clock_ended).is_true()
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	# ResetMatch cleared the clock and the winner.
	assert_int(game.state.clock_ticks_left).is_equal(-1)
	assert_bool(game.state.clock_ended).is_false()
	assert_str(game.state.winner).is_empty()
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.clock_ticks_left).is_equal(FixtureWinModes.CLOCK_TICKS)
	assert_int(game.view_of(P1).events_named(&"RoundStarted").size()).is_equal(2)


func test_the_mode_check_needs_a_setting_of_at_least_one_minute() -> void:
	var mode := FixtureWinModes.basic(2)
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	assert_array(Array(StartClock.new().check(mode))).is_equal(
		["StartClock has no minutes_setting"]
	)
	mode.find_setting(&"match_duration").min_value = 0
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("StartClock: setting match_duration goes down to 0 minutes")
	# A set of ids would read as 0 minutes: a clock that never ends.
	var a_set := FixtureWinModes.basic(2)
	var set_clock := a_set.find_transition(&"lobby", &"all_ready").actions.back() as StartClock
	set_clock.minutes_setting = &"banned_task_types"
	assert_array(Array(set_clock.check(a_set))).is_equal(
		["StartClock: setting banned_task_types is not a whole number"]
	)
	assert_str("\n".join(ModeCheck.run(a_set).errors)).contains(
		"StartClock: setting banned_task_types is not a whole number"
	)
	var unknown := FixtureWinModes.basic(2)
	var clock := unknown.find_transition(&"lobby", &"all_ready").actions.back() as StartClock
	clock.minutes_setting = &"length"
	assert_str("\n".join(ModeCheck.run(unknown).errors)).contains(
		"names setting length, which the mode does not declare"
	)


func test_a_forced_clock_gives_the_length_in_seconds_until_it_is_cleared() -> void:
	var mode := FixtureWinModes.basic(2)
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureDeliveryModes.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	# ForceClock (debug builds only): from the host's own player, in the lobby, for later rounds.
	FixtureModes.send(game, Intents.FORCE_CLOCK, P1, {"seconds": 40})
	assert_int(game.state.forced_clock_s).is_equal(40)
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.clock_ticks_left).is_equal(40 * Ticks.RATE)
	# It is not an intent: no Rejected, no event at all.
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	FixtureModes.send(game, Intents.FORCE_CLOCK, P1, {"seconds": -1})
	assert_int(game.state.forced_clock_s).is_equal(40)
	assert_str("\n".join(game.diagnostics)).contains("ForceClock: -1 seconds")
	FixtureModes.send(game, Intents.FORCE_CLOCK, P1, {"seconds": 0})
	assert_int(game.state.forced_clock_s).is_equal(0)
	# ResetMatch keeps it, like a forced role: session state.
	FixtureModes.send(game, Intents.FORCE_CLOCK, P1, {"seconds": 30})
	game.state.reset_match()
	assert_int(game.state.forced_clock_s).is_equal(30)
