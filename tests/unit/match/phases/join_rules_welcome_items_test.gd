extends GdUnitTestSuite
## Welcome's item rows (ARCHITECTURE §3.5, §4.2, #1404): a player who joins in the Lobby or the
## Countdown learns every item already in the hall, as the others saw it: the carried ones (hand
## and belt, by peer and place) first, then the lying and locked ones in id order, at most
## WelcomeEvent.MAX_ITEMS. Public facts only (§5). Driven by FixtureLobbyHands.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2
const P3 := FixtureLobbyHands.P3
const ROW_KEYS := ["holder", "item", "kind", "place", "position", "where"]
const STATION_AT := Vector3(2, 0, -2)


func test_a_joiner_learns_the_items_put_down_carried_and_locked_in_the_lobby() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1])
	var put := FixtureLobbyHands.give(game, P1, &"tool")
	FixtureItemModes.put_down(game, P1, Vector3.FORWARD)
	var belted := FixtureLobbyHands.give(game, P1, &"tool")
	var held := FixtureLobbyHands.give(game, P1, &"tool")
	var locked := _locked_at_a_station(game)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	FixtureBaseMode.join(game, P2)
	var welcome := _welcome(game, P2)
	var places := game.state.player(P1).places
	assert_int(places[game.state.player(P1).selected_place]).is_equal(held.id)
	(
		assert_array(welcome.items)
		. is_equal(
			[
				_row(belted, ItemState.Where.BELT, P1, places.find(belted.id)),
				_row(held, ItemState.Where.HAND, P1, places.find(held.id)),
				_row(put, ItemState.Where.GROUND, 0, 0),
				_row(locked, ItemState.Where.LOCKED, 0, 0),
			]
		)
	)
	assert_int(welcome.items[2]["where"]).is_equal(ItemState.Where.GROUND)
	assert_vector(welcome.items[3]["position"]).is_equal(STATION_AT)
	# The station that holds the locked item: replayed to the joiner after its Welcome.
	var placed := game.view_of(P2).events_named(&"StationPlaced")
	assert_int(placed.size()).is_equal(1)
	assert_vector((placed[0] as StationPlacedEvent).position).is_equal(STATION_AT)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_later_item_event_names_an_item_the_welcome_listed() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1])
	var put := FixtureLobbyHands.give(game, P1, &"tool")
	FixtureItemModes.put_down(game, P1, Vector3.FORWARD)
	FixtureBaseMode.join(game, P2)
	var listed: Array[int] = []
	for row: Dictionary in _welcome(game, P2).items:
		listed.append(row["item"] as int)
	assert_array(listed).is_equal([put.id])
	FixtureItemModes.pick_up(game, P1, put, 1)
	var picked := game.view_of(P2).events_named(&"ItemPickedUp")
	assert_int(picked.size()).is_equal(1)
	assert_int((picked[0] as ItemPickedUpEvent).item).is_equal(put.id)


func test_a_joiner_in_the_countdown_learns_them_too() -> void:
	var game := FixtureLobbyHands.in_countdown(FixtureLobbyHands.mode(), [P1])
	assert_str(game.phase_id()).is_equal("countdown")
	var held := FixtureLobbyHands.give(game, P1, &"tool")
	FixtureBaseMode.join(game, P2)
	var welcome := _welcome(game, P2)
	assert_str(welcome.phase).is_equal("countdown")
	assert_array(welcome.items).is_equal([_row(held, ItemState.Where.HAND, P1, 0)])


func test_an_empty_hall_gives_no_rows_and_every_row_holds_public_facts_only() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1])
	FixtureBaseMode.join(game, P2)
	assert_array(_welcome(game, P2).items).is_empty()
	FixtureLobbyHands.give(game, P1, &"tool")
	FixtureLobbyHands.give(game, P2, &"tool")
	_locked_at_a_station(game)
	FixtureBaseMode.join(game, P3)
	var welcome := _welcome(game, P3)
	assert_int(welcome.items.size()).is_equal(3)
	for row: Dictionary in welcome.items:
		var keys: Array = row.keys()
		keys.sort()
		assert_array(keys).is_equal(ROW_KEYS)
	var text := str(welcome.to_dict())
	for hidden: String in ["role", "health", "stamina", "seed"]:
		assert_str(text).not_contains(hidden)


