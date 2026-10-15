extends GdUnitTestSuite
## Cooking's plated burger and its serving (core/tasks/cooking.gd; the cooking ADR's amendment of
## 2026-10-15, #1101): E on a full plate takes the burger (the three items vanish, a burger goes to
## the taker, then BurgerPlated); E on the order board with the burger serves it, checked only
## then against its place's order. Right: BurgerServed true, the order and the place done, the
## subtask done once; wrong: BurgerServed false and nothing else, the burger thrown away, made
## again whole. The board refuses `empty_hand`, `wrong_item` (no burger) and `unavailable` (a
## burger of a done order). Driven by commands through a seeded Match on FixtureCookingModes.

const P1 := 1
const P2 := 2

var _game: Match


func before_test() -> void:
	_game = FixtureCookingModes.in_round(FixtureCookingModes.basic(2), [P1, P2])


func test_a_full_plate_is_taken_as_a_burger_its_items_vanish_first() -> void:
	FixtureCookingModes.plate(_game, P1, 0)
	var order := _order(0)
	var plated := PackedInt32Array([order.bun_item, order.patty_item, order.herb_item])
	var kinds: Array[StringName] = []
	for item_id: int in plated:
		kinds.append(_game.state.items[item_id].kind.id)
	plated.sort()
	var seen := _game.view_of(P2).events.size()
	var burger := FixtureCookingModes.take_burger(_game, P1, 0)
	assert_object(burger).is_not_null()
	assert_str(burger.kind.id).is_equal("burger")
	(
		assert_array(FixtureItemModes.names_after(_game, P2, seen))
		. is_equal(
			[
				&"ItemVanished",
				&"ItemVanished",
				&"ItemVanished",
				&"ItemSpawned",
				&"ItemPickedUp",
				&"BurgerPlated",
			]
		)
	)
	var vanished: Array = []
	for dict: Dictionary in FixtureCookingModes.dicts(_game, P2, &"ItemVanished"):
		vanished.append(dict["item"])
	assert_array(vanished).is_equal(Array(plated))
	for item_id: int in plated:
		assert_bool(_game.state.items.has(item_id)).is_false()
	var made := {
		"item": burger.id,
		"station": _place(0),
		"bun": kinds[0],
		"patty": kinds[1],
		"herb": kinds[2],
	}
	assert_array(FixtureCookingModes.dicts(_game, P2, &"BurgerPlated")).is_equal([made])
	assert_array([order.bun_item, order.patty_item, order.herb_item]).is_equal([-1, -1, -1])
	assert_bool(order.done).is_false()


func test_the_taker_s_hand_item_goes_to_the_belt() -> void:
	FixtureCookingModes.plate(_game, P1, 0)
	FixtureCookingModes.take(_game, P1, _order(0).bun.id)
	var bun := FixtureCookingModes.held(_game, P1)
	var burger := FixtureCookingModes.take_burger(_game, P1, 0)
	assert_str(burger.kind.id).is_equal("burger")
	assert_object(FixtureCookingModes.belted(_game, P1)).is_same(bun)


func test_a_box_carrier_at_a_full_plate_is_refused_two_handed() -> void:
	FixtureCookingModes.plate(_game, P1, 0)
	var box := FixtureCookingModes.box_giving(_game, _order(0).bun.id)
	FixtureItemModes.stand(_game, P1, box.position + Vector3(0, 0, 1))
	FixtureItemModes.pick_up(_game, P1, box)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(box)
	FixtureCookingModes.take_burger(_game, P1, 0)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"two_handed"])
	assert_int(_order(0).bun_item).is_not_equal(-1)


func test_a_right_burger_served_completes_the_order_once() -> void:
	FixtureCookingModes.plate(_game, P1, 0)
	var burger := FixtureCookingModes.take_burger(_game, P1, 0)
	var seen := _game.view_of(P2).events.size()
	FixtureCookingModes.serve(_game, P1)
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal(
		[&"BurgerServed", &"ItemVanished", &"TaskState", &"TaskProgress"]
	)
	var served := {"station": _place(0), "right": true}
	for peer: int in [P1, P2]:
		assert_array(FixtureCookingModes.dicts(_game, peer, &"BurgerServed")).is_equal([served])
	assert_bool(_game.state.items.has(burger.id)).is_false()
	assert_object(FixtureCookingModes.held(_game, P1)).is_null()
	assert_bool(_order(0).done).is_true()
	assert_bool(_game.state.stations[_place(0)].done).is_true()
	assert_int(FixtureCookingModes.state_of(_game).done_count()).is_equal(1)
	assert_array(FixtureCookingModes.dicts(_game, P2, &"TaskProgress")[-1].values()).is_equal(
		[1, 2]
	)
	assert_bool(FixtureCookingModes.state_of(_game).burgers.is_empty()).is_true()


