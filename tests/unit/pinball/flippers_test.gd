extends GdUnitTestSuite
## Flippers (#1398; ARCHITECTURE §4.1, §7.1.22, §9.4): only the seated, standing player's count
## (PinballSeated, `not_seated` to anyone else and to the seated player while limp); the same held
## state again is applied with no event; a `left` or `right` that is missing or no bool is refused
## `bad_args`; the dead, and a phase that does not accept it, `not_accepted`. Flippers is no
## player's action, so no claim twin precedes it (Intents.PLAYER_ACTIONS). Driven by FixturePinball.

const P1 := FixturePinball.P1
const P2 := FixturePinball.P2
const P3 := FixturePinball.P3


func _seated() -> Match:
	var game := FixturePinball.at_machine(FixturePinball.mode(), [P1, P2, P3])
	FixturePinball.interact(game, P1)
	return game


func test_the_seated_players_flippers_reach_every_peer() -> void:
	var game := _seated()
	FixturePinball.flippers(game, P1, true, false, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	for peer: int in [P1, P2, P3]:
		var shown := FixturePinball.last(game, peer)
		assert_bool(shown["left"]).is_true()
		assert_bool(shown["right"]).is_false()
	FixturePinball.flippers(game, P1, false, true, 2)
	assert_bool(FixturePinball.last(game, P2)["left"]).is_false()
	assert_bool(FixturePinball.last(game, P2)["right"]).is_true()


func test_the_same_held_state_again_is_applied_silently() -> void:
	var game := _seated()
	FixturePinball.flippers(game, P1, true, true, 1)
	var told := FixturePinball.states(game, P2).size()
	FixturePinball.flippers(game, P1, true, true, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(FixturePinball.states(game, P2).size()).is_equal(told)


func test_anyone_but_the_seated_player_is_not_seated_and_changes_nothing() -> void:
	var game := _seated()
	var told := FixturePinball.states(game, P1)
	FixturePinball.flippers(game, P2, true, true, 4)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([Pinball.NOT_SEATED])
	assert_array(FixturePinball.states(game, P1)).is_equal(told)
	var game_free := FixturePinball.at_machine(FixturePinball.mode(), [P1])
	FixturePinball.flippers(game_free, P1, true, false, 1)
	assert_array(FixtureModes.rejections(game_free, P1)).is_equal([Pinball.NOT_SEATED])
	assert_array(FixturePinball.states(game_free, P1)).is_empty()


func test_garbage_is_bad_args() -> void:
	var game := _seated()
	var bad: Array[Dictionary] = [
		{},
		{"left": true},
		{"left": 1, "right": 0},
		{"left": "yes", "right": true},
		{"left": true, "right": Vector3.ONE},
	]
	var seq := 10
	for args: Dictionary in bad:
		FixtureModes.send(game, Intents.FLIPPERS, P1, args, seq)
		FixtureModes.run_ticks(game, 1)
		seq += 1
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"bad_args", &"bad_args", &"bad_args", &"bad_args", &"bad_args"]
	)
	assert_bool(FixturePinball.last(game, P2)["left"]).is_false()


func test_a_limp_seated_player_is_not_seated() -> void:
	var game := _seated()
	game.state.player(P1).limp = LimpState.new(game.ticked_through() + 100)
	FixtureModes.send(game, Intents.FLIPPERS, P1, {"left": true, "right": true}, 3)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([Pinball.NOT_SEATED])
	assert_bool(FixturePinball.last(game, P2)["left"]).is_false()


func test_the_dead_are_not_accepted() -> void:
	var game := _seated()
	game.state.player(P2).life = PlayerState.Life.DEAD
	FixturePinball.flippers(game, P2, true, true, 3)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([RejectReasons.NOT_ACCEPTED])


func test_loading_does_not_accept_flippers() -> void:
	var game := _seated()
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	FixturePinball.flippers(game, P1, true, true, 9)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([RejectReasons.NOT_ACCEPTED])


func test_flippers_is_an_intent_but_no_players_action() -> void:
	assert_bool(Intents.ALL.has(Intents.FLIPPERS)).is_true()
	assert_bool(Intents.PLAYER_ACTIONS.has(Intents.FLIPPERS)).is_false()
	assert_dict(Intents.FIELDS[Intents.FLIPPERS]).is_equal({"left": TYPE_BOOL, "right": TYPE_BOOL})
