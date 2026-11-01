extends GdUnitTestSuite
## The round's linger (ARCHITECTURE §3.4, #1502; GDD §3's End): a win decided in the tick the ship
## engine's last stage passes waits the Round's `linger_seconds` before its `won`, so everyone sees
## the finish. The clock and the win checks stop at the decision; nothing in the linger changes the
## result; End comes once, at the due tick. A seeded Match of FixtureEngineModes with the crew's
## win conditions, asserted on views and MatchState.

const PEERS: Array[int] = [1, 2, 3]
const FORCED: Dictionary[int, StringName] = {1: &"crew", 2: &"crew", 3: &"dissident"}
const LINGER_SECONDS := 1.0
const LINGER_TICKS := 20


func _mode(linger_seconds: float = LINGER_SECONDS) -> GameMode:
	var mode := FixtureEngineModes.basic(1)
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
	if linger_seconds > 0:
		mode.find_phase(&"round").settings[RoundPhase.LINGER_SECONDS] = linger_seconds
	return mode


func _round(mode: GameMode, seed_value: int = 7) -> Match:
	return FixtureEngineModes.in_round(mode, PEERS, {}, {}, seed_value, FORCED)


## Starts the engine and plays its one stage to the pass: the tick of the pass has run.
func _to_the_pass(game: Match) -> void:
	FixtureEngineModes.start(game, 1)
	FixtureEngineModes.play_to(game, 1, 2)
	assert_bool(FixtureEngineModes.state_of(game).done).is_true()


func _phases(game: Match) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(2).events_named(&"PhaseChanged"):
		found.append((event as PhaseChangedEvent).phase)
	return found


func test_the_win_is_decided_at_the_last_stage_and_the_round_lingers() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	var passed := game.ticked_through()
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.decided()).is_true()
	assert_str(game.state.verdict_side).is_equal("crew")
	assert_str(game.state.verdict_reason).is_equal("every_task_done")
	assert_int(game.state.finale_tick).is_equal(passed)
	assert_int(game.state.verdict_tick).is_equal(passed + LINGER_TICKS)
	assert_array(FixtureWinModes.ended(game, 2)).is_empty()
	assert_array(_phases(game)).is_equal([&"round"])


func test_end_comes_once_after_the_linger_with_the_decided_win() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	var due := game.state.verdict_tick
	FixtureWinModes.run_through(game, due - 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_array(FixtureWinModes.ended(game, 2)).is_empty()
	FixtureWinModes.run_through(game, due)
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.decided()).is_false()
	# End runs on: the won is reported once, and nothing of it is left to report again.
	FixtureWinModes.run_through(game, due + 100)
	assert_str(game.phase_id()).is_equal("end")
	var ended := FixtureEngineModes.dicts(game, 2, &"MatchEnded")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0]["side"]).is_equal("crew")
	assert_str(ended[0]["reason"]).is_equal("every_task_done")
	assert_array(_phases(game)).is_equal([&"round", &"end"])
	assert_int(game.row_error_count()).is_equal(0)
	assert_array(game.diagnostics).is_empty()


func test_the_clock_stops_at_the_decision() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	var left := game.state.clock_ticks_left
	var total := game.state.clock_ticks_total
	FixtureWinModes.run_through(game, game.state.verdict_tick - 1)
	assert_int(game.state.clock_ticks_left).is_equal(left)
	FixtureWinModes.run_through(game, game.ticked_through() + 1)
	# MatchEnded's time is the clock run up to the decision, not the linger.
	var ended := FixtureEngineModes.dicts(game, 2, &"MatchEnded")
	assert_int(ended[0]["numbers"]["time"]).is_equal(floori(float(total - left) / Ticks.RATE))


func test_a_clock_due_to_end_in_the_linger_does_not_end() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	game.state.clock_ticks_left = 3
	var due := game.state.verdict_tick
	FixtureWinModes.run_through(game, due)
	assert_bool(game.state.clock_ended).is_false()
	assert_int(game.state.clock_ticks_left).is_equal(3)
	assert_array(FixtureWinModes.ended(game, 2)).is_equal([&"crew"])


