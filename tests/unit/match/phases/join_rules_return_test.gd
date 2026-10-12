extends GdUnitTestSuite
## A return (ARCHITECTURE §3.5; the returning-players ADR, Decision 2 and 3; the engineer's answers
## P1 (c), P3 (a), P4 (a), P13 (b) on #302): a player who left and joins again with the same return
## key gets its old number and the fallback name Player<number>, where joins are allowed; a key a
## present player holds, or an unusable one, joins as a new number with no binding.

const P1 := 1
const P2 := 2
const P3 := 3
const P7 := 7
const P8 := 8
const K1 := "11111111111111111111111111111111"
const K2 := "0123456789abcdef0123456789abcdef"
const K3 := "fedcba9876543210fedcba9876543210"


func test_a_returner_gets_its_old_number_and_no_join_is_counted() -> void:
	var game := _three()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P7, "", K2)
	assert_str(game.state.player(P7).name).is_equal("Player2")
	assert_int(game.state.player(P7).number).is_equal(2)
	assert_int(game.state.joins).is_equal(3)
	var joined := game.view_of(P1).events_named(&"PlayerJoined")
	assert_str((joined[joined.size() - 1] as PlayerJoinedEvent).player_name).is_equal("Player2")
	# The next joiner without a key is the fourth.
	FixtureBaseMode.join(game, P8)
	assert_str(game.state.player(P8).name).is_equal("Player4")


func test_a_returner_with_an_own_name_keeps_it_and_its_number() -> void:
	# P3 (a): a return restores the number only; the name is the Hello's, as for any joiner.
	var game := _three()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P7, "Bob", K2)
	assert_str(game.state.player(P7).name).is_equal("Bob")
	assert_int(game.state.player(P7).number).is_equal(2)
	assert_int(game.state.joins).is_equal(3)


func test_a_faster_return_is_a_new_number_and_the_key_keeps_its_binding() -> void:
	# A second window with P2's key, or a return before the host noticed the leave.
	var game := _three()
	FixtureBaseMode.join(game, P7, "", K2)
	assert_str(game.state.player(P7).name).is_equal("Player4")
	assert_int(game.state.numbers[K2]).is_equal(2)
	# Nobody is kicked out: P2 plays on, and no DisconnectPeer went out.
	assert_bool(game.state.is_present(P2)).is_true()
	assert_array(_disconnects(game)).is_empty()
	assert_array(FixtureModes.rejections(game, P7)).is_empty()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P8, "", K2)
	assert_str(game.state.player(P8).name).is_equal("Player2")
	assert_int(game.state.joins).is_equal(4)


func test_an_unusable_key_joins_with_no_binding_and_no_rejection() -> void:
	# P7 (a): anything but a String of 32 characters of 0-9a-f is no key.
	var game := FixtureBaseMode.started()
	var unusable: Array = ["zz", K2.left(31), K2 + "0", K2.to_upper(), StringName(K2), 42, ""]
	var peer := 10
	for key: Variant in unusable:
		FixtureBaseMode.join(game, peer, "", key)
		assert_bool(game.state.is_present(peer)).override_failure_message(str(key)).is_true()
		FixtureModes.send(game, Intents.PEER_LEFT, peer)
		peer += 1
	assert_dict(game.state.numbers).is_empty()
	assert_int(game.state.joins).is_equal(unusable.size())
	for each: int in range(10, peer):
		assert_array(FixtureModes.rejections(game, each)).is_empty()
	assert_array(_disconnects(game)).is_empty()
	# "zz" again, after its first holder left: still a new number.
	FixtureBaseMode.join(game, peer, "", "zz")
	assert_str(game.state.player(peer).name).is_equal("Player%d" % (unusable.size() + 1))


func test_a_return_in_the_countdown_cancels_it() -> void:
	var game := _three()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	for peer: int in [P1, P3]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureBaseMode.join(game, P7, "", K2)
	assert_str(game.state.player(P7).name).is_equal("Player2")
	var cancelled := game.view_of(P1).events_named(&"CountdownCancelled")
	assert_int(cancelled.size()).is_equal(1)
	assert_dict(cancelled[0].to_dict()).is_equal({"reason": CountdownCancelledEvent.JOIN})
	assert_str(game.phase_id()).is_equal("lobby")


func test_the_number_survives_end_to_lobby() -> void:
	var game := FixtureBaseMode.in_end([P1, P2, P3], 7, {P1: K1, P2: K2, P3: K3})
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_dict(game.state.numbers).is_equal({K1: 1, K2: 2, K3: 3})
	FixtureBaseMode.join(game, P7, "", K3)
	assert_str(game.state.player(P7).name).is_equal("Player3")
	assert_int(game.state.joins).is_equal(3)


func test_a_full_lobby_refuses_a_returner_and_holds_no_seat() -> void:
	var game := _three()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	# The leaver's seat goes to anyone: the lobby is full again.
	FixtureBaseMode.join(game, 4)
	FixtureBaseMode.join(game, 5)
	assert_int(game.state.peers().size()).is_equal(FixtureBaseMode.MAX_PLAYERS)
	FixtureBaseMode.join(game, P7, "", K2)
	assert_array(FixtureModes.rejections(game, P7)).is_equal([&"full"])
	assert_bool(game.state.players.has(P7)).is_false()
	assert_int(game.state.joins).is_equal(5)
	assert_dict(game.state.numbers).is_equal({K1: 1, K2: 2, K3: 3})
	# Once a seat frees up, the returner gets its number.
	FixtureModes.send(game, Intents.PEER_LEFT, 4)
	FixtureBaseMode.join(game, P8, "", K2)
	assert_str(game.state.player(P8).name).is_equal("Player2")


func test_a_newcomer_naming_itself_like_the_leaver_keeps_its_own_fallback() -> void:
	# P13 (b): while Player2 is away nobody may wear its name, and Player2 returns as Player2.
	var game := _three()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P7, "Player2")
	assert_str(game.state.player(P7).name).is_equal("Player4")
	FixtureBaseMode.join(game, P8, "", K2)
	assert_str(game.state.player(P8).name).is_equal("Player2")


func test_no_event_carries_the_key_and_the_command_log_keeps_it_as_sent() -> void:
	var game := _three()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P7, "", K2)
	FixtureBaseMode.join(game, P8, "", "zz")
	for peer: int in [P1, P2, P3, P7, P8]:
		for event: MatchEvent in game.view_of(peer).events:
			var text := var_to_str(event.to_dict())
			for key: String in [K1, K2, K3]:
				assert_bool(text.contains(key)).override_failure_message(text).is_false()
	for property: Dictionary in PlayerState.new(1, "").get_property_list():
		assert_str(str(property["name"])).is_not_equal("key")
	# P10 (a): the host's command log holds each key as its Hello carried it.
	var keys: Array = []
	for command: MatchCommand in game.command_log.commands:
		if command.kind == Intents.HELLO:
			keys.append(command.args.get("key"))
	assert_array(keys).is_equal([K1, K2, K3, K2, "zz"])


## P1, P2 and P3 joined the lobby with K1, K2 and K3: Player1 to Player3.
func _three() -> Match:
	var game := FixtureBaseMode.started()
	FixtureBaseMode.join(game, P1, "", K1)
	FixtureBaseMode.join(game, P2, "", K2)
	FixtureBaseMode.join(game, P3, "", K3)
	return game


## The DisconnectPeer directives emitted so far.
func _disconnects(game: Match) -> Array[String]:
	var found: Array[String] = []
	for directive: String in FixtureBaseMode.directives(game):
		if directive.begins_with("DisconnectPeer"):
			found.append(directive)
	return found
