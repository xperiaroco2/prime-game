extends GdUnitTestSuite
## Cooking's places (core/tasks/cooking.gd; the cooking ADR's §2.5, §4, CD8 (b), CE5, CE13, #773):
## Interact on a place puts the hand item on. Right (the order's bun, fried patty or herb, its slot
## empty): locked there; wrong: it lies at the place, and PickUp takes it back; IngredientPlaced
## either way. The third right one: the place done, then Tasks.subtask_done. Refused `two_handed`
## (the rule's HandNotTwoHanded), then `unavailable` (done), `empty_hand`, `wrong_item` (not an
## ingredient a place takes: a knife, a raw or burnt patty). Driven by commands through a seeded
## Match on FixtureCookingModes.

const P1 := 1
const P2 := 2

var _game: Match


func before_test() -> void:
	_game = FixtureCookingModes.in_round(FixtureCookingModes.basic(2), [P1, P2])


func test_the_order_s_bun_is_right_locked_on_the_place() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	var bun := FixtureCookingModes.held(_game, P1)
	var place := _game.state.stations[_place(0)]
	_use(P1, 0)
	assert_int(bun.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(bun.position).is_equal(place.position)
	assert_int(_game.state.player(P1).held_item).is_equal(-1)
	assert_int(order.bun_item).is_equal(bun.id)
	var placed := {"item": bun.id, "station": place.id, "right": true}
	for peer: int in [P1, P2]:
		assert_array(FixtureCookingModes.dicts(_game, peer, &"IngredientPlaced")).is_equal([placed])


func test_another_bun_is_wrong_it_lies_at_the_place_and_pick_up_takes_it_back() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, _other_bun(order).id)
	var bun := FixtureCookingModes.held(_game, P1)
	var place := _game.state.stations[_place(0)]
	var at := _game.ticked_through() + 1
	_use(P1, 0)
	assert_int(bun.where).is_equal(ItemState.Where.GROUND)
	assert_vector(bun.position).is_equal(place.position)
	assert_int(bun.rest_tick).is_equal(at)
	assert_int(order.bun_item).is_equal(-1)
	var placed := {"item": bun.id, "station": place.id, "right": false}
	assert_array(FixtureCookingModes.dicts(_game, P2, &"IngredientPlaced")).is_equal([placed])
	assert_array(FixtureModes.notes(_game)).contains(
		["rested %d %s %s" % [bun.id, Items.ON_STATION, place.position]]
	)
	FixtureModes.run_ticks(_game, 1)
	FixtureItemModes.pick_up(_game, P1, bun)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(bun)


func test_a_second_right_bun_on_a_green_bun_is_wrong() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	var second := FixtureCookingModes.held(_game, P1)
	_use(P1, 0)
	assert_int(second.where).is_equal(ItemState.Where.GROUND)
	var rights: Array = []
	for placed: Dictionary in FixtureCookingModes.dicts(_game, P1, &"IngredientPlaced"):
		rights.append(placed["right"])
	assert_array(rights).is_equal([true, false])


func test_the_other_fried_patty_is_wrong() -> void:
	var order := _order(0)
	var other := _other_raw(order)
	var patty := FixtureCookingModes.fry(_game, P1, other.id)
	FixtureModes.run_ticks(_game, 1)
	assert_bool(patty.kind == FixtureCookingModes.type_of(_game.mode).fried_of(other)).is_true()
	_use(P1, 0)
	assert_int(patty.where).is_equal(ItemState.Where.GROUND)
	assert_bool(FixtureCookingModes.dicts(_game, P1, &"IngredientPlaced")[0]["right"]).is_false()


func test_a_raw_or_burnt_patty_is_refused_wrong_item_and_stays_in_the_hand() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, order.raw_patty.id)
	var raw := FixtureCookingModes.held(_game, P1)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(raw)
	var grill := FixtureCookingModes.grill_of(_game)
	FixtureCookingModes.use(_game, P1, grill)
	FixtureModes.run_ticks(_game, FixtureCookingModes.type_of(_game.mode).burnt_ticks() + 1)
	FixtureCookingModes.use(_game, P1, grill)
	FixtureModes.run_ticks(_game, 1)
	assert_str(raw.kind.id).is_equal("burnt")
	_use(P1, 0)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(raw)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"wrong_item", &"wrong_item"])
	assert_int(FixtureCookingModes.dicts(_game, P2, &"IngredientPlaced").size()).is_equal(0)


func test_a_knife_is_refused_wrong_item_and_a_package_two_handed() -> void:
	var knife := FixtureCombatModes.arm(_game, P1, Vector3(12, 0, 5))
	FixtureModes.run_ticks(_game, 1)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(knife)
	var package := FixtureItemModes.lay(_game, &"package", Vector3(13, 0, 5))
	FixtureItemModes.stand(_game, P2, Vector3(13, 0, 6))
	FixtureItemModes.pick_up(_game, P2, package)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(package)
	_use(P2, 0)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"wrong_item"])
	assert_array(FixtureModes.rejections(_game, P2)).is_equal([&"two_handed"])


func test_an_empty_hand_is_refused_empty_hand() -> void:
	_use(P1, 0)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"empty_hand"])


