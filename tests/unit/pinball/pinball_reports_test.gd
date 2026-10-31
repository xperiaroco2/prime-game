extends GdUnitTestSuite
## The table's reports (#1398, the table interface of ARCHITECTURE §7.1.22), sent by StubTable as
## server/'s table (#1399) would: the score and the balls follow BallLaunched, TargetHit and
## BallLost; the game ends after its last ball and frees the seat; a report of another game (a
## closed one after a reseat) or one that does not fit (a second launch, a hit or a loss with no
## ball on the table) is ignored with no event; an unknown target is a table bug (an error); no
## client can send one; a replay counts the same score with no physics. Driven by FixturePinball.

const P1 := FixturePinball.P1
const P2 := FixturePinball.P2


func _seated() -> Match:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	return game


func test_the_score_and_the_balls_follow_the_reports() -> void:
	var game := _seated()
	StubTable.play(game, [&"launch"])
	assert_bool(FixturePinball.last(game, P2)["in_play"]).is_true()
	StubTable.play(game, [[&"hit", &"bumper"], [&"hit", &"target"], [&"hit", &"bumper"]])
	var shown := FixturePinball.last(game, P2)
	assert_int(shown["score"]).is_equal(2 * FixturePinball.BUMPER + FixturePinball.TARGET)
	assert_int(shown["balls_left"]).is_equal(FixturePinball.BALLS)
	StubTable.play(game, [&"lost"])
	shown = FixturePinball.last(game, P2)
	assert_bool(shown["in_play"]).is_false()
	assert_int(shown["balls_left"]).is_equal(FixturePinball.BALLS - 1)
	assert_int(Pinball.seated(game.state)).is_equal(P1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_game_ends_after_its_last_ball() -> void:
	var game := _seated()
	for i in FixturePinball.BALLS:
		StubTable.play(game, StubTable.ball([&"bumper"]))
	var shown := FixturePinball.last(game, P2)
	assert_int(shown["player"]).is_equal(-1)
	assert_int(shown["balls_left"]).is_equal(0)
	assert_int(shown["score"]).is_equal(FixturePinball.BALLS * FixturePinball.BUMPER)
	assert_int(Pinball.seated(game.state)).is_equal(-1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_reports_that_do_not_fit_are_ignored_with_no_event() -> void:
	var game := _seated()
	var serial := Pinball.game(game.state).serial
	var told := FixturePinball.states(game, P2).size()
	StubTable.hit(game, serial, &"bumper")
	StubTable.lost(game, serial)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixturePinball.states(game, P2).size()).is_equal(told)
	StubTable.play(game, [&"launch"])
	told = FixturePinball.states(game, P2).size()
	StubTable.launch(game, serial)
	StubTable.hit(game, serial + 1, &"bumper")
	StubTable.lost(game, 0)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixturePinball.states(game, P2).size()).is_equal(told)
	assert_int(FixturePinball.last(game, P2)["score"]).is_equal(0)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_report_of_a_closed_game_is_not_credited_to_the_next() -> void:
	var game := _seated()
	var first := Pinball.game(game.state).serial
	StubTable.play(game, [&"launch"])
	FixturePinball.interact(game, P1, 2)
	FixturePinball.interact(game, P2, 3)
	assert_int(Pinball.seated(game.state)).is_equal(P2)
	StubTable.launch(game, Pinball.game(game.state).serial)
	FixtureModes.run_ticks(game, 1)
	StubTable.hit(game, first, &"target")
	StubTable.lost(game, first)
	FixtureModes.run_ticks(game, 1)
	var shown := FixturePinball.last(game, P1)
	assert_int(shown["player"]).is_equal(P2)
	assert_int(shown["score"]).is_equal(0)
	assert_int(shown["balls_left"]).is_equal(FixturePinball.BALLS)
	assert_bool(shown["in_play"]).is_true()


func test_no_reports_without_a_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	StubTable.launch(game, 0)
	StubTable.hit(game, 0, &"bumper")
	StubTable.lost(game, 0)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixturePinball.states(game, P2)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_an_unknown_target_is_a_table_bug() -> void:
	var game := _seated()
	StubTable.play(game, [&"launch", [&"hit", &"spinner"]])
	assert_int(FixturePinball.last(game, P2)["score"]).is_equal(0)
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("spinner")


func test_no_client_can_send_a_report() -> void:
	for kind: StringName in Intents.TABLE_REPORTS:
		assert_bool(Intents.ALL.has(kind)).override_failure_message(str(kind)).is_false()
		assert_bool(Intents.FIELDS[kind].has("game")).is_true()


func test_a_replay_counts_the_same_score() -> void:
	# Where they joined (in reach of the machine at MACHINE): a replay has no hand-set positions.
	var game := Match.new(FixturePinball.mode(), 7, FlatWorldQuery.new(), FixturePinball.layouts())
	game.start(0)
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	FixturePinball.interact(game, P1)
	assert_int(Pinball.seated(game.state)).is_equal(P1)
	StubTable.play(game, StubTable.ball([&"bumper", &"target"]))
	StubTable.play(game, [&"launch", [&"hit", &"target"]])
	var replayed := Match.replay(game.command_log, game.mode)
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))
	assert_int(Pinball.game(replayed.state).score).is_equal(
		FixturePinball.BUMPER + 2 * FixturePinball.TARGET
	)