## Wrong in any one part: only "wrong" (no word of which part), the burger thrown away, the order
## not done; a right one made again whole then completes it.
func test_a_burger_wrong_in_any_part_is_thrown_away_and_made_again_whole() -> void:
	for part: int in 3:
		before_test()
		var order := _order(0)
		var kinds: Array[StringName] = [order.bun.id, order.raw_patty.id, order.herb.id]
		kinds[part] = _other(part, kinds[part])
		for kind_id: StringName in kinds:
			FixtureCookingModes.put(_game, P1, 0, kind_id)
		var burger := FixtureCookingModes.take_burger(_game, P1, 0)
		var seen := _game.view_of(P2).events.size()
		FixtureCookingModes.serve(_game, P1)
		assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal(
			[&"BurgerServed", &"ItemVanished"]
		)
		var served := {"station": _place(0), "right": false}
		assert_array(FixtureCookingModes.dicts(_game, P2, &"BurgerServed")).is_equal([served])
		assert_bool(_game.state.items.has(burger.id)).is_false()
		assert_bool(order.done).is_false()
		assert_bool(_game.state.stations[_place(0)].done).is_false()
		assert_int(_game.view_of(P2).events_named(&"TaskProgress").size()).is_equal(1)
		FixtureCookingModes.cook(_game, P1, 0)
		assert_bool(order.done).is_true()
		assert_int(_game.view_of(P2).events_named(&"TaskProgress").size()).is_equal(2)


func test_the_board_refuses_an_empty_hand_and_anything_but_a_burger() -> void:
	FixtureCookingModes.serve(_game, P1)
	FixtureCookingModes.take(_game, P1, _order(0).bun.id)
	var bun := FixtureCookingModes.held(_game, P1)
	FixtureCookingModes.serve(_game, P1)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"empty_hand", &"wrong_item"])
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(bun)
	assert_int(_game.view_of(P2).events_named(&"BurgerServed").size()).is_equal(0)


## Two burgers plated for one order: the first served right does it; the second is refused
## `unavailable` and stays in its hand.
func test_a_burger_of_a_done_order_is_refused_unavailable_and_kept() -> void:
	FixtureCookingModes.plate(_game, P1, 0)
	FixtureCookingModes.take_burger(_game, P1, 0)
	FixtureCookingModes.plate(_game, P2, 0)
	var second := FixtureCookingModes.take_burger(_game, P2, 0)
	FixtureCookingModes.serve(_game, P1)
	assert_bool(_order(0).done).is_true()
	FixtureCookingModes.serve(_game, P2)
	assert_array(FixtureModes.rejections(_game, P2)).is_equal([&"unavailable"])
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(second)
	assert_int(_game.view_of(P1).events_named(&"BurgerServed").size()).is_equal(1)


## A plate filled again while its burger is carried: served right, the refill vanishes (ascending
## id) and the done place is empty.
func test_a_right_serve_clears_a_refilled_plate() -> void:
	FixtureCookingModes.plate(_game, P1, 0)
	FixtureCookingModes.take_burger(_game, P1, 0)
	FixtureCookingModes.plate(_game, P2, 0)
	var order := _order(0)
	var refill := PackedInt32Array([order.bun_item, order.patty_item, order.herb_item])
	refill.sort()
	var seen := _game.view_of(P2).events.size()
	FixtureCookingModes.serve(_game, P1)
	(
		assert_array(FixtureItemModes.names_after(_game, P2, seen))
		. is_equal(
			[
				&"BurgerServed",
				&"ItemVanished",
				&"ItemVanished",
				&"ItemVanished",
				&"ItemVanished",
				&"TaskState",
				&"TaskProgress",
			]
		)
	)
	var vanished: Array = []
	for dict: Dictionary in FixtureCookingModes.dicts(_game, P2, &"ItemVanished").slice(-3):
		vanished.append(dict["item"])
	assert_array(vanished).is_equal(Array(refill))
	assert_array([order.bun_item, order.patty_item, order.herb_item]).is_equal([-1, -1, -1])
	assert_bool(order.done).is_true()


