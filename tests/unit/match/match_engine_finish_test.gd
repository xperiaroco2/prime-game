extends GdUnitTestSuite
## The ship engine's finish ends the round like any win (#1563, GDD §3's End; ARCHITECTURE §3.4):
## the win holds in the tick the engine's last stage passes, and its `won` and End follow in that
## tick, with no linger, as before #1544. A seeded Match of FixtureEngineModes with the crew's win
## conditions and the shipped base mode's Round settings, asserted on a peer's view and MatchState.

const BASE_MODE := "res://content/modes/base_mode.tres"
const PEERS: Array[int] = [1, 2, 3]
const FORCED: Dictionary[int, StringName] = {1: &"crew", 2: &"crew", 3: &"dissident"}


func _mode() -> GameMode:
	var mode := FixtureEngineModes.basic(1)
	# The shipped Round's settings: none of them may hold the round once the engine is done.
	var shipped := (load(BASE_MODE) as GameMode).find_phase(&"round")
	mode.find_phase(&"round").settings = shipped.settings.duplicate()
	mode.settings.append(FixtureModes.setting(&"match_duration", 1, 1, 60))
	mode.settings.append(FixtureModes.setting(&"dissidents", 1, 0, 9))
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(
		0, FixtureDealModes.deal_roles(mode.find_role(&"dissident"), mode.find_role(&"crew"))
	)
	deal.actions.append(FixtureWinModes.start_clock())
	mode.find_transition(&"round", Match.WON).actions.append(EndMatch.new())
	mode.win_conditions = [
		FixtureWinModes.every_task_done(),
		FixtureWinModes.no_crew_present(),
		FixtureWinModes.time_up(),
	]
	return mode


func _phases(game: Match) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(2).events_named(&"PhaseChanged"):
		found.append((event as PhaseChangedEvent).phase)
	return found


func test_the_last_stage_passing_ends_the_round_in_its_tick() -> void:
	var game := FixtureEngineModes.in_round(_mode(), PEERS, {}, {}, 7, FORCED)
	FixtureEngineModes.start(game, 1)
	var task_state := FixtureEngineModes.state_of(game)
	for i in 2000:
		if task_state.done:
			break
		# The tick before the pass: the round still runs, nothing ended.
		assert_str(game.phase_id()).is_equal("round")
		if task_state.problems.is_empty():
			FixtureModes.run_ticks(game, 1)
		else:
			FixtureEngineModes.fix_all(game, 1)
	assert_bool(task_state.done).is_true()
	# The tick that passed the last stage ended the round: End now, the win reported once.
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	assert_array(_phases(game)).is_equal([&"round", &"end"])
	var ended := FixtureEngineModes.dicts(game, 2, &"MatchEnded")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0]["side"]).is_equal("crew")
	assert_str(ended[0]["reason"]).is_equal("every_task_done")
	# The last ZoneProgress (the console's bar full) and End arrive together: nothing between.
	var tail := FixtureEngineModes.stream(
		game, 2, [&"ZoneProgress", &"MatchEnded", &"PhaseChanged"]
	)
	assert_array(tail.slice(tail.rfind(&"ZoneProgress"))).is_equal(
		[&"ZoneProgress", &"MatchEnded", &"PhaseChanged"] as Array[StringName]
	)
	# End runs on: nothing is reported again.
	FixtureWinModes.run_through(game, game.ticked_through() + 100)
	assert_int(FixtureEngineModes.dicts(game, 2, &"MatchEnded").size()).is_equal(1)
	assert_int(game.row_error_count()).is_equal(0)
	assert_array(game.diagnostics).is_empty()
