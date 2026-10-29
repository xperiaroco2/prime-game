extends GdUnitTestSuite
## Cooking's herb beds (core/tasks/cooking.gd; the cooking ADR's §2.3, §4, CD3 (b), CE2, CE3, #773):
## Interact on a bed gives a new item of the bed's herb of the round, spawned at the bed
## (GiveItem.give_new: ItemSpawned, then Items.give, which makes room: the hand item to the belt, a
## full belt's item to the feet first; a box carrier's herb onto the belt with the box kept). At the
## herb's cap the loose one that lay longest vanishes first; with none loose the use is refused
## `unavailable` and nothing is spawned. Driven by commands through a seeded Match on
## FixtureCookingModes.

const P1 := 1
const P2 := 2
const AWAY := Vector3(30, 0, 30)

var _game: Match


func before_test() -> void:
	_game = FixtureCookingModes.in_round(FixtureCookingModes.basic(), [P1, P2])


func test_each_bed_gives_its_herb_of_the_round_spawned_at_the_bed() -> void:
	# One picker per bed, each with empty hands; P2 watches.
	var pickers: Array[int] = [P1, 3, 4]
	_game = FixtureCookingModes.in_round(FixtureCookingModes.basic(), [P1, P2, 3, 4])
	var task_state := FixtureCookingModes.state_of(_game)
	assert_int(task_state.beds.size()).is_equal(pickers.size())
	for i in task_state.beds.size():
		var bed := _game.state.stations[task_state.beds[i]]
		var herb := task_state.bed_herbs[i]
		var seen := _game.view_of(P2).events.size()
		FixtureCookingModes.use(_game, pickers[i], bed.id)
		var made := FixtureCookingModes.held(_game, pickers[i])
		assert_object(made).is_not_null()
		assert_object(made.kind).is_same(herb)
		# No item_rested note between: a given herb never lies (CE2).
		assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal(
			[&"ItemSpawned", &"ItemPickedUp"]
		)
		var spawned := _game.view_of(P2).events_named(&"ItemSpawned")[-1].to_dict()
		assert_dict(spawned).is_equal({"item": made.id, "kind": herb.id, "position": bed.position})
		FixtureModes.run_ticks(_game, 1)
	for peer: int in pickers:
		assert_array(FixtureModes.rejections(_game, peer)).is_empty()
	assert_array(Array(_game.diagnostics)).is_empty()


func test_a_one_handed_hand_item_goes_to_the_empty_belt() -> void:
	FixtureCookingModes.take(_game, P1, &"bun_a")
	var bun := FixtureCookingModes.held(_game, P1)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.pick(_game, P1, &"herb_b")
	var herb := FixtureCookingModes.held(_game, P1)
	assert_str(herb.kind.id).is_equal("herb_b")
	assert_object(FixtureCookingModes.belted(_game, P1)).is_same(bun)
	var picked := _game.view_of(P1).events_named(&"ItemPickedUp")[-1].to_dict()
	assert_int(picked["item"]).is_equal(herb.id)
	assert_int(picked["belted"]).is_equal(bun.id)


func test_a_box_carrier_s_herb_goes_onto_the_belt_and_the_box_stays_in_the_hand() -> void:
	var box := _carry_box(P2)
	FixtureCookingModes.pick(_game, P2, &"herb_c")
	var herb := FixtureCookingModes.belted(_game, P2)
	assert_object(herb).is_not_null()
	assert_str(herb.kind.id).is_equal("herb_c")
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(box)
	var picked := _game.view_of(P2).events_named(&"ItemPickedUp")[-1].to_dict()
	assert_int(picked["item"]).is_equal(herb.id)
	assert_int(picked["belted"]).is_equal(herb.id)


