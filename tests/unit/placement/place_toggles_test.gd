extends GdUnitTestSuite
## PlaceToggles (#1295; ARCHITECTURE §9.4.3): at Loading -> Pregame every toggle part of the map
## goes back to off, then each toggle kind stands on every marker of its tag (off, `index` its
## marker's ordinal), StationPlaced to everyone; a kind with no marker places none and logs
## nothing; Stations.kinds_in lists the toggle kinds. Driven by FixtureToggles.

const P1 := FixtureToggles.P1
const P2 := FixtureToggles.P2


func test_the_deal_places_every_toggle_off_with_its_marker_index() -> void:
	var world := FixtureToggleWorld.new()
	var game := FixtureToggles.in_pregame(FixtureToggles.mode(), world, [P1, P2])
	assert_str(game.phase_id()).is_equal("pregame")
	var covers := FixtureToggles.ids_of(game, &"cover")
	assert_int(covers.size()).is_equal(2)
	for i in covers.size():
		var station := game.state.stations[covers[i]]
		assert_int(station.index).is_equal(i)
		assert_bool(station.on).is_false()
		assert_vector(station.position).is_equal(FixtureToggles.COVERS[i])
	for kind_id: StringName in [&"book", &"bottle", &"breaker"]:
		var ids := FixtureToggles.ids_of(game, kind_id)
		assert_int(ids.size()).is_equal(1)
		assert_int(game.state.stations[ids[0]].index).is_equal(0)
	var placed: Array[int] = []
	for event: MatchEvent in game.view_of(P2).events_named(&"StationPlaced"):
		placed.append((event as StationPlacedEvent).station)
	var ids: Array[int] = []
	ids.assign(game.state.stations.keys())
	ids.sort()
	assert_array(placed).is_equal(ids)
	assert_array(world.calls).is_equal(["reset"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_kind_with_no_marker_places_none_and_logs_nothing() -> void:
	var made := FixtureToggles.mode()
	for kind: StationKind in Stations.toggle_kinds(made):
		if kind.id == &"breaker":
			kind.spawn_tag = &"hatch"
	var game := FixtureToggles.in_pregame(made, FixtureToggleWorld.new(), [P1, P2])
	assert_array(FixtureToggles.ids_of(game, &"breaker")).is_empty()
	assert_int(FixtureToggles.ids_of(game, &"cover").size()).is_equal(2)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_next_match_on_one_world_starts_closed() -> void:
	var world := FixtureToggleWorld.new()
	var first := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	var cover := FixtureToggles.ids_of(first, &"cover")[0]
	FixtureToggles.flip(first, P1, cover, FixtureToggles.COVERS[0])
	assert_str(world.calls[world.calls.size() - 1]).is_equal("cover 0 on")
	var second := FixtureToggles.in_pregame(FixtureToggles.mode(), world, [P1, P2])
	assert_str(world.calls[world.calls.size() - 1]).is_equal("reset")
	for id: int in second.state.stations:
		assert_bool(second.state.stations[id].on).is_false()


func test_kinds_in_lists_the_toggle_kinds() -> void:
	var made := FixtureToggles.mode()
	var ids: Array[StringName] = []
	for kind: StationKind in Stations.kinds_in(made):
		ids.append(kind.id)
	assert_array(ids).contains([&"cover", &"book", &"bottle", &"breaker"])
	for kind: StationKind in Stations.toggle_kinds(made):
		assert_object(Stations.owner_of(made, kind)).is_null()


func test_the_toggle_mode_passes_the_mode_check() -> void:
	assert_array(Array(ModeCheck.run(FixtureToggles.mode()).errors)).is_empty()
