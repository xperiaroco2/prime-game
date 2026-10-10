extends GdUnitTestSuite
## ResetMatch (ARCHITECTURE §3.2, §9.1, §9.4): on `End -> Lobby` it resets the match state from the
## roster and un-readies everyone (ReadyChanged per player), and it runs before PlacePlayers, so
## nobody is placed, and announced to everyone, while still downed.

const P1 := 1
const P2 := 2
const P3 := 3


func test_back_resets_the_match_before_placing_players() -> void:
	var game := FixtureBaseMode.in_end([P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.bodies[P2] = Vector3(1, 0, 1)
	game.state.player(P3).role = &"crew"
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	(
		assert_array(FixtureBaseMode.names_since(game, P1, from))
		. is_equal(
			[
				&"ReadyChanged",
				&"ReadyChanged",
				&"ReadyChanged",
				&"SettingsChanged",
				&"PlayersPlaced",
				&"Correction",
				&"PhaseChanged",
			]
		)
	)
	var peers: Array[int] = []
	for event: MatchEvent in game.view_of(P1).events.slice(from, from + 3):
		var changed := event as ReadyChangedEvent
		assert_bool(changed.ready).is_false()
		peers.append(changed.peer)
	assert_array(peers).is_equal([P1, P2, P3])
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	assert_dict(game.state.bodies).is_empty()
	assert_str(game.state.player(P3).role).is_equal("")
	var lobby := Array(FixtureBaseMode.layouts()[FixtureBaseMode.LOBBY].positions(&"lobby_player"))
	var placed := game.view_of(P2).events_named(&"PlayersPlaced")[-1] as PlayersPlacedEvent
	for peer: int in [P1, P2, P3]:
		assert_array(lobby).contains([placed.spots[peer]])


func test_placing_before_the_reset_would_place_a_downed_player() -> void:
	# Why the order matters: with the actions swapped, PlacePlayers places and announces P2 while
	# it is still downed, and the reset's ReadyChanged only follows the placement.
	var mode := FixtureBaseMode.mode()
	var probe := FixtureLifeProbe.new()
	var row := mode.find_transition(&"end", EndPhase.BACK)
	row.actions = [FixtureModes.place(&"lobby_player"), probe, ResetMatch.new()]
	var game := _in_end(mode)
	game.state.player(P2).life = PlayerState.Life.DOWNED
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_array(probe.downed_seen).is_equal([P2])
	var placed := game.view_of(P1).events_named(&"PlayersPlaced")[-1] as PlayersPlacedEvent
	assert_bool(placed.spots.has(P2)).is_true()
	var names := FixtureBaseMode.names_since(game, P1, from)
	assert_int(names.find(&"PlayersPlaced")).is_less(names.find(&"ReadyChanged"))
	# In the base mode's order, nobody is downed any more when the players are placed.
	var in_order := FixtureBaseMode.mode()
	var after_reset := FixtureLifeProbe.new()
	var ordered := in_order.find_transition(&"end", EndPhase.BACK)
	ordered.actions = [ResetMatch.new(), after_reset, FixtureModes.place(&"lobby_player")]
	var second := _in_end(in_order)
	second.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureModes.send(second, Intents.RETURN_TO_LOBBY, P1)
	assert_array(after_reset.downed_seen).is_empty()


## #737: a player who left mid-round is dropped from the roster on `End -> Lobby`, so the lobby
## is short again in a mode that needs more players. Every peer back in the lobby gets the host's
## shortfalls afresh, as a leave in the lobby sends them, not the empty ones of before the
## countdown.
func test_back_resends_the_shortfalls_to_everyone() -> void:
	var mode := FixtureBaseMode.mode()
	mode.min_players = 3
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	var peers: Array[int] = [P1, P2, P3]
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	var before := game.view_of(P1).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
	assert_array(before.shortfalls).is_empty()
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	var left_from := game.view_of(P3).events.size()
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	for peer: int in [P1, P2]:
		var changed := (
			game.view_of(peer).events_named(&"SettingsChanged")[-1] as SettingsChangedEvent
		)
		assert_int(changed.players).is_equal(2)
		assert_array(HostText.to_dicts(changed.shortfalls)).is_equal(
			[
				{
					"id": &"players_few",
					"ids": PackedStringArray(),
					"numbers": {&"count": 1, &"min": 3, &"max": FixtureBaseMode.MAX_PLAYERS}
				}
			]
		)
	# The player who left is no longer an audience: nothing more reaches it.
	assert_int(game.view_of(P3).events.size()).is_equal(left_from)


func test_the_next_match_has_the_next_id() -> void:
	var game := FixtureBaseMode.in_end([P1, P2])
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	FixtureBaseMode.ready(game, P1)
	FixtureBaseMode.ready(game, P2)
	FixtureModes.run_ticks(game, 101)
	assert_str(game.phase_id()).is_equal("loading")
	var load_event := game.view_of(P1).events_named(&"LoadMatch")[-1] as LoadMatchEvent
	assert_int(load_event.match_id).is_equal(1)
	# A late ack of the first match is dropped.
	FixtureBaseMode.load_ack(game, P2, 0)
	assert_int(game.view_of(P1).events_named(&"PlayerLoaded").size()).is_equal(2)
	FixtureBaseMode.load_ack(game, P2)
	assert_int(game.view_of(P1).events_named(&"PlayerLoaded").size()).is_equal(3)


func _in_end(mode: GameMode) -> Match:
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	return game
