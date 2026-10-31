extends GdUnitTestSuite
## The ball's place (#1399, ARCHITECTURE §7.1.22): BallMoved, the table's fourth report, places the
## live game's ball for the snapshots (Pinball.shown_ball) and emits nothing; every viewer's
## snapshot and view_of hold the same `ball`, and none holds one before a launch, after a loss, after
## the game's end, or from a report of another game. Driven by FixturePinball and StubTable.

const P1 := FixturePinball.P1
const P2 := FixturePinball.P2
const PLACE := Vector3(0.25, 0.0, -0.5)


func _seated() -> Match:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	return game


func _serial(game: Match) -> int:
	return Pinball.game(game.state).serial


func _move(game: Match, serial: int, position: Vector3) -> void:
	StubTable.moved(game, serial, position)
	FixtureModes.run_ticks(game, 1)


func test_a_moved_ball_is_in_every_snapshot_and_emits_nothing() -> void:
	var game := _seated()
	StubTable.play(game, [&"launch"])
	var told := FixturePinball.states(game, P2).size()
	_move(game, _serial(game), PLACE)
	for peer: int in [P1, P2]:
		assert_that(game.snapshot_for(peer).get("ball")).is_equal(PLACE)
	var at_tick := game.ticked_through()
	assert_that(game.view_of(P2).snapshots[at_tick].get("ball")).is_equal(PLACE)
	assert_int(FixturePinball.states(game, P2).size()).is_equal(told)
	assert_array(Array(game.diagnostics)).is_empty()


func test_no_ball_before_a_launch_or_after_a_loss() -> void:
	var game := _seated()
	_move(game, _serial(game), PLACE)
	assert_bool(game.snapshot_for(P2).has("ball")).is_false()
	StubTable.play(game, [&"launch"])
	assert_bool(game.snapshot_for(P2).has("ball")).override_failure_message("unplaced").is_false()
	_move(game, _serial(game), PLACE)
	StubTable.play(game, [&"lost"])
	assert_bool(game.snapshot_for(P2).has("ball")).is_false()
	assert_bool(game.view_of(P2).snapshots[game.ticked_through()].has("ball")).is_false()
	StubTable.play(game, [&"launch"])
	assert_bool(game.snapshot_for(P2).has("ball")).override_failure_message("relaunch").is_false()


func test_no_ball_after_the_game_ends() -> void:
	var game := _seated()
	StubTable.play(game, [&"launch"])
	_move(game, _serial(game), PLACE)
	FixturePinball.interact(game, P1)
	assert_int(Pinball.seated(game.state)).is_equal(-1)
	assert_bool(game.snapshot_for(P2).has("ball")).is_false()


func test_a_report_of_another_game_or_a_bad_place_is_ignored() -> void:
	var game := _seated()
	StubTable.play(game, [&"launch"])
	_move(game, _serial(game) + 1, PLACE)
	assert_bool(game.snapshot_for(P2).has("ball")).is_false()
	_move(game, _serial(game), Vector3(INF, 0.0, 0.0))
	assert_bool(game.snapshot_for(P2).has("ball")).is_false()
	_move(game, _serial(game), PLACE)
	_move(game, _serial(game), Vector3(NAN, 0.0, 0.0))
	assert_that(game.snapshot_for(P2).get("ball")).is_equal(PLACE)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_replay_places_the_ball_where_the_match_did() -> void:
	var game := _seated()
	StubTable.play(game, [&"launch"])
	_move(game, _serial(game), PLACE)
	var replayed := Match.replay(game.command_log, game.mode)
	assert_that(replayed.snapshot_for(P2).get("ball")).is_equal(PLACE)