func test_nothing_in_the_linger_changes_the_result() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	var due := game.state.verdict_tick
	FixtureModes.run_ticks(game, 2)
	# Every crew member leaves: no_crew_present now holds, and the win checks no longer run.
	FixtureModes.send(game, Intents.PEER_LEFT, 1)
	FixtureModes.send(game, Intents.PEER_LEFT, 2)
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.verdict_tick).is_equal(due)
	FixtureWinModes.run_through(game, due - 1)
	assert_str(game.phase_id()).is_equal("round")
	FixtureWinModes.run_through(game, due)
	var ended := FixtureEngineModes.dicts(game, 3, &"MatchEnded")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0]["side"]).is_equal("crew")
	assert_str(ended[0]["reason"]).is_equal("every_task_done")


func test_the_round_runs_on_in_the_linger() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	var rejected := FixtureModes.rejections(game, 2).size()
	FixtureModes.run_ticks(game, 5)
	# An intent of the round still reaches its rules (nothing to use there), not a refusal of the
	# phase: the round's phase, rules and voice stay.
	FixtureModes.send(game, Intents.USE, 2, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.rejections(game, 2).slice(rejected)).is_equal([&"nothing_to_do"])
	assert_str(game.phase_id()).is_equal("round")


func test_no_linger_without_the_setting() -> void:
	var game := _round(_mode(0.0))
	_to_the_pass(game)
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.decided()).is_false()
	assert_array(FixtureWinModes.ended(game, 2)).is_equal([&"crew"])


func test_a_win_not_at_the_finale_ends_at_once() -> void:
	var game := _round(_mode())
	FixtureEngineModes.start(game, 1)
	game.state.clock_ticks_left = 2
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("end")
	var ended := FixtureEngineModes.dicts(game, 2, &"MatchEnded")
	assert_str(ended[0]["side"]).is_equal("dissidents")
	assert_str(ended[0]["reason"]).is_equal("time_up")


func test_the_same_seed_lingers_alike() -> void:
	var first := _round(_mode(), 11)
	var second := _round(_mode(), 11)
	for game: Match in [first, second]:
		_to_the_pass(game)
		FixtureWinModes.run_through(game, game.ticked_through() + LINGER_TICKS + 5)
	assert_array(FixtureModes.describe(first)).is_equal(FixtureModes.describe(second))


func test_a_reset_drops_the_decision() -> void:
	var game := _round(_mode())
	_to_the_pass(game)
	game.state.reset_match()
	assert_bool(game.state.decided()).is_false()
	assert_str(game.state.verdict_side).is_empty()
	assert_str(game.state.verdict_reason).is_empty()
	assert_int(game.state.finale_tick).is_equal(-1)


func test_the_round_checks_its_linger_setting() -> void:
	var round_phase := RoundPhase.new()
	var key := RoundPhase.LINGER_SECONDS
	assert_array(round_phase.check_settings({key: 4.0})).is_empty()
	assert_array(round_phase.check_settings({key: 0.0})).is_empty()
	assert_array(round_phase.check_settings({key: -1.0})).is_not_empty()
	assert_array(round_phase.check_settings({key: 31.0})).is_not_empty()
	assert_array(round_phase.check_settings({&"seconds": 3.0})).is_not_empty()


func test_only_the_ship_engine_has_a_finale() -> void:
	assert_bool(FixtureEngineModes.engine_type().has_finale()).is_true()
	assert_bool(FixtureTaskType.new().has_finale()).is_false()
	var spec := PhaseSpec.new()
	assert_float(RoundPhase.linger_seconds_of(spec)).is_equal(0.0)
	spec.settings[RoundPhase.LINGER_SECONDS] = 4.0
	assert_float(RoundPhase.linger_seconds_of(spec)).is_equal(4.0)


