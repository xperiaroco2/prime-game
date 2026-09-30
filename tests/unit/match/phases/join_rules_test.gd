extends GdUnitTestSuite
## Joining (ARCHITECTURE §3.2, §3.5, §4.1): Hello from a connected newcomer, once; the version and
## the room; the host's Player<n> names by join order, never reused; Welcome with public facts
## only, PlayerJoined and SettingsChanged; the joiner's lobby spot and epoch; leaves of newcomers
## and players.

const P1 := 1
const P2 := 2
const P3 := 3
const P5 := 5


func test_a_hello_joins_with_welcome_player_joined_and_settings_changed() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.join(game, P2, "  Bob ")
	assert_array(game.state.peers()).is_equal([P1, P2])
	assert_str(game.state.player(P2).name).is_equal("Player2")
	assert_array(game.view_of(P2).event_names()).is_equal(
		[&"Welcome", &"PlayerJoined", &"SettingsChanged"]
	)
	assert_array(FixtureBaseMode.names_since(game, P1, 3)).is_equal(
		[&"PlayerJoined", &"SettingsChanged"]
	)
	var joined := game.view_of(P1).events_named(&"PlayerJoined")[1] as PlayerJoinedEvent
	assert_int(joined.peer).is_equal(P2)
	assert_str(joined.player_name).is_equal("Player2")
	assert_vector(joined.spot).is_equal(game.state.player(P2).position)
	assert_array(game.state.newcomers.keys()).is_empty()


func test_welcome_holds_the_joiner_spot_epoch_and_the_public_lobby() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.ready(game, P1)
	# P1 alone and ready fits: the countdown starts; a join cancels it.
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	FixtureBaseMode.hello(game, P2, "Bob")
	var welcome := game.view_of(P2).events_named(&"Welcome")[0] as WelcomeEvent
	var bob := game.state.player(P2)
	assert_int(welcome.peer).is_equal(P2)
	assert_vector(welcome.spot).is_equal(bob.position)
	assert_int(welcome.epoch).is_equal(1)
	assert_int(bob.epoch).is_equal(1)
	assert_array(welcome.roster).is_equal(
		[
			{"peer": P1, "name": "Player1", "ready": true},
			{"peer": P2, "name": "Player2", "ready": false}
		]
	)
	assert_dict(welcome.settings).is_equal({&"knives": 2, &"circles": 1})
	assert_str(welcome.map).is_equal(FixtureBaseMode.MAP)
	assert_str(welcome.phase).is_equal("countdown")
	assert_dict(welcome.positions).is_equal({P1: game.state.player(P1).position})
	# Public facts only: no role, health, stamina or seed in it.
	var text := str(welcome.to_dict())
	for hidden: String in ["role", "health", "stamina", "seed"]:
		assert_str(text).not_contains(hidden)


func test_a_joiner_takes_the_first_free_lobby_marker() -> void:
	var game := FixtureBaseMode.started()
	var markers := FixtureBaseMode.layouts()[FixtureBaseMode.LOBBY].positions(&"lobby_player")
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	assert_vector(game.state.player(P1).position).is_equal(markers[0])
	assert_vector(game.state.player(P2).position).is_equal(markers[1])
	# P1 walks away from its marker: the next joiner takes it.
	game.state.player(P1).position = Vector3(50, 0, 50)
	FixtureBaseMode.join(game, P3)
	assert_vector(game.state.player(P3).position).is_equal(markers[0])


func test_a_hello_without_a_connection_or_a_second_hello_is_not_accepted() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.hello(game, P1, "Ann", JoinRules.PROTOCOL_VERSION, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_object(game.state.player(P1)).is_null()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.hello(game, P1, "again", JoinRules.PROTOCOL_VERSION, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted", &"not_accepted"])
	assert_str(game.state.player(P1).name).is_equal("Player1")


func test_another_version_is_rejected_and_disconnected() -> void:
	var game := FixtureBaseMode.started()
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	FixtureBaseMode.hello(game, P2, "Bob", JoinRules.PROTOCOL_VERSION + 1, 3)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"wrong_version"])
	assert_array(FixtureBaseMode.directives(game)).is_equal(["AllowJoins", "DisconnectPeer 2"])
	assert_object(game.state.player(P2)).is_null()
	assert_bool(game.state.newcomers.has(P2)).is_false()
	FixtureModes.send(game, Intents.PEER_CONNECTED, P3)
	FixtureModes.send(game, Intents.HELLO, P3, {"name": "Cy", "version": "1"})
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"wrong_version"])
	# Their late PeerLeft changes nothing.
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(game.diagnostics).is_empty()


func test_the_host_names_players_by_join_order() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P3)
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	assert_str(game.state.player(P3).name).is_equal("Player1")
	assert_str(game.state.player(P1).name).is_equal("Player2")
	assert_str(game.state.player(P2).name).is_equal("Player3")


func test_a_leave_does_not_free_a_number() -> void:
	var game := FixtureBaseMode.started()
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P5)
	assert_str(game.state.player(P5).name).is_equal("Player4")
	# The same peer id coming back is a new joiner too.
	FixtureBaseMode.join(game, P2)
	assert_str(game.state.player(P2).name).is_equal("Player5")


