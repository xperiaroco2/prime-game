extends GdUnitTestSuite
## Items on stations and items that change kind (ARCHITECTURE §9.3; the cooking ADR, CE4, CE5):
## Items.lock_at locks an item at a station's spot (no PickUp takes it, it never lies), only
## Items.give hands it out again; Items.lay_on_station lays one there, interactive, with item_rested
## `on_station` and no ItemPlaced; Items.change_kind turns an item into another kind in place, with
## ItemChanged to everyone. Driven by Use through FixtureItemMove (the stand-in for the grill and
## the places) and PickUp on a seeded fixture match; asserted on the events, view_of and the state.

const P1 := 1
const P2 := 2
const HERE := Vector3(0.5, 0, 0.25)
## A station's spot (a grill's grate, a place's plate), in P1's reach.
const STATION := Vector3(1.5, 0, 0.25)


func test_a_locked_item_is_out_of_the_hand_and_no_pick_up_takes_it() -> void:
	var game := _game()
	var raw := _picked(game, &"raw")
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.LOCK, STATION)
	assert_int(raw.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(raw.position).is_equal(STATION)
	assert_int(raw.holder).is_equal(0)
	assert_int(raw.rest_tick).is_equal(-1)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	# The station's own event announces it (GrillLoaded, C3): Items emits nothing, raises nothing.
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()
	assert_array(FixtureModes.notes(game)).is_empty()
	FixtureItemModes.pick_up(game, P1, raw)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_int(raw.where).is_equal(ItemState.Where.LOCKED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_locked_item_is_given_back_through_give() -> void:
	var game := _game()
	var raw := _picked(game, &"raw")
	FixtureItemMove.use(game, P1, FixtureItemMove.LOCK, STATION)
	var package := _picked(game, &"package")
	var seen := game.view_of(P2).events.size()
	# The grill's take-off beside a package: onto the belt, the package kept (CD3 (b), CE20).
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE_AT, STATION)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(package.id)
	assert_int(player.belt_item).is_equal(raw.id)
	assert_int(raw.where).is_equal(ItemState.Where.BELT)
	assert_int(raw.holder).is_equal(P1)
	assert_int(raw.rest_tick).is_equal(-1)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal([&"ItemPickedUp"])
	var picked := game.view_of(P2).events_named(&"ItemPickedUp")[-1] as ItemPickedUpEvent
	assert_dict(picked.to_dict()).is_equal(
		{"peer": P1, "item": raw.id, "belted": raw.id, "place": 1}
	)
	assert_array(Array(game.diagnostics)).is_empty()


func test_an_item_laid_on_a_station_lies_there_and_is_picked_up_again() -> void:
	var game := _game()
	var herb := _picked(game, &"herb")
	var seen := game.view_of(P2).events.size()
	var tick := game.ticked_through() + 1
	FixtureItemMove.use(game, P1, FixtureItemMove.LAY, STATION)
	assert_int(herb.where).is_equal(ItemState.Where.GROUND)
	assert_vector(herb.position).is_equal(STATION)
	assert_int(herb.holder).is_equal(0)
	assert_int(herb.rest_tick).is_equal(tick)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	# item_rested with the cause on_station, and no ItemPlaced: IngredientPlaced (C4) says where.
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"FixtureNote", &"FixtureNote"]
	)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureRestedNote.text(herb.id, &"on_station", STATION), "task item_rested"]
	)
	FixtureItemModes.pick_up(game, P1, herb)
	assert_int(herb.where).is_equal(ItemState.Where.HAND)
	assert_int(herb.rest_tick).is_equal(-1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_an_item_changes_kind_in_place_and_everyone_is_told() -> void:
	var game := _game()
	var raw := _picked(game, &"raw")
	FixtureItemMove.use(game, P1, FixtureItemMove.LOCK, STATION)
	var id := raw.id
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.CHANGE, STATION, &"fried")
	assert_object(game.state.items[id]).is_same(raw)
	assert_str(String(raw.kind.id)).is_equal("fried")
	assert_int(raw.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(raw.position).is_equal(STATION)
	for peer: int in [P1, P2]:
		var changed := game.view_of(peer).events_named(&"ItemChanged")
		assert_array(changed).has_size(1)
		assert_dict((changed[0] as ItemChangedEvent).to_dict()).is_equal(
			{"item": id, "kind": &"fried"}
		)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal([&"ItemChanged"])
	# Already that kind: nothing changes, nothing is said.
	FixtureItemMove.use(game, P1, FixtureItemMove.CHANGE, STATION, &"fried")
	assert_array(game.view_of(P2).events_named(&"ItemChanged")).has_size(1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_carried_item_keeps_its_holder_and_a_lying_one_its_rest_tick() -> void:
	var game := _game()
	var raw := _picked(game, &"raw")
	FixtureItemMove.use(game, P1, FixtureItemMove.CHANGE_HELD, Vector3.ZERO, &"fried")
	assert_str(String(raw.kind.id)).is_equal("fried")
	assert_int(raw.where).is_equal(ItemState.Where.HAND)
	assert_int(raw.holder).is_equal(P1)
	assert_int(game.state.player(P1).held_item).is_equal(raw.id)
	FixtureItemMove.use(game, P1, FixtureItemMove.LAY, STATION)
	var laid := raw.rest_tick
	FixtureModes.run_ticks(game, 5)
	FixtureItemMove.use(game, P1, FixtureItemMove.CHANGE, STATION, &"raw")
	assert_str(String(raw.kind.id)).is_equal("raw")
	assert_int(raw.where).is_equal(ItemState.Where.GROUND)
	assert_int(raw.rest_tick).is_equal(laid)
	assert_array(game.view_of(P2).events_named(&"ItemChanged")).has_size(2)


## The photo ADR's PE17: every lay and every lift bumps ItemState.moves, two in one tick too, so a
## part that remembers an item lying at a spot (the camera's film) sees a lift and a lay in the
## same tick, which leave the rest tick as it was.
func test_every_lay_and_lift_bumps_the_move_serial() -> void:
	var game := _game()
	var herb := FixtureItemModes.lay(game, &"herb", HERE + Vector3(0, 0, 1))
	var moves := herb.moves
	FixtureItemModes.pick_up(game, P1, herb)
	assert_int(herb.moves).is_equal(moves + 1)
	FixtureItemMove.use(game, P1, FixtureItemMove.LAY, STATION)
	assert_int(herb.moves).is_equal(moves + 2)
	var laid := herb.rest_tick
	# A lift and a lay in one tick: the rest tick looks the same, the serial does not.
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.tick = laid
	ctx.actor = P1
	Items.give(ctx, P1, herb)
	Items.lay(ctx, herb, STATION)
	assert_int(herb.rest_tick).is_equal(laid)
	assert_int(herb.moves).is_equal(moves + 4)
	Items.lock(herb)
	assert_int(herb.moves).is_equal(moves + 5)
	Items.give(ctx, P1, herb)
	Items.back(ctx, P1)
	assert_int(herb.moves).is_equal(moves + 6)
	Items.launch(ctx, herb, ItemFlight.new())
	assert_int(herb.moves).is_equal(moves + 7)
	assert_array(Array(game.diagnostics)).is_empty()


func test_locking_or_laying_no_item_is_a_logged_rule_error_and_moves_nothing() -> void:
	var game := _game()
	var seen := game.view_of(P2).events.size()
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.tick = game.ticked_through() + 1
	ctx.actor = P1
	Items.lock_at(ctx, null, STATION)
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("lock_at: no item")
	Items.lay_on_station(ctx, null, STATION)
	assert_int(game.diagnostics.size()).is_equal(2)
	assert_str(game.diagnostics[1]).contains("lay_on_station: no item")
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()
	assert_array(FixtureModes.notes(game)).is_empty()


func _game() -> Match:
	var game := FixtureItemModes.in_round(FixtureItemMove.mode(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	return game


## An item of `kind_id` laid next to P1 and picked up by it.
func _picked(game: Match, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, HERE + Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P1, item)
	return item
