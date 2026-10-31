extends GdUnitTestSuite
## The lobby's best score (#1398; ARCHITECTURE §3.5, §7.1.22): a game whose score beats the best
## replaces it and its owner's name; a tie or a lower score keeps the older; a game that ends early
## (walked off) counts; the best and the name survive a match (ResetMatch, and every peer is told
## them again in the lobby) and the owner leaving; every peer sees the same; nothing is kept beyond
## the session. Driven by FixturePinball and StubTable.

const P1 := FixturePinball.P1
const P2 := FixturePinball.P2
const P3 := FixturePinball.P3


## `peer` sits, plays one ball hitting `hits` and gives the seat up.
func _play(game: Match, peer: int, hits: Array[StringName]) -> void:
	FixturePinball.interact(game, peer, game.ticked_through())
	StubTable.play(game, StubTable.ball(hits))
	if Pinball.seated(game.state) == peer:
		FixturePinball.interact(game, peer, game.ticked_through())


func _named(game: Match, peer: int, player_name: String) -> void:
	game.state.player(peer).name = player_name


func test_a_higher_score_replaces_the_best_and_a_tie_or_lower_keeps_it() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2, P3])
	_named(game, P1, "Ann")
	_named(game, P2, "Bob")
	_named(game, P3, "Cid")
	_play(game, P1, [&"bumper", &"bumper"])
	assert_int(FixturePinball.last(game, P3)["best"]).is_equal(2 * FixturePinball.BUMPER)
	assert_str(FixturePinball.last(game, P3)["best_name"]).is_equal("Ann")
	_play(game, P2, [&"bumper", &"bumper"])
	assert_str(FixturePinball.last(game, P3)["best_name"]).is_equal("Ann")
	_play(game, P3, [&"bumper"])
	assert_str(FixturePinball.last(game, P3)["best_name"]).is_equal("Ann")
	_play(game, P2, [&"target"])
	for peer: int in [P1, P2, P3]:
		var shown := FixturePinball.last(game, peer)
		assert_int(shown["best"]).is_equal(FixturePinball.TARGET)
		assert_str(shown["best_name"]).is_equal("Bob")
	assert_array(FixturePinball.states(game, P1)).is_equal(FixturePinball.states(game, P2))
	assert_array(FixturePinball.states(game, P1)).is_equal(FixturePinball.states(game, P3))


func test_a_game_walked_off_counts_for_the_best() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	_named(game, P1, "Ann")
	FixturePinball.interact(game, P1)
	StubTable.play(game, [&"launch", [&"hit", &"target"]])
	FixtureItemModes.stand(game, P1, FixturePinball.MACHINE + Vector3(4, 0, 0))
	FixtureModes.run_ticks(game, 1)
	assert_int(FixturePinball.last(game, P2)["best"]).is_equal(FixturePinball.TARGET)
	assert_str(FixturePinball.last(game, P2)["best_name"]).is_equal("Ann")


func test_the_owners_name_stays_after_the_owner_leaves() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	_named(game, P1, "Ann")
	FixturePinball.interact(game, P1)
	StubTable.play(game, [&"launch", [&"hit", &"target"]])
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixturePinball.last(game, P2)["best"]).is_equal(FixturePinball.TARGET)
	assert_str(FixturePinball.last(game, P2)["best_name"]).is_equal("Ann")
	FixtureBaseMode.join(game, P3)
	FixtureModes.run_ticks(game, 1)
	assert_str(FixturePinball.last(game, P3)["best_name"]).is_equal("Ann")


func test_the_best_survives_a_match_and_every_peer_is_told_it_again() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	_named(game, P1, "Ann")
	_play(game, P1, [&"target", &"bumper"])
	var best := FixturePinball.TARGET + FixturePinball.BUMPER
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	var told_before := FixturePinball.states(game, P2).size()
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(Pinball.session(game.state).best).is_equal(best)
	for peer: int in [P1, P2]:
		assert_int(FixturePinball.states(game, peer).size()).is_equal(told_before + 1)
		var shown := FixturePinball.last(game, peer)
		assert_int(shown["best"]).is_equal(best)
		assert_str(shown["best_name"]).is_equal("Ann")
		assert_int(shown["player"]).is_equal(-1)
		assert_int(shown["game"]).is_equal(0)
	FixturePinball.stand_at(game, P2)
	FixturePinball.interact(game, P2, 50)
	assert_int(FixturePinball.last(game, P1)["game"]).is_equal(2)


func test_reset_match_keeps_the_best_and_drops_the_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	StubTable.play(game, [&"launch", [&"hit", &"bumper"]])
	FixturePinball.interact(game, P1, 9)
	game.state.reset_match()
	assert_int(Pinball.session(game.state).best).is_equal(FixturePinball.BUMPER)
	assert_int(Pinball.game(game.state).score).is_equal(0)
	assert_int(Pinball.seated(game.state)).is_equal(-1)


func test_a_new_session_starts_with_no_best() -> void:
	var state := MatchState.new(7)
	assert_int(Pinball.session(state).best).is_equal(0)
	assert_str(Pinball.session(state).best_name).is_equal("")
	assert_bool(Pinball.started(state)).is_false()
