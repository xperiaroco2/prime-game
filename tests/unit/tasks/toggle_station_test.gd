extends GdUnitTestSuite
## ToggleStation (#1295; ARCHITECTURE §9.4.2): an Interact at a world toggle's station and in sight
## flips the toggle; every station of the toggle (the kinds sharing its key and index) takes the
## new state, SwitchChanged tells each to everyone, and the host's world follows once
## (WorldQuery.set_toggle, through the recording wrapper Match asks while it records). Driven by
## FixtureToggles on a FixtureToggleWorld.

const P1 := FixtureToggles.P1
const P2 := FixtureToggles.P2


func test_an_interact_at_a_cover_opens_it_for_everyone_and_the_world() -> void:
	var world := FixtureToggleWorld.new()
	var game := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	assert_bool(game.recording).is_true()
	var covers := FixtureToggles.ids_of(game, &"cover")
	var since := game.view_of(P2).events_named(&"SwitchChanged").size()
	FixtureToggles.flip(game, P1, covers[0], FixtureToggles.COVERS[0])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_bool(game.state.stations[covers[0]].on).is_true()
	assert_bool(game.state.stations[covers[1]].on).is_false()
	for peer: int in [P1, P2]:
		var told := game.view_of(peer).events_named(&"SwitchChanged")
		assert_int(told.size()).is_equal(since + 1)
		var last := told[told.size() - 1] as SwitchChangedEvent
		assert_int(last.station).is_equal(covers[0])
		assert_bool(last.on).is_true()
	assert_str(world.calls[world.calls.size() - 1]).is_equal("cover 0 on")
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_second_interact_closes_it_again() -> void:
	var world := FixtureToggleWorld.new()
	var game := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	var cover := FixtureToggles.ids_of(game, &"cover")[1]
	FixtureToggles.flip(game, P1, cover, FixtureToggles.COVERS[1], 1)
	FixtureToggles.flip(game, P2, cover, FixtureToggles.COVERS[1], 1)
	assert_bool(game.state.stations[cover].on).is_false()
	assert_array(world.calls.slice(-2)).is_equal(["cover 1 on", "cover 1 off"])
	var told := game.view_of(P1).events_named(&"SwitchChanged")
	assert_bool((told[told.size() - 1] as SwitchChangedEvent).on).is_false()


func test_the_bookcase_and_the_wine_rack_are_one_toggle() -> void:
	var world := FixtureToggleWorld.new()
	var game := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	var book := FixtureToggles.ids_of(game, &"book")[0]
	var bottle := FixtureToggles.ids_of(game, &"bottle")[0]
	var since := game.view_of(P2).events_named(&"SwitchChanged").size()
	var calls := world.calls.size()
	FixtureToggles.flip(game, P1, book, FixtureToggles.BOOK)
	assert_bool(game.state.stations[book].on).is_true()
	assert_bool(game.state.stations[bottle].on).is_true()
	var told := game.view_of(P2).events_named(&"SwitchChanged").slice(since)
	(
		assert_array(told.map(func(e: SwitchChangedEvent) -> int: return e.station))
		. is_equal([book, bottle])
	)
	assert_array(world.calls.slice(calls)).is_equal(["bookcase 0 on"])
	for id: int in FixtureToggles.ids_of(game, &"cover"):
		assert_bool(game.state.stations[id].on).is_false()
	# From below: the wine rack closes what the book opened, both stations say off.
	FixtureToggles.flip(game, P2, bottle, FixtureToggles.BOTTLE)
	assert_bool(game.state.stations[book].on).is_false()
	assert_bool(game.state.stations[bottle].on).is_false()
	assert_str(world.calls[world.calls.size() - 1]).is_equal("bookcase 0 off")


func test_a_closed_part_blocks_sight_until_its_toggle_opens() -> void:
	# The bookcase's part stands between the wine rack and a player beside it.
	var wall := AABB(FixtureToggles.BOTTLE + Vector3(0.4, -1, -1), Vector3(0.2, 5, 2))
	var world := FixtureToggleWorld.new().add_part(&"bookcase", 0, wall)
	var game := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	var book := FixtureToggles.ids_of(game, &"book")[0]
	var bottle := FixtureToggles.ids_of(game, &"bottle")[0]
	FixtureItemModes.stand(game, P2, FixtureToggles.BOTTLE + Vector3(1, 0, 0))
	FixtureModes.send(game, Intents.INTERACT, P2, {"station": bottle}, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([StationInSight.BLOCKED])
	FixtureToggles.flip(game, P1, book, FixtureToggles.BOOK)
	FixtureItemModes.stand(game, P2, FixtureToggles.BOTTLE + Vector3(1, 0, 0))
	FixtureModes.send(game, Intents.INTERACT, P2, {"station": bottle}, 2)
	FixtureModes.run_ticks(game, 1)
	# Open, it hides nothing: the second Interact passes (no new rejection) and closes it again.
	assert_array(FixtureModes.rejections(game, P2)).is_equal([StationInSight.BLOCKED])
	assert_bool(game.state.stations[bottle].on).is_false()
	assert_str(world.calls[world.calls.size() - 1]).is_equal("bookcase 0 off")


func test_the_breaker_has_a_state_and_no_world_part() -> void:
	var world := FixtureToggleWorld.new()
	var game := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	var breaker := FixtureToggles.ids_of(game, &"breaker")[0]
	var calls := world.calls.size()
	FixtureToggles.flip(game, P1, breaker, FixtureToggles.BREAKER)
	assert_bool(game.state.stations[breaker].on).is_true()
	var told := game.view_of(P2).events_named(&"SwitchChanged")
	assert_int((told[told.size() - 1] as SwitchChangedEvent).station).is_equal(breaker)
	assert_int(world.calls.size()).is_equal(calls)


func test_out_of_reach_flips_nothing() -> void:
	var world := FixtureToggleWorld.new()
	var game := FixtureToggles.in_round(FixtureToggles.mode(), world, [P1, P2])
	var cover := FixtureToggles.ids_of(game, &"cover")[0]
	var calls := world.calls.size()
	FixtureItemModes.stand(game, P1, FixtureToggles.COVERS[0] + Vector3(5, 0, 0))
	FixtureModes.send(game, Intents.INTERACT, P1, {"station": cover}, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([AtStation.OUT_OF_REACH])
	assert_bool(game.state.stations[cover].on).is_false()
	assert_int(world.calls.size()).is_equal(calls)


func test_a_switch_changed_names_no_player() -> void:
	var event := SwitchChangedEvent.new(4, true)
	assert_array(event.to_dict().keys()).contains_exactly_in_any_order(["station", "on"])