func test_a_rejected_hello_takes_no_number() -> void:
	var game := FixtureBaseMode.started()
	# not_accepted: a Hello without a connection.
	FixtureBaseMode.hello(game, P5, "Eve")
	assert_array(FixtureModes.rejections(game, P5)).is_equal([&"not_accepted"])
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	FixtureBaseMode.hello(game, P2, "Bob", JoinRules.PROTOCOL_VERSION + 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"wrong_version"])
	FixtureBaseMode.join(game, P3)
	assert_str(game.state.player(P3).name).is_equal("Player1")
	# not_accepted: a second Hello from a player.
	FixtureBaseMode.hello(game, P3, "again")
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"not_accepted"])
	for peer: int in range(10, 10 + FixtureBaseMode.MAX_PLAYERS - 1):
		FixtureBaseMode.join(game, peer)
	assert_int(game.state.joins).is_equal(FixtureBaseMode.MAX_PLAYERS)
	# full: the roster has no room.
	FixtureModes.send(game, Intents.PEER_CONNECTED, 9)
	FixtureBaseMode.hello(game, 9, "late")
	assert_array(FixtureModes.rejections(game, 9)).is_equal([&"full"])
	assert_int(game.state.joins).is_equal(FixtureBaseMode.MAX_PLAYERS)
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	FixtureBaseMode.join(game, 20)
	assert_str(game.state.player(20).name).is_equal("Player%d" % (FixtureBaseMode.MAX_PLAYERS + 1))


func test_the_numbering_survives_end_to_lobby() -> void:
	var game := FixtureBaseMode.in_end([P1, P2, P3])
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(game.state.joins).is_equal(3)
	assert_str(game.state.player(P1).name).is_equal("Player1")
	assert_str(game.state.player(P2).name).is_equal("Player2")
	FixtureBaseMode.join(game, P5)
	assert_str(game.state.player(P5).name).is_equal("Player4")


func test_welcome_and_player_joined_carry_the_hosts_name_never_the_clients() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "Ann")
	FixtureBaseMode.join(game, P2, "Bob")
	var welcome := game.view_of(P2).events_named(&"Welcome")[0] as WelcomeEvent
	(
		assert_array(welcome.roster.map(func(entry: Dictionary) -> Variant: return entry["name"]))
		. is_equal(["Player1", "Player2"])
	)
	for peer: int in [P1, P2]:
		var joined := game.view_of(peer).events_named(&"PlayerJoined")
		assert_str((joined[-1] as PlayerJoinedEvent).player_name).is_equal("Player2")
	var names_seen := ""
	for peer: int in [P1, P2]:
		for event: MatchEvent in game.view_of(peer).events:
			names_seen += str(event.to_dict())
	assert_str(names_seen).not_contains("Ann")
	assert_str(names_seen).not_contains("Bob")


func test_a_clients_odd_name_is_ignored() -> void:
	var game := FixtureBaseMode.started()
	var odd: Array[Variant] = ["", "   ", "x".repeat(10000), "a\nb\tc\u0007\u009f", 7, null]
	var peer := 10
	for odd_name: Variant in odd:
		FixtureModes.send(game, Intents.PEER_CONNECTED, peer)
		FixtureModes.send(
			game, Intents.HELLO, peer, {"name": odd_name, "version": JoinRules.PROTOCOL_VERSION}
		)
		assert_array(FixtureModes.rejections(game, peer)).is_empty()
		assert_str(game.state.player(peer).name).is_equal("Player%d" % (peer - 9))
		# Leave again: the mode's roster holds at most 4 players.
		FixtureModes.send(game, Intents.PEER_LEFT, peer)
		peer += 1
	# A Hello without a name joins too.
	FixtureModes.send(game, Intents.PEER_CONNECTED, peer)
	FixtureModes.send(game, Intents.HELLO, peer, {"version": JoinRules.PROTOCOL_VERSION})
	assert_str(game.state.player(peer).name).is_equal("Player%d" % (odd.size() + 1))


func test_a_hello_into_a_full_roster_is_rejected_and_disconnected() -> void:
	var game := FixtureBaseMode.started()
	for peer: int in range(1, FixtureBaseMode.MAX_PLAYERS + 1):
		FixtureBaseMode.join(game, peer)
	FixtureModes.send(game, Intents.PEER_CONNECTED, 9)
	FixtureBaseMode.hello(game, 9, "late")
	assert_array(FixtureModes.rejections(game, 9)).is_equal([&"full"])
	assert_array(FixtureBaseMode.directives(game)).contains(["DisconnectPeer 9"])
	assert_int(game.state.peers().size()).is_equal(FixtureBaseMode.MAX_PLAYERS)
	# The rejected newcomer received nothing else.
	assert_array(game.view_of(9).event_names()).is_equal([&"Rejected"])


func test_a_newcomer_receives_nothing_but_its_rejected() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureModes.send(game, Intents.PEER_CONNECTED, P5)
	FixtureModes.send(game, Intents.SET_READY, P5, {"ready": true})
	assert_array(game.view_of(P5).event_names()).is_equal([&"Rejected"])


func test_a_newcomer_leaving_is_forgotten_silently() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	var emitted_before := game.emitted().size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_int(game.emitted().size()).is_equal(emitted_before)
	assert_bool(game.state.newcomers.has(P2)).is_false()
	FixtureBaseMode.hello(game, P2, "Bob")
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])


func test_a_player_leaving_the_lobby_leaves_the_roster() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(game.state.peers()).is_equal([P1])
	assert_array(FixtureBaseMode.names_since(game, P1, from)).is_equal(
		[&"PlayerLeft", &"SettingsChanged"]
	)
	var left := game.view_of(P1).events_named(&"PlayerLeft")[0] as PlayerLeftEvent
	assert_int(left.peer).is_equal(P2)
	var changed := game.view_of(P1).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
	assert_int(changed.players).is_equal(1)


func test_a_peer_connected_twice_as_a_player_is_an_error() -> void:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1)
	FixtureModes.send(game, Intents.PEER_CONNECTED, P1)
	assert_str(game.diagnostics[0]).contains("PeerConnected for peer 1, which is a player")