func test_a_box_carrier_with_a_full_belt_puts_the_belt_item_down_at_the_feet_first() -> void:
	FixtureCookingModes.take(_game, P2, &"bun_a")
	var bun := FixtureCookingModes.held(_game, P2)
	# Both belt places full (GDD §6): the first bun on the lower one, which goes down.
	FixtureCookingModes.take(_game, P2, &"bun_b")
	FixtureModes.run_ticks(_game, 1)
	var box := _carry_box(P2)
	assert_object(FixtureCookingModes.belted(_game, P2)).is_same(bun)
	var seen := _game.view_of(P1).events.size()
	FixtureCookingModes.pick(_game, P2, &"herb_a")
	assert_object(FixtureCookingModes.held(_game, P2)).is_same(box)
	assert_str(FixtureCookingModes.belted(_game, P2).kind.id).is_equal("herb_a")
	assert_int(bun.where).is_equal(ItemState.Where.GROUND)
	# The fixture's note on item_rested comes between: the put-down rested first (CE13).
	assert_array(FixtureItemModes.names_after(_game, P1, seen)).is_equal(
		[&"ItemSpawned", &"ItemPlaced", &"FixtureNote", &"ItemPickedUp"]
	)


func test_at_the_cap_the_loose_herb_that_lay_longest_vanishes_first() -> void:
	var herb := _game.mode.find_item_kind(&"herb_a")
	var loose := FixtureItemModes.lay(_game, &"herb_a", AWAY)
	loose.rest_tick = 0
	_lay_locked(&"herb_a", FixtureCookingModes.CAP - 1)
	var seen := _game.view_of(P2).events.size()
	FixtureCookingModes.pick(_game, P1, &"herb_a")
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_equal(
		[&"ItemVanished", &"ItemSpawned", &"ItemPickedUp"]
	)
	assert_bool(_game.state.items.has(loose.id)).is_false()
	assert_object(FixtureCookingModes.held(_game, P1).kind).is_same(herb)
	assert_int(_count(herb)).is_equal(FixtureCookingModes.CAP)


func test_at_the_cap_with_none_loose_the_bed_is_refused_unavailable_and_spawns_nothing() -> void:
	var herb := _game.mode.find_item_kind(&"herb_a")
	_lay_locked(&"herb_a", FixtureCookingModes.CAP)
	var seen := _game.view_of(P2).events.size()
	FixtureCookingModes.pick(_game, P1, &"herb_a", 4)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_empty()
	assert_object(FixtureCookingModes.held(_game, P1)).is_null()
	assert_int(_count(herb)).is_equal(FixtureCookingModes.CAP)
	# Another bed's herb is under its cap: it still gives.
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.pick(_game, P1, &"herb_b", 5)
	assert_str(FixtureCookingModes.held(_game, P1).kind.id).is_equal("herb_b")
	assert_array(Array(_game.diagnostics)).is_empty()


## `count` items of `kind_id` laid away and locked (none of them loose), straight in the state.
func _lay_locked(kind_id: StringName, count: int) -> void:
	for i in count:
		var item := FixtureItemModes.lay(_game, kind_id, AWAY + Vector3(i, 0, 0))
		item.where = ItemState.Where.LOCKED


func _count(kind: ItemKind) -> int:
	var count := 0
	for item: ItemState in _game.state.items.values():
		if item.kind == kind:
			count += 1
	return count


## `peer` picks up the box of `bun_b` (two-handed) and holds it. Returns it.
func _carry_box(peer: int) -> ItemState:
	var box := FixtureCookingModes.box_giving(_game, &"bun_b")
	FixtureItemModes.stand(_game, peer, box.position + Vector3(0, 0, 1))
	FixtureItemModes.pick_up(_game, peer, box)
	FixtureModes.run_ticks(_game, 1)
	assert_object(FixtureCookingModes.held(_game, peer)).is_same(box)
	return box


func test_a_second_pick_in_the_same_tick_is_refused_too_soon_and_the_next_tick_gives() -> void:
	FixtureCookingModes.pick(_game, P1, &"herb_a", 1)
	var herb := FixtureCookingModes.held(_game, P1)
	var seen := _game.view_of(P2).events.size()
	FixtureCookingModes.pick(_game, P1, &"herb_a", 2)
	assert_array(FixtureModes.rejections(_game, P1)).is_equal([&"too_soon"])
	assert_array(FixtureItemModes.names_after(_game, P2, seen)).is_empty()
	assert_object(FixtureCookingModes.held(_game, P1)).is_same(herb)
	FixtureModes.run_ticks(_game, 1)
	FixtureCookingModes.pick(_game, P1, &"herb_a", 3)
	assert_object(FixtureCookingModes.held(_game, P1)).is_not_same(herb)
	assert_object(FixtureCookingModes.belted(_game, P1)).is_same(herb)
