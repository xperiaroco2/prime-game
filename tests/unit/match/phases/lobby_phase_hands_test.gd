extends GdUnitTestSuite
## The hand, the belt and Interact in the Lobby and the Countdown (ARCHITECTURE §3.2, §9.4.5,
## #1388): no phase class handles them, so each goes to the mode's, the role's or the item's rule
## as in Round (Match._run_action), with the same refusals; none cancels the Countdown, which still
## ends on its tick. Throw, Raise and Pose stay refused (`not_accepted`). Driven by
## FixtureLobbyHands.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2


func test_the_lobby_takes_the_hand_and_the_belt() -> void:
	_hands_work(FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2]), "lobby")


func test_the_countdown_takes_them_and_is_not_cancelled() -> void:
	var game := FixtureLobbyHands.in_countdown(FixtureLobbyHands.mode(), [P1, P2])
	var end := game.current_phase().entered_tick + 100
	_hands_work(game, "countdown")
	_interact_refusals(game)
	assert_array(game.view_of(P1).events_named(&"CountdownCancelled")).is_empty()
	while game.ticked_through() < end - 1:
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")


func test_an_interact_on_a_placed_station_reaches_the_mode_s_rule() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2])
	var kind := StationKind.new()
	kind.id = &"bar"
	var station := game.state.add_station(kind, Vector3(1, 0, -1), Color.WHITE)
	FixtureModes.send(game, Intents.INTERACT, P1, {"station": station.id})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureModes.notes(game)).is_equal(["interacted"])


func test_an_interact_with_nothing_there_is_refused_in_the_lobby() -> void:
	_interact_refusals(FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2]))


func test_throw_raise_and_pose_stay_refused() -> void:
	for in_countdown: bool in [false, true]:
		var made := FixtureLobbyHands.mode()
		var game := (
			FixtureLobbyHands.in_countdown(made, [P1, P2])
			if in_countdown
			else FixtureLobbyHands.in_lobby(made, [P1, P2])
		)
		var phase := game.phase_id()
		FixtureLobbyHands.give(game, P1, &"tool")
		FixtureModes.send(game, Intents.THROW, P1, {"facing": Vector3.FORWARD}, 1)
		FixtureModes.send(game, Intents.RAISE, P1, {}, 2)
		FixtureModes.send(game, Intents.POSE, P1, {"pose": 1}, 3)
		assert_array(FixtureModes.rejections(game, P1)).is_equal(
			[&"not_accepted", &"not_accepted", &"not_accepted"]
		)
		assert_str(game.phase_id()).is_equal(phase)


## PickUp, Swap, Draw, Use and PutDown by P1, in `phase_id` throughout.
func _hands_work(game: Match, phase_id: String) -> void:
	var first := FixtureLobbyHands.give(game, P1, &"tool")
	assert_int(game.state.player(P1).held_item).is_equal(first.id)
	FixtureItemModes.swap(game, P1)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	assert_int(first.where).is_equal(ItemState.Where.BELT)
	FixtureItemModes.draw(game, P1, game.state.player(P1).places.find(first.id))
	assert_int(game.state.player(P1).held_item).is_equal(first.id)
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_bool(FixtureModes.notes(game).has("tool used")).is_true()
	FixtureItemModes.put_down(game, P1, Vector3.FORWARD)
	assert_int(first.where).is_equal(ItemState.Where.GROUND)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	for event_name: StringName in [&"ItemPickedUp", &"Swapped", &"ItemPlaced"]:
		assert_array(game.view_of(P2).events_named(event_name)).is_not_empty()
	assert_str(game.phase_id()).is_equal(phase_id)
	# An empty hand: PutDown and Swap are refused as in Round.
	FixtureItemModes.put_down(game, P1, Vector3.FORWARD, 1)
	FixtureItemModes.swap(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"empty_hand", &"nothing_to_swap"])


## Interact naming a station that is not there (nothing_to_do), and naming neither a station nor
## an item (bad_args), by P2.
func _interact_refusals(game: Match) -> void:
	FixtureModes.send(game, Intents.INTERACT, P2, {"station": 7}, 1)
	FixtureModes.send(game, Intents.INTERACT, P2, {}, 2)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"nothing_to_do", &"bad_args"])
