extends GdUnitTestSuite
## A leave outside Round (JoinRules.leave, ARCHITECTURE §3.5, #1388) while the hand and the belt
## are live in the lobby: the leaver's channels stop, PlayerLeft goes to everyone else, then what it
## carried drops to the floor below it (ItemPlaced, cause `leave`), as Round's life rule does; the
## leaver hears none of it. Driven by FixtureLobbyHands.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2
const P3 := FixtureLobbyHands.P3


func test_a_lobby_leaver_drops_its_hand_and_belt_after_player_left() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2])
	var belted := FixtureLobbyHands.give(game, P2, &"tool")
	FixtureItemModes.swap(game, P2)
	var held := FixtureLobbyHands.give(game, P2, &"tool")
	assert_int(game.state.player(P2).held_item).is_equal(held.id)
	var from := game.view_of(P1).events.size()
	var leaver_from := game.view_of(P2).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(FixtureBaseMode.names_since(game, P1, from).slice(0, 3)).is_equal(
		[&"PlayerLeft", &"ItemPlaced", &"ItemPlaced"]
	)
	var placed := game.view_of(P1).events_named(&"ItemPlaced")
	assert_int((placed[-2] as ItemPlacedEvent).item).is_equal(held.id)
	assert_int((placed[-1] as ItemPlacedEvent).item).is_equal(belted.id)
	assert_str(String((placed[-1] as ItemPlacedEvent).cause)).is_equal("leave")
	for item: ItemState in [held, belted]:
		assert_int(item.where).is_equal(ItemState.Where.GROUND)
		assert_int(item.holder).is_equal(0)
		assert_float(item.position.y).is_equal(0.0)
	assert_array(FixtureBaseMode.names_since(game, P2, leaver_from)).is_empty()
	assert_bool(game.state.players.has(P2)).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_countdown_leaver_drops_its_two_handed_item_and_the_countdown_is_cancelled() -> void:
	var game := FixtureLobbyHands.in_countdown(FixtureLobbyHands.mode(), [P1, P2, P3])
	var package := FixtureLobbyHands.give(game, P3, &"package")
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	assert_array(FixtureBaseMode.names_since(game, P1, from).slice(0, 2)).is_equal(
		[&"PlayerLeft", &"ItemPlaced"]
	)
	assert_bool(FixtureBaseMode.names_since(game, P1, from).has(&"CountdownCancelled")).is_true()
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_int(package.holder).is_equal(0)


func test_a_leaver_s_channel_stops() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2])
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD})
	FixtureModes.run_ticks(game, 3)
	assert_object(Channels.of_actor(game.state, P2)).is_not_null()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_object(Channels.of_actor(game.state, P2)).is_null()
	assert_array(FixtureModes.notes(game)).is_equal(["started 2", "stopped 2 after 3"])
	FixtureModes.run_ticks(game, 30)
	assert_array(FixtureModes.notes(game)).is_equal(["started 2", "stopped 2 after 3"])


func test_a_leaver_with_empty_hands_leaves_as_before() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2])
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(FixtureBaseMode.names_since(game, P1, from)).is_equal(
		[&"PlayerLeft", &"SettingsChanged"]
	)
