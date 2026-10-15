extends GdUnitTestSuite
## Cooking's places (core/tasks/cooking.gd; the cooking ADR's §2.5, §4, CD8 (b), CE5, CE13, #773,
## and its amendment of 2026-10-15, #1101): Interact on a place puts the hand item on its free
## slot, locked there, whatever the order asks: nothing is checked before the burger is served
## (cooking_serve_test.gd), and IngredientPlaced carries no word of right or wrong. Refused
## `two_handed` (the rule's HandNotTwoHanded), then `unavailable` (done), `empty_hand`,
## `wrong_item` (not an ingredient a place takes: a knife, a raw or burnt patty), `unavailable`
## (the slot filled). Driven by commands through a seeded Match on FixtureCookingModes.

const P1 := 1
const P2 := 2

var _game: Match


func before_test() -> void:
	_game = FixtureCookingModes.in_round(FixtureCookingModes.basic(2), [P1, P2])


func test_the_order_s_bun_is_locked_on_the_place() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	var bun := FixtureCookingModes.held(_game, P1)
	var place := _game.state.stations[_place(0)]
	_use(P1, 0)
	assert_int(bun.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(bun.position).is_equal(place.position)
	assert_int(_game.state.player(P1).held_item).is_equal(-1)
	assert_int(order.bun_item).is_equal(bun.id)
	var placed := {"item": bun.id, "station": place.id}
	for peer: int in [P1, P2]:
		assert_array(FixtureCookingModes.dicts(_game, peer, &"IngredientPlaced")).is_equal([placed])


## Before #1101 another bun lay on the ground at the place, drawn red; now it is locked on the
## bun slot as the order's would be, and the event is the same.
func test_another_bun_is_locked_on_the_place_as_the_order_s_would_be() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, _other_bun(order).id)
	var bun := FixtureCookingModes.held(_game, P1)
	var place := _game.state.stations[_place(0)]
	_use(P1, 0)
	assert_int(bun.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(bun.position).is_equal(place.position)
	assert_int(order.bun_item).is_equal(bun.id)
	var placed := {"item": bun.id, "station": place.id}
	assert_array(FixtureCookingModes.dicts(_game, P2, &"IngredientPlaced")).is_equal([placed])
	for note: Variant in FixtureModes.notes(_game):
		assert_str(str(note)).not_contains(String(Items.ON_STATION))


## A plated item is locked: no PickUp takes it back (a wrong one goes with the burger, #1101).
func test_a_plated_item_is_not_picked_up() -> void:
	FixtureCookingModes.take(_game, P1, _other_bun(_order(0)).id)
	var bun := FixtureCookingModes.held(_game, P1)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	FixtureItemModes.stand(_game, P2, bun.position + Vector3(0, 0, -1))
	FixtureItemModes.pick_up(_game, P2, bun)
	assert_object(FixtureCookingModes.held(_game, P2)).is_null()
	assert_int(bun.where).is_equal(ItemState.Where.LOCKED)


## Before #1101 a second right bun lay there wrong; now a filled slot refuses another bun
## `unavailable`, and it stays in the hand.
func test_a_second_bun_on_a_filled_bun_slot_is_refused_unavailable() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, order.bun.id)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.take(_game, P1, _other_bun(order).id)
	var second := FixtureCookingModes.held(_game, P1)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(second)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"unavailable"])
	assert_int(FixtureCookingModes.dicts(_game, P2, &"IngredientPlaced").size()).is_equal(1)


func test_the_other_fried_patty_is_locked_on_the_patty_slot() -> void:
	var order := _order(0)
	var other := _other_raw(order)
	var patty := FixtureCookingModes.fry(_game, P1, other.id)
	FixtureModes.run_ticks(_game, 1)
	assert_bool(patty.kind == FixtureCookingModes.type_of(_game.mode).fried_of(other)).is_true()
	_use(P1, 0)
	assert_int(patty.where).is_equal(ItemState.Where.LOCKED)
	assert_int(order.patty_item).is_equal(patty.id)


