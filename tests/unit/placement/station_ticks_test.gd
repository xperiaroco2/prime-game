extends GdUnitTestSuite
## StationTicks, ClearStations and the joiner's replay (#1390; ARCHITECTURE §3.2, §9.4.2, §9.4.5):
## the lobby's tap stands from the first Lobby tick (StationPlaced to everyone, once), stays through
## a cancelled countdown, goes at `countdown_done` (the next station is numbered 1 again) and is
## never placed in Loading; a peer who joins in the Lobby or the Countdown is told the tap; a lobby
## level without its marker refuses the mode (LayoutCheck). Driven by FixtureBar.

const P1 := FixtureBar.P1
const P2 := FixtureBar.P2
const P3 := FixtureBar.P3


func test_the_first_lobby_tick_places_the_tap_once() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	FixtureModes.run_ticks(game, 5)
	assert_int(FixtureBar.tap_id(game)).is_equal(1)
	var station := game.state.stations[1]
	assert_vector(station.position).is_equal(FixtureBar.TAP)
	var placed := game.view_of(P1).events_named(&"StationPlaced")
	assert_array(placed).has_size(1)
	assert_str(String((placed[0] as StationPlacedEvent).kind)).is_equal("tap")
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_cancelled_countdown_keeps_the_tap_and_countdown_done_clears_it() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureBaseMode.ready(game, P2, false)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(FixtureBar.tap_id(game)).is_equal(1)
	FixtureBaseMode.ready(game, P2)
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	assert_bool(game.state.stations.is_empty()).is_true()
	FixtureModes.run_ticks(game, 5)
	assert_bool(game.state.stations.is_empty()).is_true()
	assert_int(game.state.add_station(StationKind.new(), Vector3.ZERO, Color.WHITE).id).is_equal(1)
	assert_int(game.view_of(P1).events_named(&"StationPlaced").size()).is_equal(1)


func test_an_interact_on_the_cleared_tap_is_nothing_to_do() -> void:
	var made := FixtureBar.mode()
	# The round takes Interact here, so the intent reaches the rules (not `not_accepted`).
	made.find_phase(&"round").accepts.append(
		AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING)
	)
	var game := FixtureBar.at_bar(made, [P1, P2])
	var tap := FixtureBar.tap_id(game)
	assert_int(tap).is_equal(1)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	FixtureModes.send(game, Intents.INTERACT, P1, {"station": tap}, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_object(Items.held_by(game.state, P1)).is_null()
	assert_bool(game.state.stations.has(1) and game.state.stations[1].kind.id == &"tap").is_false()


func test_a_joiner_in_the_lobby_is_told_the_tap() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	FixtureBaseMode.join(game, P3)
	var placed := game.view_of(P3).events_named(&"StationPlaced")
	assert_array(placed).has_size(1)
	assert_int((placed[0] as StationPlacedEvent).station).is_equal(1)
	assert_vector((placed[0] as StationPlacedEvent).position).is_equal(FixtureBar.TAP)


func test_a_joiner_in_the_countdown_is_told_the_tap() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureBaseMode.join(game, P3)
	assert_array(game.view_of(P3).events_named(&"StationPlaced")).has_size(1)
	assert_int(FixtureBar.tap_id(game)).is_equal(1)


func test_a_lobby_without_the_tap_marker_is_refused() -> void:
	var game := Match.new(FixtureBar.mode(), 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	var about_tap := Array(game.refusals).filter(
		func(line: Variant) -> bool: return str(line).contains("tap")
	)
	assert_array(about_tap).is_not_empty()
	var placed := Match.new(FixtureBar.mode(), 7, FlatWorldQuery.new(), FixtureBar.layouts())
	assert_array(Array(placed.refusals)).is_empty()