func test_the_third_right_one_completes_the_subtask_once_after_its_ingredient_placed() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.fry(_game, P1, order.raw_patty.id)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.pick(_game, P1, order.herb.id)
	FixtureModes.run_ticks(_game, 1)
	var herb := FixtureCookingModes.held(_game, P1)
	assert_object(herb.kind).is_same(order.herb)
	assert_bool(order.done).is_false()
	var seen := _game.view_of(P2).events.size()
	_use(P1, 0)
	assert_bool(order.done).is_true()
	assert_bool(_game.state.stations[_place(0)].done).is_true()
	assert_int(herb.where).is_equal(ItemState.Where.LOCKED)
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal(
		[&"IngredientPlaced", &"TaskState", &"TaskProgress"]
	)
	assert_array(FixtureCookingModes.dicts(_game, P2, &"TaskProgress")[-1].values()).is_equal(
		[1, 2]
	)
	assert_bool(FixtureCookingModes.state_of(_game).done_count() == 1).is_true()
	# A done place refuses more, so the subtask is done once.
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	_use(P1, 0)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"unavailable"])
	assert_int(_game.view_of(P2).events_named(&"TaskProgress").size()).is_equal(2)


func test_a_red_one_on_a_done_place_still_goes_back_with_pick_up() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, _other_bun(order).id)
	var red := FixtureCookingModes.held(_game, P1)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.cook(_game, P1, 0)
	assert_bool(order.done).is_true()
	FixtureItemModes.stand(_game, P2, red.position + Vector3(0, 0, -1))
	FixtureItemModes.pick_up(_game, P2, red)
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(red)


func test_a_second_place_s_order_is_its_own() -> void:
	FixtureCookingModes.cook(_game, P1, 1)
	assert_bool(_order(1).done).is_true()
	assert_bool(_order(0).done).is_false()
	assert_bool(_game.state.stations[_place(0)].done).is_false()


func _order(index: int) -> Cooking.Order:
	return FixtureCookingModes.state_of(_game).orders[index]


func _place(index: int) -> int:
	return FixtureCookingModes.place_of(_game, index)


func _use(peer: int, index: int) -> void:
	FixtureCookingModes.use(_game, peer, _place(index))


func _other_bun(order: Cooking.Order) -> ItemKind:
	for bun: ItemKind in FixtureCookingModes.type_of(_game.mode).buns:
		if bun != order.bun:
			return bun
	return null


func _other_raw(order: Cooking.Order) -> ItemKind:
	for raw: ItemKind in FixtureCookingModes.type_of(_game.mode).raw_patties:
		if raw != order.raw_patty:
			return raw
	return null


func test_a_bun_carried_past_its_time_vanishes_exactly_its_time_after_it_is_laid_red() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, _other_bun(order).id)
	var bun := FixtureCookingModes.held(_game, P1)
	var vanish := Ticks.from_seconds(FixtureCookingModes.VANISH)
	# Carried for longer than it may lie: a held item does not lie.
	FixtureModes.run_ticks(_game, vanish + 100)
	assert_bool(_game.state.items.has(bun.id)).is_true()
	_use(P1, 0)
	var laid := bun.rest_tick
	assert_int(laid).is_equal(_game.ticked_through() + 1)
	FixtureModes.run_ticks(_game, laid + vanish - 1 - _game.ticked_through())
	assert_bool(_game.state.items.has(bun.id)).is_true()
	FixtureModes.run_ticks(_game, 1)
	assert_bool(_game.state.items.has(bun.id)).is_false()
	assert_int(_game.ticked_through()).is_equal(laid + vanish)


func test_an_ingredient_put_down_near_a_place_lies_on_the_floor_unchecked() -> void:
	var order := _order(0)
	var bun := order.bun
	bun.actions = [FixtureItemModes.put_down_rule(1.0)]
	FixtureCookingModes.take(_game, P1, bun.id)
	var held := FixtureCookingModes.held(_game, P1)
	var place := _game.state.stations[_place(0)]
	FixtureItemModes.stand(_game, P1, place.position + Vector3(0, 0, 1))
	FixtureItemModes.put_down(_game, P1, Vector3(0, 0, -1))
	assert_int(held.where).is_equal(ItemState.Where.GROUND)
	assert_int(order.bun_item).is_equal(-1)
	assert_bool(place.done).is_false()
	for peer: int in [P1, P2]:
		assert_array(FixtureCookingModes.dicts(_game, peer, &"IngredientPlaced")).is_empty()
	assert_array(FixtureModes.rejections(_game, P1)).is_empty()


func test_a_done_place_refuses_unavailable_before_empty_hand_and_wrong_item() -> void:
	FixtureCookingModes.cook(_game, P1, 0)
	assert_bool(_order(0).done).is_true()
	# An empty hand: unavailable, not empty_hand.
	_use(P2, 0)
	assert_array(FixtureModes.rejections(_game, P2)).is_equal([&"unavailable"])
	# A raw patty (a wrong_item at a place that is not done): unavailable too.
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.take(_game, P2, _order(0).raw_patty.id)
	_use(P2, 0)
	assert_array(FixtureModes.rejections(_game, P2)).is_equal([&"unavailable", &"unavailable"])