## Nothing about right or wrong before a burger is served (#1101): a right bun on one place and a
## wrong one on another send the same events with the same keys, and no event carries a bool.
func test_a_right_and_a_wrong_put_look_the_same_to_every_peer() -> void:
	var seen := _game.view_of(P2).events.size()
	FixtureCookingModes.take(_game, P1, _order(0).bun.id)
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	var right_names := FixtureItemModes.names_after(_game, P2, seen)
	seen = _game.view_of(P2).events.size()
	FixtureCookingModes.take(_game, P1, _other_bun(_order(1)).id)
	_use(P1, 1)
	FixtureModes.run_ticks(_game, 1)
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal(right_names)
	var dicts := FixtureCookingModes.dicts(_game, P2, &"IngredientPlaced")
	assert_int(dicts.size()).is_equal(2)
	for placed: Dictionary in dicts:
		assert_array(placed.keys()).is_equal(["item", "station"])
	for peer: int in [P1, P2]:
		for event: MatchEvent in _game.view_of(peer).events:
			for value: Variant in event.to_dict().values():
				var says := "%s carries a bool" % event.event_name()
				assert_bool(value is bool).override_failure_message(says).is_false()


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


## Before #1101 the third right one completed the subtask on the spot; now it only fills the
## plate: IngredientPlaced alone, nothing done (the serve completes it, cooking_serve_test.gd).
func test_the_third_one_fills_the_plate_and_completes_nothing() -> void:
	var order := _order(0)
	FixtureCookingModes.put(_game, P1, 0, order.bun.id)
	FixtureCookingModes.put(_game, P1, 0, order.raw_patty.id)
	FixtureCookingModes.pick(_game, P1, order.herb.id)
	FixtureModes.run_ticks(_game, 1)
	var herb := FixtureCookingModes.held(_game, P1)
	assert_object(herb.kind).is_same(order.herb)
	var seen := _game.view_of(P2).events.size()
	_use(P1, 0)
	FixtureModes.run_ticks(_game, 1)
	assert_bool(order.done).is_false()
	assert_bool(_game.state.stations[_place(0)].done).is_false()
	assert_int(herb.where).is_equal(ItemState.Where.LOCKED)
	assert_int(order.herb_item).is_equal(herb.id)
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal([&"IngredientPlaced"])
	assert_int(FixtureCookingModes.state_of(_game).done_count()).is_equal(0)


## A done place keeps nothing on its plate (#1101; before it, a red one lay there and went back
## with PickUp): its order served, its plate empty, and it refuses more, so the subtask is done
## once.
func test_a_done_place_holds_nothing_and_refuses_more() -> void:
	FixtureCookingModes.cook(_game, P1, 0)
	var order := _order(0)
	assert_bool(order.done).is_true()
	assert_array([order.bun_item, order.patty_item, order.herb_item]).is_equal([-1, -1, -1])
	FixtureCookingModes.take(_game, P1, order.bun.id)
	_use(P1, 0)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"unavailable"])
	assert_int(_game.view_of(P2).events_named(&"TaskProgress").size()).is_equal(2)


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


## Before #1101 a wrong bun lay at the place and vanished in its time; now every plated item is
## locked, so neither a carried nor a plated one vanishes, however long.
func test_a_bun_carried_past_its_time_and_plated_never_vanishes() -> void:
	var order := _order(0)
	FixtureCookingModes.take(_game, P1, _other_bun(order).id)
	var bun := FixtureCookingModes.held(_game, P1)
	var vanish := Ticks.from_seconds(FixtureCookingModes.VANISH)
	# Carried for longer than it may lie: a held item does not lie.
	FixtureModes.run_ticks(_game, vanish + 100)
	assert_bool(_game.state.items.has(bun.id)).is_true()
	_use(P1, 0)
	FixtureModes.run_ticks(_game, vanish + 100)
	assert_bool(_game.state.items.has(bun.id)).is_true()
	assert_int(bun.where).is_equal(ItemState.Where.LOCKED)


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
