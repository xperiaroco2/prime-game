extends GdUnitTestSuite
## PlacePlayers (ARCHITECTURE §3.2, §9.4): distinct random markers of its tag in the level being
## entered, a new epoch per player, PlayersPlaced to everyone and a private Correction each.

const P1 := 1
const P2 := 2
const P3 := 3


func test_every_player_gets_a_distinct_marker_of_the_tag() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3])
	var markers := Array(FixtureModes.layouts()[FixtureModes.MAP].positions(&"round_player"))
	var seen: Array[Vector3] = []
	for peer: int in [P1, P2, P3]:
		var at := game.state.player(peer).position
		assert_array(markers).contains([at])
		assert_array(seen).not_contains([at])
		seen.append(at)
		assert_int(game.state.player(peer).epoch).is_equal(1)


func test_players_placed_and_corrections_say_where() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	var placed := game.view_of(P2).events_named(&"PlayersPlaced")[0] as PlayersPlacedEvent
	assert_array(placed.spots.keys()).is_equal([P1, P2])
	for peer: int in [P1, P2]:
		assert_vector(placed.spots[peer]).is_equal(game.state.player(peer).position)
		var correction := game.view_of(peer).events_named(&"Correction")[0] as CorrectionEvent
		assert_vector(correction.position).is_equal(game.state.player(peer).position)
		assert_vector(correction.velocity).is_equal(Vector3.ZERO)


func test_the_draw_depends_only_on_the_seed() -> void:
	var a := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3], 5)
	var b := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3], 5)
	for peer: int in [P1, P2, P3]:
		assert_vector(a.state.player(peer).position).is_equal(b.state.player(peer).position)
	var spots: Array[Array] = []
	for seed_value in range(1, 9):
		var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3], seed_value)
		spots.append([game.state.player(P1).position, game.state.player(P2).position])
	var distinct: Array[Array] = []
	for spot: Array in spots:
		if not distinct.has(spot):
			distinct.append(spot)
	assert_int(distinct.size()).is_greater(1)


func test_back_in_the_lobby_players_stand_on_lobby_markers() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.set_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	for peer: int in [P1, P2]:
		game.state.player(peer).ready = false
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	var lobby := Array(FixtureModes.layouts()[FixtureModes.LOBBY].positions(&"lobby_player"))
	for peer: int in [P1, P2]:
		assert_array(lobby).contains([game.state.player(peer).position])
		assert_int(game.state.player(peer).epoch).is_equal(2)


func test_too_few_markers_is_an_error_and_places_nobody() -> void:
	var game := Match.new(FixtureModes.basic(), 7, FlatWorldQuery.new(), FixtureModes.layouts(2))
	game.start(0)
	for peer: int in [P1, P2, P3]:
		FixtureModes.send(game, Intents.HELLO, peer)
	for peer: int in [P1, P2, P3]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.diagnostics[0]).contains("2 round_player marker(s) for 3 players")
	assert_int(game.state.player(P1).epoch).is_equal(0)


func test_it_demands_one_marker_per_player() -> void:
	var demands := Demands.new()
	FixtureModes.place(&"round_player").add_demands({}, 6, demands)
	assert_dict(demands.markers).is_equal({&"round_player": 6})