## Nothing about correctness before the serve (the amendment's rule 3): a right plate on place 0
## (by P1) and a wrong one on place 1 (by P2, so both start with empty hands), each filled and
## taken, reach both peers as the same events by name, and none of them carries a `right` field;
## only the serve tells, BurgerServed.
func test_no_event_tells_right_or_wrong_before_the_serve() -> void:
	var streams: Array[Array] = []
	for wrong: bool in [false, true]:
		var index := 1 if wrong else 0
		var cook := P2 if wrong else P1
		var order := _order(index)
		var kinds: Array[StringName] = [order.bun.id, order.raw_patty.id, order.herb.id]
		if wrong:
			kinds[2] = _other(2, kinds[2])
		var seen := {P1: _game.view_of(P1).events.size(), P2: _game.view_of(P2).events.size()}
		for kind_id: StringName in kinds:
			FixtureCookingModes.put(_game, cook, index, kind_id)
		FixtureCookingModes.take_burger(_game, cook, index)
		for peer: int in [P1, P2]:
			var events: Array = _game.view_of(peer).events.slice(seen[peer] as int)
			assert_array(events).is_not_empty()
			for event: MatchEvent in events:
				(
					assert_bool(event.to_dict().has("right"))
					. override_failure_message("%s tells right or wrong" % event.event_name())
					. is_false()
				)
			streams.append(FixtureItemModes.names_after(_game, peer, seen[peer] as int))
	assert_array(streams[2]).is_equal(streams[0])
	assert_array(streams[3]).is_equal(streams[1])
	assert_array(_game.view_of(P2).events_named(&"BurgerServed")).is_empty()


## A burger is checked against the order of the place it was plated on (decision 1 of the plan):
## place 1's right burger completes order 1 only.
func test_a_burger_serves_its_own_place_s_order() -> void:
	FixtureCookingModes.cook(_game, P1, 1)
	assert_bool(_order(1).done).is_true()
	assert_bool(_order(0).done).is_false()
	var served := {"station": _place(1), "right": true}
	assert_array(FixtureCookingModes.dicts(_game, P2, &"BurgerServed")).is_equal([served])


## A burger made on place 1 with order 0's parts is wrong, though order 0 is open and it matches
## order 0: it is checked against its own place's order only, never any open one.
func test_a_burger_matching_another_place_s_order_is_wrong() -> void:
	var other := _order(0)
	var own := _order(1)
	var kinds: Array[StringName] = [other.bun.id, other.raw_patty.id, other.herb.id]
	var mine: Array[StringName] = [own.bun.id, own.raw_patty.id, own.herb.id]
	assert_array(kinds).is_not_equal(mine)
	for kind_id: StringName in kinds:
		FixtureCookingModes.put(_game, P1, 1, kind_id)
	FixtureCookingModes.take_burger(_game, P1, 1)
	FixtureCookingModes.serve(_game, P1)
	var served := {"station": _place(1), "right": false}
	assert_array(FixtureCookingModes.dicts(_game, P2, &"BurgerServed")).is_equal([served])
	assert_bool(other.done).is_false()
	assert_bool(own.done).is_false()
	assert_int(FixtureCookingModes.state_of(_game).done_count()).is_equal(0)


func _order(index: int) -> Cooking.Order:
	return FixtureCookingModes.state_of(_game).orders[index]


func _place(index: int) -> int:
	return FixtureCookingModes.place_of(_game, index)


## Another kind of part `part` (0 bun, 1 raw patty, 2 herb) than `kind_id`.
func _other(part: int, kind_id: StringName) -> StringName:
	var type := FixtureCookingModes.type_of(_game.mode)
	var lists: Array[Array] = [type.buns, type.raw_patties, type.herbs]
	for kind: ItemKind in lists[part]:
		if kind.id != kind_id:
			return kind.id
	return &""
