extends GdUnitTestSuite
## DeliveryByMeaning's check (#683's ADR §2.2-§2.4, §4, DD5 (a), DE7; ARCHITECTURE §7.1.14): an item
## resting on the ground inside its own drop-off is delivered; another place, another item or a
## held item does nothing; a place is done once every item routed to it is delivered.

const P1 := 1
const P2 := 2


func test_an_item_put_down_in_its_own_place_is_delivered() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(4), [P1, P2])
	var task := FixtureMeaningModes.task_of(game)
	var item := FixtureMeaningModes.item_of(game, 0)
	var place := FixtureMeaningModes.station_of(game, 0)
	var seen := game.view_of(P2).events.size()
	var notes := FixtureModes.notes(game).size()
	FixtureDeliveryModes.carry_to(game, P1, item, place.position)
	assert_int(item.where).is_equal(ItemState.Where.LOCKED)
	assert_bool(place.done).is_true()
	assert_int(task.state.done_count()).is_equal(1)
	var expected: Array[StringName] = [
		&"ItemPickedUp", &"ItemPlaced", &"PackageDelivered", &"TaskState", &"TaskProgress"
	]
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(expected)
	assert_dict(game.view_of(P2).events_named(&"PackageDelivered")[0].to_dict()).is_equal(
		{"item": item.id, "station": place.id}
	)
	assert_dict(game.view_of(P2).events_named(&"TaskState")[-1].to_dict()).is_equal(
		{"task": task.id, "type": &"delivery", "done": 1, "total": 4}
	)
	# subtask_done comes after the events, with the subtask and the item.
	assert_int(FixtureModes.notes(game).size()).is_equal(notes + 1)
	# Delivered: locked, PickUp gets `unavailable`.
	FixtureItemModes.stand(game, P2, place.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P2, item, 9)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])


func test_another_routes_place_and_another_item_do_nothing() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(4), [P1, P2])
	var task := FixtureMeaningModes.task_of(game)
	var item := FixtureMeaningModes.item_of(game, 0)
	var other := FixtureMeaningModes.other_station(game, FixtureMeaningModes.station_of(game, 0))
	FixtureDeliveryModes.carry_to(game, P1, item, other.position)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_bool(other.done).is_false()
	assert_int(task.state.done_count()).is_equal(0)
	# Anyone may carry it on from there.
	FixtureItemModes.stand(game, P2, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P2, item, 9)
	assert_int(game.state.player(P2).held_item).is_equal(item.id)
	# A one-handed tool, no item of the task, in a place does nothing either.
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(30, 0, 0))
	FixtureDeliveryModes.carry_to(game, P1, tool, FixtureMeaningModes.station_of(game, 1).position)
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	assert_int(task.state.done_count()).is_equal(0)
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).is_empty()


func test_a_place_with_two_items_is_done_only_after_both() -> void:
	# N = 5 over 4 routes: one route, and so one place, takes two items.
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(5), [P1, P2])
	var state := FixtureMeaningModes.state_of(game)
	var pair: Array[int] = []
	for i in state.total():
		for j in range(i + 1, state.total()):
			if state.stations[i] == state.stations[j]:
				pair = [i, j]
	assert_array(pair).has_size(2)
	var place := FixtureMeaningModes.station_of(game, pair[0])
	FixtureDeliveryModes.carry_to(
		game, P1, FixtureMeaningModes.item_of(game, pair[0]), place.position
	)
	assert_bool(state.done[pair[0]]).is_true()
	assert_bool(place.done).is_false()
	FixtureDeliveryModes.carry_to(
		game, P2, FixtureMeaningModes.item_of(game, pair[1]), place.position + Vector3(0, 0, 0.5)
	)
	assert_bool(state.done[pair[1]]).is_true()
	assert_bool(place.done).is_true()
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).has_size(2)