func test_a_win_after_the_finale_s_tick_ends_at_once() -> void:
	# No every_task_done (the crew wins only once no dissident is present): the engine's last stage
	# passes and decides nothing, and the round runs on.
	var mode := _mode()
	var crew_never := FixtureModes.win(&"crew", NoneAlive.of(&"dissidents"))
	mode.win_conditions = [crew_never, FixtureWinModes.no_crew_present(), FixtureWinModes.time_up()]
	var game := _round(mode)
	_to_the_pass(game)
	var passed := game.ticked_through()
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.decided()).is_false()
	assert_int(game.state.finale_tick).is_equal(passed)
	# Every crew member leaves later: that win was not decided in the finale's tick, so no linger.
	FixtureModes.run_ticks(game, 3)
	FixtureModes.send(game, Intents.PEER_LEFT, 1)
	FixtureModes.send(game, Intents.PEER_LEFT, 2)
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.decided()).is_false()
	var ended := FixtureEngineModes.dicts(game, 3, &"MatchEnded")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0]["side"]).is_equal("dissidents")
	assert_str(ended[0]["reason"]).is_equal("no_crew_present")


func test_every_task_done_without_a_finale_ends_at_once() -> void:
	var mode := FixtureWinModes.basic(2)
	mode.find_phase(&"round").settings[RoundPhase.LINGER_SECONDS] = LINGER_SECONDS
	var game := FixtureWinModes.in_round(mode, PEERS)
	var crew := FixtureDealModes.players_of(game, &"crew")
	FixtureWinModes.deliver(game, crew[0], 0)
	FixtureWinModes.deliver(game, crew[0], 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.decided()).is_false()
	assert_int(game.state.finale_tick).is_equal(-1)
	assert_array(FixtureWinModes.ended(game, crew[0])).is_equal([&"crew"])


func test_only_the_subtask_that_finishes_a_finale_task_marks_its_tick() -> void:
	var mode := FixtureWinModes.basic(2)
	mode.task_types = [FinaleDelivery.like(mode.task_types[0] as Delivery)]
	mode.find_phase(&"round").settings[RoundPhase.LINGER_SECONDS] = LINGER_SECONDS
	var game := FixtureWinModes.in_round(mode, PEERS)
	var crew := FixtureDealModes.players_of(game, &"crew")
	# The first package is a subtask done, but the task is not: no finale yet.
	FixtureWinModes.deliver(game, crew[0], 0)
	assert_int(game.state.finale_tick).is_equal(-1)
	assert_str(game.phase_id()).is_equal("round")
	# The last package finishes the task: its tick is the finale's, and the crew's win lingers.
	FixtureWinModes.deliver(game, crew[0], 1)
	# The delivery is an intent stamped for the next tick: that tick is the finale's.
	assert_int(game.state.finale_tick).is_equal(game.ticked_through() + 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.decided()).is_true()
	assert_str(game.state.verdict_reason).is_equal("every_task_done")


func test_leaving_the_round_another_way_drops_the_pending_win() -> void:
	var mode := _mode()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureReport.of(&"abort")]))
	mode.transitions.append(FixtureModes.row(&"round", &"abort", &"end", []))
	var game := _round(mode)
	_to_the_pass(game)
	var due := game.state.verdict_tick
	FixtureModes.run_ticks(game, 2)
	# A rule of the round reports another outcome in the linger: the round ends by that row.
	FixtureModes.send(game, Intents.USE, 2, {"facing": Vector3.FORWARD})
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.decided()).is_false()
	# The dropped win is never reported later: no MatchEnded, no row error, no second phase.
	FixtureWinModes.run_through(game, due + 5)
	assert_array(FixtureEngineModes.dicts(game, 2, &"MatchEnded")).is_empty()
	assert_int(game.row_error_count()).is_equal(0)
	assert_array(game.diagnostics).is_empty()
	assert_array(_phases(game)).is_equal([&"round", &"end"])


## A Delivery whose task has a finale, as the ship's engine has: the linger's trigger seen on a
## task of several subtasks, each done in its own tick.
class FinaleDelivery:
	extends Delivery

	static func like(other: Delivery) -> FinaleDelivery:
		var made := FinaleDelivery.new()
		made.id = other.id
		made.description = other.description
		made.package = other.package
		made.circle = other.circle
		made.subtasks_setting = other.subtasks_setting
		return made

	func has_finale() -> bool:
		return true
