extends GdUnitTestSuite
## Cooking's grill (core/tasks/cooking.gd; the cooking ADR's §2.4, §4, CE4, CE10, CE13, #773):
## Interact on the grill puts a raw patty on (locked, GrillLoaded with its fried and burnt ticks)
## or takes the patty off (Items.give, which makes room); Cooking.tick turns it fried, then burnt;
## its refusals (`empty_hand`, `two_handed`, `wrong_item`), driven by commands through a seeded
## Match on FixtureCookingModes (fried after 20 ticks, burnt 40 later: fixture values).

const P1 := 1
const P2 := 2
const FRIED := 20
const BURNT := 60

var _game: Match


func before_test() -> void:
	_game = FixtureCookingModes.in_round(FixtureCookingModes.basic(), [P1, P2])


func test_a_raw_patty_goes_on_the_empty_grill_locked_with_its_ticks() -> void:
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	var at := _game.ticked_through() + 1
	_use(P1)
	var grill := _game.state.stations[_grill()]
	assert_int(patty.where).is_equal(ItemState.Where.LOCKED)
	assert_int(patty.holder).is_equal(0)
	assert_vector(patty.position).is_equal(grill.position)
	assert_int(_game.state.player(P1).held_item).is_equal(-1)
	var task_state := FixtureCookingModes.state_of(_game)
	assert_int(task_state.grill_item).is_equal(patty.id)
	var loaded := {"station": grill.id, "item": patty.id, "fried": at + FRIED, "burnt": at + BURNT}
	for peer: int in [P1, P2]:
		assert_array(FixtureCookingModes.dicts(_game, peer, &"GrillLoaded")).is_equal([loaded])


func test_the_patty_turns_fried_at_its_fried_tick_and_burnt_at_its_burnt_tick() -> void:
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	var at := _game.ticked_through() + 1
	_use(P1)
	_run_through(at + FRIED - 1)
	assert_str(patty.kind.id).is_equal("raw_a")
	_run_through(at + FRIED)
	assert_str(patty.kind.id).is_equal("fried_a")
	_run_through(at + BURNT - 1)
	assert_str(patty.kind.id).is_equal("fried_a")
	_run_through(at + BURNT)
	assert_str(patty.kind.id).is_equal("burnt")
	# Left there, it stays burnt on the grill: no more changes.
	FixtureModes.run_ticks(_game, 100)
	assert_int(patty.where).is_equal(ItemState.Where.LOCKED)
	var changed: Array[Dictionary] = [
		{"item": patty.id, "kind": &"fried_a"}, {"item": patty.id, "kind": &"burnt"}
	]
	for peer: int in [P1, P2]:
		assert_array(FixtureCookingModes.dicts(_game, peer, &"ItemChanged")).is_equal(changed)


func test_a_patty_taken_off_before_its_fried_tick_is_raw_and_starts_from_0_again() -> void:
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	var at := _game.ticked_through() + 1
	_use(P1)
	_run_through(at + FRIED - 2)
	# Taken off by a command in the tick before its fried tick.
	_use(P1)
	assert_int(_game.ticked_through() + 1).is_equal(at + FRIED - 1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(patty)
	assert_str(patty.kind.id).is_equal("raw_a")
	assert_int(FixtureCookingModes.state_of(_game).grill_item).is_equal(-1)
	FixtureModes.run_ticks(_game, 30)
	assert_str(patty.kind.id).is_equal("raw_a")
	var again := _game.ticked_through() + 1
	_use(P1)
	var loads := FixtureCookingModes.dicts(_game, P2, &"GrillLoaded")
	assert_int(loads.size()).is_equal(2)
	assert_int(loads[1]["fried"]).is_equal(again + FRIED)
	assert_int(loads[1]["burnt"]).is_equal(again + BURNT)


func test_the_take_off_gives_the_patty_whatever_its_kind_through_items_give() -> void:
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	_use(P1)
	_run_through(_game.ticked_through() + BURNT + 1)
	_take(P2, &"bun_a")
	var bun := FixtureCookingModes.held(_game, P2)
	var seen := _game.view_of(P1).events.size()
	_use(P2)
	# The bun to the empty belt, the burnt patty into the hand: ItemPickedUp with `belted`.
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(patty)
	assert_object(FixtureCookingModes.belted(_game, P2)).is_same(bun)
	assert_str(patty.kind.id).is_equal("burnt")
	assert_array(FixtureItemModes.names_after(_game, P1, seen)).is_equal([&"ItemPickedUp"])
	var picked := _game.view_of(P1).events_named(&"ItemPickedUp")[-1].to_dict()
	assert_int(picked["item"]).is_equal(patty.id)
	assert_int(picked["belted"]).is_equal(bun.id)
	assert_int(FixtureCookingModes.state_of(_game).grill_item).is_equal(-1)


func test_two_presses_in_one_tick_load_then_take_off() -> void:
	_take(P1, &"raw_a")
	_take(P2, &"raw_b")
	FixtureModes.run_ticks(_game, 1)
	var first := FixtureCookingModes.held(_game, P1)
	var second := FixtureCookingModes.held(_game, P2)
	var at := _game.ticked_through() + 1
	_use(P1)
	_use(P2)
	assert_int(_game.ticked_through()).is_equal(at - 1)
	# The second press found the grill occupied and took P1's patty off; its own raw patty went to
	# its empty belt.
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(first)
	assert_object(FixtureCookingModes.belted(_game, P2)).is_same(second)
	assert_int(FixtureCookingModes.state_of(_game).grill_item).is_equal(-1)
	assert_int(FixtureCookingModes.dicts(_game, P1, &"GrillLoaded").size()).is_equal(1)


func test_a_take_off_with_a_full_belt_puts_the_hand_item_down_at_the_feet_first() -> void:
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	_use(P1)
	FixtureModes.run_ticks(_game, 1)
	_take(P2, &"bun_a")
	_take(P2, &"bun_b")
	# All three places full (GDD §6): the hand item goes to the feet.
	_take(P2, &"bun_a")
	FixtureModes.run_ticks(_game, 1)
	var hand := FixtureCookingModes.held(_game, P2)
	var belt := FixtureCookingModes.belted(_game, P2)
	var seen := _game.view_of(P1).events.size()
	_use(P2)
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(patty)
	assert_object(FixtureCookingModes.belted(_game, P2)).is_same(belt)
	assert_int(hand.where).is_equal(ItemState.Where.GROUND)
	# The fixture's note on item_rested comes between: the put-down rested first (CE13).
	assert_array(FixtureItemModes.names_after(_game, P1, seen)).is_equal(
		[&"ItemPlaced", &"FixtureNote", &"ItemPickedUp"]
	)


func test_a_box_carrier_takes_the_patty_off_onto_the_belt_and_keeps_the_box() -> void:
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	_use(P1)
	FixtureModes.run_ticks(_game, 1)
	var box := _carry_box(P2)
	_use(P2)
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(box)
	assert_object(FixtureCookingModes.belted(_game, P2)).is_same(patty)
	var picked := _game.view_of(P2).events_named(&"ItemPickedUp")[-1].to_dict()
	assert_int(picked["item"]).is_equal(patty.id)
	assert_int(picked["belted"]).is_equal(patty.id)
	assert_int(FixtureCookingModes.state_of(_game).grill_item).is_equal(-1)


func test_a_box_carrier_at_an_empty_grill_is_refused_two_handed() -> void:
	var box := _carry_box(P2)
	_use(P2)
	assert_array(FixtureModes.rejections(_game, P2)).is_equal([&"two_handed"])
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(box)
	assert_int(FixtureCookingModes.dicts(_game, P2, &"GrillLoaded").size()).is_equal(0)


func test_an_empty_hand_at_an_empty_grill_is_refused_empty_hand() -> void:
	_use(P1)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"empty_hand"])


func test_a_fried_or_burnt_patty_or_a_knife_at_an_empty_grill_is_refused_wrong_item() -> void:
	var fried := FixtureCookingModes.fry(_game, P1, &"raw_a")
	FixtureModes.run_ticks(_game, 1)
	assert_str(fried.kind.id).is_equal("fried_a")
	_use(P1)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(fried)
	_take(P2, &"raw_b")
	var burnt := FixtureCookingModes.held(_game, P2)
	_use(P2)
	_run_through(_game.ticked_through() + BURNT + 1)
	_use(P2)
	FixtureModes.run_ticks(_game, 1)
	assert_str(burnt.kind.id).is_equal("burnt")
	_use(P2)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(burnt)
	var knife := FixtureCombatModes.arm(_game, P2, Vector3(12, 0, 5))
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(knife)
	_use(P2)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"wrong_item"])
	assert_array(FixtureModes.rejections(_game, P2)).is_equal([&"wrong_item", &"wrong_item"])
	assert_int(FixtureCookingModes.dicts(_game, P1, &"GrillLoaded").size()).is_equal(2)


func _grill() -> int:
	return FixtureCookingModes.grill_of(_game)


func _use(peer: int) -> void:
	FixtureCookingModes.use(_game, peer, _grill())


func _take(peer: int, kind_id: StringName) -> void:
	FixtureCookingModes.take(_game, peer, kind_id)


## Runs ticks until the match has ticked through `tick`.
func _run_through(tick: int) -> void:
	FixtureModes.run_ticks(_game, tick - _game.ticked_through())


## `peer` picks up the box of `bun_b` (two-handed) and holds it. Returns it.
func _carry_box(peer: int) -> ItemState:
	var box := FixtureCookingModes.box_giving(_game, &"bun_b")
	FixtureItemModes.stand(_game, peer, box.position + Vector3(0, 0, 1))
	FixtureItemModes.pick_up(_game, peer, box)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, peer)).is_same(box)
	return box


func test_a_patty_taken_off_the_grill_and_put_down_counts_its_vanish_time_from_the_put_down(
) -> void:
	_game.mode.find_item_kind(&"raw_a").actions = [FixtureItemModes.put_down_rule(1.0)]
	_take(P1, &"raw_a")
	var patty := FixtureCookingModes.held(_game, P1)
	_use(P1)
	assert_int(patty.where).is_equal(ItemState.Where.LOCKED)
	FixtureModes.run_ticks(_game, 5)
	_use(P1)
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(patty)
	assert_int(patty.rest_tick).is_equal(-1)
	var vanish := Ticks.from_seconds(FixtureCookingModes.VANISH)
	# Carried for longer than it may lie: the time starts at the put down, not at the take.
	FixtureModes.run_ticks(_game, vanish + 100)
	assert_bool(_game.state.items.has(patty.id)).is_true()
	FixtureItemModes.put_down(_game, P1, Vector3(0, 0, -1))
	assert_int(patty.where).is_equal(ItemState.Where.GROUND)
	var laid := patty.rest_tick
	assert_int(laid).is_equal(_game.ticked_through() + 1)
	_run_through(laid + vanish - 1)
	assert_bool(_game.state.items.has(patty.id)).is_true()
	_run_through(laid + vanish)
	assert_bool(_game.state.items.has(patty.id)).is_false()