func test_rows_past_the_cap_are_left_out_with_an_error_carried_first() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1])
	for i: int in WelcomeEvent.MAX_ITEMS:
		FixtureItemModes.lay(game, &"tool", Vector3(i * 0.01, 0, 5))
	var held := FixtureLobbyHands.give(game, P1, &"tool")
	FixtureBaseMode.join(game, P2)
	var welcome := _welcome(game, P2)
	assert_int(welcome.items.size()).is_equal(WelcomeEvent.MAX_ITEMS)
	assert_dict(welcome.items[0]).is_equal(_row(held, ItemState.Where.HAND, P1, 0))
	var errors := "\n".join(game.diagnostics)
	assert_str(errors).contains("Welcome: %d items, %d sent" % [97, WelcomeEvent.MAX_ITEMS])


func test_a_flying_item_is_sent_lying_where_it_was_with_an_error() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1])
	var flying := FixtureItemModes.lay(game, &"tool", Vector3(1, 0, 3))
	# Lobby refuses Throw, so no rule does this: the host state is set wrong by hand.
	flying.where = ItemState.Where.FLYING
	FixtureBaseMode.join(game, P2)
	var welcome := _welcome(game, P2)
	assert_array(welcome.items).is_equal([_row(flying, ItemState.Where.GROUND, 0, 0)])
	assert_int(welcome.items[0]["where"]).is_equal(ItemState.Where.GROUND)
	assert_vector(welcome.items[0]["position"]).is_equal(Vector3(1, 0, 3))
	assert_str("\n".join(game.diagnostics)).contains("Welcome: item %d flies in" % flying.id)


func test_an_item_in_a_place_of_a_player_who_is_not_its_holder_is_left_out_with_an_error() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1, P2])
	var held := FixtureLobbyHands.give(game, P2, &"tool")
	# The earlier player's place list also names it: the host state disagrees with itself.
	game.state.player(P1).places[0] = held.id
	FixtureBaseMode.join(game, P3)
	var welcome := _welcome(game, P3)
	assert_array(welcome.items).is_equal([_row(held, ItemState.Where.HAND, P2, 0)])
	assert_str("\n".join(game.diagnostics)).contains(
		"Welcome: item %d is in place 0 of %d" % [held.id, P1]
	)


func test_an_item_named_by_two_places_of_its_holder_gets_one_row_and_an_error() -> void:
	var game := FixtureLobbyHands.in_lobby(FixtureLobbyHands.mode(), [P1])
	var held := FixtureLobbyHands.give(game, P1, &"tool")
	game.state.player(P1).places[1] = held.id
	FixtureBaseMode.join(game, P2)
	assert_array(_welcome(game, P2).items).is_equal([_row(held, ItemState.Where.HAND, P1, 0)])
	assert_str("\n".join(game.diagnostics)).contains(
		"Welcome: item %d is in place 1 of %d" % [held.id, P1]
	)


## An item laid at a placed station and locked there, as Items.lock_at leaves it; no lobby rule
## does this today (the issue asks for the case all the same).
func _locked_at_a_station(game: Match) -> ItemState:
	var kind := StationKind.new()
	kind.id = &"bar"
	game.state.add_station(kind, STATION_AT, Color.WHITE)
	var item := FixtureItemModes.lay(game, &"tool", STATION_AT)
	Items.lock(item)
	return item


func _welcome(game: Match, peer: int) -> WelcomeEvent:
	var welcomes := game.view_of(peer).events_named(&"Welcome")
	assert_int(welcomes.size()).is_equal(1)
	return welcomes[0] as WelcomeEvent


func _row(item: ItemState, where: ItemState.Where, holder: int, place: int) -> Dictionary:
	return {
		"item": item.id,
		"kind": item.kind.id,
		"where": where as int,
		"holder": holder,
		"place": place,
		"position": item.position,
	}