func test_a_held_item_never_counts_nor_one_held_by_a_carrier_knocked_down_in_its_place() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(4), [P1, P2])
	var item := FixtureMeaningModes.item_of(game, 0)
	var place := FixtureMeaningModes.station_of(game, 0)
	FixtureItemModes.stand(game, P1, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	FixtureItemModes.stand(game, P1, place.position)
	FixtureModes.run_ticks(game, 2)
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	# Knocked down there: nothing drops at a knockdown (§7.1.13), so nothing is delivered.
	game.state.player(P1).life = PlayerState.Life.DOWNED
	FixtureModes.run_ticks(game, 2)
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	assert_bool(place.done).is_false()
	# A raise leaves it in the hands.
	game.state.player(P1).life = PlayerState.Life.ALIVE
	FixtureModes.run_ticks(game, 2)
	assert_int(game.state.player(P1).held_item).is_equal(item.id)
	assert_array(game.view_of(P2).events_named(&"PackageDelivered")).is_empty()


func test_an_item_rested_while_held_inside_its_place_is_not_delivered() -> void:
	# Only an item on the ground is delivered. No shipped part raises item_rested for a held item
	# today; should one (raised by hand here), the item stays in the hands and nothing is done.
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(4), [P1, P2])
	var task := FixtureMeaningModes.task_of(game)
	var item := FixtureMeaningModes.item_of(game, 0)
	var place := FixtureMeaningModes.station_of(game, 0)
	FixtureItemModes.stand(game, P1, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	FixtureItemModes.stand(game, P1, place.position)
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	item.position = place.position
	assert_bool(place.contains(item.position)).is_true()
	var seen := game.view_of(P2).events.size()
	Items.raise_rested(_context(game), item, Items.PUT_DOWN)
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	assert_array(game.view_of(P2).events.slice(seen)).is_empty()
	assert_bool(FixtureMeaningModes.state_of(game).done[0]).is_false()
	assert_int(task.state.done_count()).is_equal(0)
	assert_bool(place.done).is_false()


func test_an_item_dropped_at_a_death_inside_its_place_is_delivered() -> void:
	var mode := FixtureMeaningModes.basic(4)
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.DEATH)]))
	var game := FixtureMeaningModes.in_round(mode, [P1, P2])
	var item := FixtureMeaningModes.item_of(game, 0)
	var place := FixtureMeaningModes.station_of(game, 0)
	FixtureItemModes.stand(game, P1, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	FixtureItemModes.stand(game, P1, place.position + Vector3(0, 0, 0.4))
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(item.where).is_equal(ItemState.Where.LOCKED)
	assert_bool(place.done).is_true()
	for peer: int in [P1, P2]:
		assert_array(game.view_of(peer).events_named(&"PackageDelivered")).has_size(1)


func test_an_item_thrown_into_its_place_is_delivered_once_it_rests() -> void:
	var game := FixtureMeaningModes.in_round(
		FixtureFlightModes.with_throw(FixtureMeaningModes.basic(4)), [P1, P2]
	)
	var item := FixtureMeaningModes.item_of(game, 0)
	var place := FixtureMeaningModes.station_of(game, 0)
	FixtureItemModes.stand(game, P1, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	# A level throw from the 1.6 m eye lands about 5.44 m ahead (delivery_throw_test.gd).
	FixtureItemModes.stand(game, P1, place.position - Vector3(5.44, 0, 0))
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	assert_bool(place.done).is_false()
	FixtureModes.run_ticks(game, 20)
	assert_int(item.where).is_equal(ItemState.Where.LOCKED)
	assert_bool(place.done).is_true()


func test_a_delivered_item_that_rests_again_is_not_delivered_twice() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(4), [P1, P2])
	var task := FixtureMeaningModes.task_of(game)
	var item := FixtureMeaningModes.item_of(game, 0)
	FixtureDeliveryModes.carry_to(game, P1, item, FixtureMeaningModes.station_of(game, 0).position)
	item.where = ItemState.Where.GROUND
	var seen := game.view_of(P2).events.size()
	Items.raise_rested(_context(game), item, Items.PUT_DOWN)
	assert_array(game.view_of(P2).events.slice(seen)).is_empty()
	assert_int(task.state.done_count()).is_equal(1)


func test_every_item_delivered_completes_the_task() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(6), [P1, P2])
	var task := FixtureMeaningModes.task_of(game)
	for i in task.state.total():
		var place := FixtureMeaningModes.station_of(game, i)
		FixtureDeliveryModes.carry_to(
			game,
			P1,
			FixtureMeaningModes.item_of(game, i),
			place.position + Vector3(0, 0, 0.2 * (i % 4))
		)
	assert_bool(task.state.is_done()).is_true()
	for id: int in game.state.stations:
		assert_bool(game.state.stations[id].done).is_true()


func _context(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx
