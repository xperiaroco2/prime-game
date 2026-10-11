extends GdUnitTestSuite
## Body colours and SetProfile (ARCHITECTURE §3.5, §4.1, #551; the engineer's answers on #73): a
## joiner takes the first free of the ten colours; SetProfile(name, colour) in the lobby, from a
## player, renames and recolours with the clash rule (a taken colour gives the first free one) and
## tells everyone (ProfileChanged); every other phase refuses it (`not_accepted`).

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4


func test_joiners_take_the_first_free_colours_in_join_order() -> void:
	var game := FixtureBaseMode.started()
	for peer: int in [P1, P2, P3, P4]:
		FixtureBaseMode.join(game, peer)
	for peer: int in [P1, P2, P3, P4]:
		assert_int(game.state.player(peer).colour).is_equal(peer - 1)


func test_welcome_and_player_joined_carry_the_colours() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.profile(game, P1, "Ann", 4)
	FixtureBaseMode.join(game, P2, "Bob")
	var welcome := game.view_of(P2).events_named(&"Welcome")[0] as WelcomeEvent
	(
		assert_array(welcome.roster)
		. is_equal(
			[
				{"peer": P1, "name": "Ann", "ready": false, "colour": 4},
				{"peer": P2, "name": "Bob", "ready": false, "colour": 0},
			]
		)
	)
	# P1 moved off colour 0, so it is the first free one for P2.
	var joined := game.view_of(P1).events_named(&"PlayerJoined")[-1] as PlayerJoinedEvent
	assert_int(joined.peer).is_equal(P2)
	assert_int(joined.colour).is_equal(0)
	assert_dict(joined.to_dict()).contains_key_value("colour", 0)


func test_a_leavers_colour_goes_to_the_next_joiner() -> void:
	var game := FixtureBaseMode.started()
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P4)
	assert_int(game.state.player(P4).colour).is_equal(1)


func test_a_profile_change_goes_to_everyone() -> void:
	var game := FixtureBaseMode.started()
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.join(game, peer)
	FixtureBaseMode.ready(game, P2)
	FixtureBaseMode.profile(game, P2, "  Dima ", 7, 4)
	var bob := game.state.player(P2)
	assert_str(bob.name).is_equal("Dima")
	assert_int(bob.colour).is_equal(7)
	# The ready flag is the player's own business: a profile leaves it.
	assert_bool(bob.ready).is_true()
	for peer: int in [P1, P2, P3]:
		var changed := game.view_of(peer).events_named(&"ProfileChanged")
		assert_int(changed.size()).is_equal(1)
		assert_dict((changed[0] as ProfileChangedEvent).to_dict()).is_equal(
			{"peer": P2, "name": "Dima", "colour": 7}
		)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_str(game.phase_id()).is_equal("lobby")


func test_a_taken_colour_gives_the_first_free_one() -> void:
	var game := FixtureBaseMode.started()
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.join(game, peer)
	# Colours 0, 1, 2; P1 moves to 5: 0 is free.
	FixtureBaseMode.profile(game, P1, "Player1", 5)
	# P3 asks for P2's colour and gets the first free one, 0, not the one it had.
	FixtureBaseMode.profile(game, P3, "Player3", 1)
	assert_int(game.state.player(P3).colour).is_equal(0)
	var changed := game.view_of(P2).events_named(&"ProfileChanged")[1] as ProfileChangedEvent
	assert_dict(changed.to_dict()).is_equal({"peer": P3, "name": "Player3", "colour": 0})
	# Its own colour is no clash: P2 asks for P3's 0, the others hold 5 and 0, so the first free
	# one is P2's own 1: unchanged.
	FixtureBaseMode.profile(game, P2, "Player2", 0)
	assert_int(game.state.player(P2).colour).is_equal(1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unchanged"])
	# P1 asks for P3's 0: the others hold 0 and 1, so the first free is 2.
	FixtureBaseMode.profile(game, P1, "Player1", 0)
	assert_int(game.state.player(P1).colour).is_equal(2)


func test_a_name_clash_gets_a_suffix_and_resending_it_is_unchanged() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Dima")
	FixtureBaseMode.join(game, P2, "Olena")
	FixtureBaseMode.profile(game, P2, "dima", 1)
	assert_str(game.state.player(P2).name).is_equal("dima 2")
	# Its own suffixed name is no clash with itself: not "dima 3".
	FixtureBaseMode.profile(game, P2, "dima 2", 1)
	FixtureBaseMode.profile(game, P2, "dima", 1)
	assert_str(game.state.player(P2).name).is_equal("dima 2")
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unchanged", &"unchanged"])
	assert_int(game.view_of(P1).events_named(&"ProfileChanged").size()).is_equal(1)


func test_a_name_with_nothing_usable_keeps_the_current_name_and_counts_no_join() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.join(game, P2)
	assert_int(game.state.joins).is_equal(2)
	for blank: String in ["", "   ", "\u0007"]:
		FixtureBaseMode.profile(game, P1, blank, 0)
	assert_str(game.state.player(P1).name).is_equal("Ann")
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"unchanged", &"unchanged", &"unchanged"]
	)
	# Only the colour changes: the name stays.
	FixtureBaseMode.profile(game, P1, "", 5)
	assert_str(game.state.player(P1).name).is_equal("Ann")
	assert_int(game.state.player(P1).colour).is_equal(5)
	# No rename used up a join number: the next nameless joiner is Player3.
	assert_int(game.state.joins).is_equal(2)
	FixtureBaseMode.join(game, P3)
	assert_str(game.state.player(P3).name).is_equal("Player3")


func test_the_same_profile_is_unchanged_with_no_event() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.profile(game, P1, "Ann", 0, 9)
	var rejected := game.view_of(P1).events_named(&"Rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_int((rejected[0] as RejectedEvent).seq).is_equal(9)
	assert_str((rejected[0] as RejectedEvent).reason).is_equal("unchanged")
	assert_array(game.view_of(P1).events_named(&"ProfileChanged")).is_empty()


func test_a_colour_outside_the_ten_is_out_of_bounds() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	for colour: int in [10, -1, 255, 1 << 40]:
		FixtureBaseMode.profile(game, P1, "Bob", colour)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"out_of_bounds", &"out_of_bounds", &"out_of_bounds", &"out_of_bounds"]
	)
	assert_str(game.state.player(P1).name).is_equal("Ann")
	assert_int(game.state.player(P1).colour).is_equal(0)


func test_a_name_that_is_not_text_or_a_colour_that_is_not_an_int_is_bad_args() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.profile(game, P1, "Bob", "3")
	FixtureBaseMode.profile(game, P1, "Bob", 3.0)
	FixtureBaseMode.profile(game, P1, "Bob", null)
	FixtureBaseMode.profile(game, P1, 7, 3)
	FixtureBaseMode.profile(game, P1, null, 3)
	FixtureModes.send(game, Intents.SET_PROFILE, P1, {"colour": 3})
	FixtureModes.send(game, Intents.SET_PROFILE, P1, {"name": "Bob"})
	var reasons := FixtureModes.rejections(game, P1)
	assert_int(reasons.size()).is_equal(7)
	for reason: StringName in reasons:
		assert_str(reason).is_equal("bad_args")
	assert_str(game.state.player(P1).name).is_equal("Ann")
	assert_int(game.state.player(P1).colour).is_equal(0)


func test_set_profile_is_accepted_in_the_lobby_only() -> void:
	# The base mode's accept row: Lobby, from a player. Every later phase refuses it.
	var games: Dictionary[String, Match] = {
		"countdown": FixtureBaseMode.in_countdown([P1, P2]),
		"loading": FixtureBaseMode.in_loading([P1, P2]),
		"pregame": FixtureBaseMode.in_pregame([P1, P2]),
		"round": FixtureBaseMode.in_round([P1, P2]),
		"end": FixtureBaseMode.in_end([P1, P2]),
	}
	for phase: String in games:
		var game := games[phase]
		assert_str(game.phase_id()).is_equal(phase)
		FixtureBaseMode.profile(game, P1, "Hacked", 5, 77)
		assert_array(FixtureModes.rejections(game, P1)).override_failure_message(phase).is_equal(
			[&"not_accepted"]
		)
		assert_str(game.state.player(P1).name).is_equal("Player1")
		assert_int(game.state.player(P1).colour).is_equal(0)
		assert_array(game.view_of(P2).events_named(&"ProfileChanged")).is_empty()


func test_a_newcomer_may_not_set_a_profile() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	FixtureBaseMode.profile(game, P2, "Bob", 3)
	assert_array(game.state.peers()).is_equal([P1])
	assert_array(game.view_of(P1).events_named(&"ProfileChanged")).is_empty()
	var refusal := game.emitted()[-1].event as RejectedEvent
	assert_str(refusal.reason).is_equal("not_accepted")


func test_colours_and_names_survive_the_way_back_to_the_lobby() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.join(game, P2, "Bob")
	FixtureBaseMode.profile(game, P2, "Bob", 6)
	FixtureBaseMode.ready(game, P1)
	FixtureBaseMode.ready(game, P2)
	FixtureModes.run_ticks(game, 101)
	FixtureBaseMode.load_ack(game, P1)
	FixtureBaseMode.load_ack(game, P2)
	FixtureBaseMode.through_pregame(game)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(game.state.player(P1).colour).is_equal(0)
	assert_int(game.state.player(P2).colour).is_equal(6)
	assert_str(game.state.player(P2).name).is_equal("Bob")
	# Back in the lobby, SetProfile is accepted again.
	FixtureBaseMode.profile(game, P2, "Bob", 2)
	assert_int(game.state.player(P2).colour).is_equal(2)
