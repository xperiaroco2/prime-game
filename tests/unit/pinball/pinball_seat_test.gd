extends GdUnitTestSuite
## The pinball's seat (#1398; ARCHITECTURE §7.1.22, §9.4): an Interact at the machine seats one
## player and starts a game every peer sees (PinballState); a second player's is refused
## `unavailable`; the seat is given up by the seated player's Interact again, a walk away, a
## knockdown, a limp, a death, a leave and the row out of the lobby's phases (EndPinball), so no
## seat survives into a match; a cancelled countdown keeps it. Driven by FixturePinball.

const P1 := FixturePinball.P1
const P2 := FixturePinball.P2
const P3 := FixturePinball.P3


func test_an_interact_seats_the_player_and_every_peer_sees_the_same_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2, P3])
	assert_array(FixturePinball.states(game, P1)).is_empty()
	FixturePinball.interact(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(Pinball.seated(game.state)).is_equal(P1)
	var shown := FixturePinball.last(game, P1)
	assert_int(shown["player"]).is_equal(P1)
	assert_int(shown["game"]).is_equal(1)
	assert_int(shown["balls_left"]).is_equal(FixturePinball.BALLS)
	assert_int(shown["score"]).is_equal(0)
	assert_bool(shown["in_play"]).is_false()
	for peer: int in [P2, P3]:
		assert_array(FixturePinball.states(game, peer)).is_equal(FixturePinball.states(game, P1))


func test_a_second_player_is_refused_while_one_plays() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	var before := FixturePinball.states(game, P2).size()
	FixturePinball.interact(game, P2, 3)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])
	assert_int(Pinball.seated(game.state)).is_equal(P1)
	assert_int(FixturePinball.states(game, P2).size()).is_equal(before)


func test_the_seated_players_interact_again_gives_the_seat_up() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	FixturePinball.interact(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(Pinball.seated(game.state)).is_equal(-1)
	assert_int(FixturePinball.last(game, P2)["player"]).is_equal(-1)
	FixturePinball.interact(game, P2, 3)
	assert_int(Pinball.seated(game.state)).is_equal(P2)
	assert_int(FixturePinball.last(game, P1)["game"]).is_equal(2)


func test_an_interact_out_of_reach_takes_no_seat() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1])
	FixtureItemModes.stand(game, P1, FixturePinball.MACHINE + Vector3(4, 0, 0))
	FixturePinball.interact(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	assert_int(Pinball.seated(game.state)).is_equal(-1)


func test_walking_away_ends_the_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	FixtureItemModes.stand(game, P1, FixturePinball.MACHINE + Vector3(3, 0, 0))
	FixtureModes.run_ticks(game, 1)
	assert_int(Pinball.seated(game.state)).is_equal(-1)
	assert_int(FixturePinball.last(game, P2)["player"]).is_equal(-1)


func test_a_knockdown_a_death_and_a_limp_each_end_the_game() -> void:
	for how: String in ["downed", "dead", "limp"]:
		var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
		FixturePinball.interact(game, P1)
		var player := game.state.player(P1)
		match how:
			"downed":
				player.life = PlayerState.Life.DOWNED
			"dead":
				player.life = PlayerState.Life.DEAD
			_:
				player.limp = LimpState.new(game.ticked_through() + 100)
		FixtureModes.run_ticks(game, 1)
		assert_int(Pinball.seated(game.state)).override_failure_message(how).is_equal(-1)
		assert_int(FixturePinball.last(game, P2)["player"]).override_failure_message(how).is_equal(
			-1
		)


func test_a_leave_ends_the_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(Pinball.seated(game.state)).is_equal(-1)
	assert_int(FixturePinball.last(game, P2)["player"]).is_equal(-1)


func test_no_seat_survives_into_a_match() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	assert_int(Pinball.seated(game.state)).is_equal(-1)
	assert_int(FixturePinball.last(game, P2)["player"]).is_equal(-1)


func test_a_cancelled_countdown_keeps_the_seat() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureBaseMode.ready(game, P2, false, 5)
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(Pinball.seated(game.state)).is_equal(P1)


func test_a_joiner_is_told_the_running_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixturePinball.interact(game, P1)
	FixtureBaseMode.join(game, P3)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixturePinball.last(game, P3)["player"]).is_equal(P1)
	assert_dict(FixturePinball.last(game, P3)).is_equal(FixturePinball.last(game, P1))


func test_nothing_is_told_before_the_first_game() -> void:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2])
	FixtureBaseMode.join(game, P3)
	FixtureModes.run_ticks(game, 3)
	for peer: int in [P1, P2, P3]:
		assert_array(FixturePinball.states(game, peer)).is_empty()
