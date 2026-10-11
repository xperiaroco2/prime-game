extends GdUnitTestSuite
## GiveItem (the cooking ADR's CE2, CE3, #770; ARCHITECTURE §9.4.2): an Interact naming a box on
## the ground runs the box kind's target action, which spawns a new bun at the box (ItemSpawned, no
## station) and gives it to the actor (Items.give: ItemPickedUp), with no item_rested for it. The
## cap: at `max_items` the loose bun that has lain longest vanishes first (ItemVanished; the
## earliest rest tick, then the lowest id); with none loose the take is refused `unavailable`,
## nothing spawned and nothing paid. A carried box answers `unavailable` (ItemOnGround). Driven by
## commands on a seeded FixtureGiveModes match; asserted on the events, view_of and the state.

const P1 := 1
const P2 := 2
## Two spots on the ground far from P1, where loose buns lie.
const AWAY_A := Vector3(14, 0, 9)
const AWAY_B := Vector3(15, 0, 9)


func test_a_take_spawns_a_bun_at_the_box_and_puts_it_into_the_hand() -> void:
	var game := FixtureGiveModes.in_round([P1, P2])
	var box := FixtureGiveModes.box_of(game)
	var seen := game.view_of(P2).events.size()
	FixtureGiveModes.interact_item(game, P1, box.id)
	var buns := FixtureGiveModes.ids_of(game, &"bun")
	assert_array(buns).has_size(1)
	var bun: ItemState = game.state.items[buns[0]]
	assert_int(game.state.player(P1).held_item).is_equal(bun.id)
	assert_int(bun.where).is_equal(ItemState.Where.HAND)
	assert_int(bun.rest_tick).is_equal(-1)
	# Everyone sees the new bun appear and taken; it never rested, so no item_rested note.
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPickedUp"]
	)
	var spawned := game.view_of(P2).events_named(&"ItemSpawned")[-1] as ItemSpawnedEvent
	assert_int(spawned.item).is_equal(bun.id)
	assert_str(String(spawned.kind)).is_equal("bun")
	assert_vector(spawned.position).is_equal(FixtureGiveModes.BOX_AT)
	assert_int(spawned.station).is_equal(-1)
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	# The box stays where it lay.
	assert_int(box.where).is_equal(ItemState.Where.GROUND)
	assert_array(Array(game.diagnostics)).is_empty()


func test_at_the_cap_the_loose_bun_that_lay_longest_vanishes_first() -> void:
	var game := FixtureGiveModes.in_round([P1, P2])
	var newer := FixtureGiveModes.lay_bun(game, AWAY_A, 30)
	var older := FixtureGiveModes.lay_bun(game, AWAY_B, 10)
	var seen := game.view_of(P2).events.size()
	FixtureGiveModes.interact_item(game, P1, FixtureGiveModes.box_of(game).id)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemVanished", &"ItemSpawned", &"ItemPickedUp"]
	)
	var vanished := game.view_of(P2).events_named(&"ItemVanished")[-1] as ItemVanishedEvent
	assert_int(vanished.item).is_equal(older.id)
	assert_bool(game.state.items.has(older.id)).is_false()
	assert_bool(game.state.items.has(newer.id)).is_true()
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).has_size(FixtureGiveModes.BUN_CAP)


func test_a_tie_on_the_rest_tick_vanishes_the_lowest_id() -> void:
	var game := FixtureGiveModes.in_round([P1, P2])
	var first := FixtureGiveModes.lay_bun(game, AWAY_A, 10)
	var second := FixtureGiveModes.lay_bun(game, AWAY_B, 10)
	FixtureGiveModes.interact_item(game, P1, FixtureGiveModes.box_of(game).id)
	assert_bool(game.state.items.has(first.id)).is_false()
	assert_bool(game.state.items.has(second.id)).is_true()


func test_with_no_bun_loose_the_take_is_refused_unavailable_and_pays_nothing() -> void:
	var mode := FixtureGiveModes.basic()
	var take := mode.find_item_kind(&"box").target_actions[0]
	var cooldown := Cooldown.new()
	cooldown.key = &"take"
	take.conditions.append(cooldown)
	var game := FixtureGiveModes.in_round([P1, P2], mode)
	var box := FixtureGiveModes.box_of(game)
	# Two takes: one bun in the hand, one on the belt; neither lies on the ground.
	FixtureGiveModes.interact_item(game, P1, box.id)
	FixtureModes.run_ticks(game, 1)
	FixtureGiveModes.interact_item(game, P1, box.id)
	var paid_at := game.state.cooldown_paid_at(P1, &"take")
	var held := FixtureGiveModes.ids_of(game, &"bun")
	assert_array(held).has_size(FixtureGiveModes.BUN_CAP)
	FixtureModes.run_ticks(game, 1)
	var seen := game.view_of(P2).events.size()
	FixtureGiveModes.interact_item(game, P1, box.id, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).is_equal(held)
	assert_int(game.state.cooldown_paid_at(P1, &"take")).is_equal(paid_at)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_carried_box_answers_unavailable() -> void:
	var game := FixtureGiveModes.in_round([P1, P2])
	var box := FixtureGiveModes.box_of(game)
	FixtureItemModes.pick_up(game, P1, box)
	assert_int(box.holder).is_equal(P1)
	FixtureItemModes.stand(game, P2, FixtureGiveModes.HERE)
	FixtureGiveModes.interact_item(game, P2, box.id, 3)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).is_empty()


func test_a_box_out_of_reach_answers_out_of_reach() -> void:
	var game := FixtureGiveModes.in_round([P1, P2])
	FixtureItemModes.stand(game, P1, AWAY_A)
	FixtureGiveModes.interact_item(game, P1, FixtureGiveModes.box_of(game).id, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).is_empty()


func test_a_wall_between_answers_blocked() -> void:
	var world := FlatWorldQuery.new()
	var game := FixtureGiveModes.in_round([P1, P2], null, world)
	world.add_wall(AABB(Vector3(10.4, 0, 4), Vector3(0.2, 3, 2)))
	FixtureGiveModes.interact_item(game, P1, FixtureGiveModes.box_of(game).id, 6)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"blocked"])
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).is_empty()


func test_the_refusals_come_in_their_order() -> void:
	# Each step clears the first refusal while every later one still holds.
	var world := FlatWorldQuery.new()
	var game := FixtureGiveModes.in_round([P1, P2], null, world)
	var box := FixtureGiveModes.box_of(game)
	FixtureItemModes.pick_up(game, P2, box, 1)
	FixtureItemModes.stand(game, P2, FixtureGiveModes.HERE)
	FixtureItemModes.pick_up(game, P2, box, 2)
	assert_int(box.holder).is_equal(P2)
	FixtureItemModes.put_down(game, P2, Vector3(1, 0, 0), 3)
	assert_int(box.where).is_equal(ItemState.Where.GROUND)
	# A wall on the box's far side (x + 0.5) cuts every line from the east.
	world.add_wall(AABB(box.position + Vector3(0.5, 0, -2), Vector3(0.2, 3, 4)))
	var east := box.position + Vector3(1.2, 0, 0)
	# Held: unavailable first, though the sender is far away and behind the wall.
	FixtureItemModes.pick_up(game, P2, box, 4)
	FixtureItemModes.stand(game, P1, AWAY_A)
	FixtureGiveModes.interact_item(game, P1, box.id, 1)
	FixtureItemModes.put_down(game, P2, Vector3(1, 0, 0), 5)
	# On the ground, far and behind the wall: out of reach before blocked.
	FixtureGiveModes.interact_item(game, P1, box.id, 2)
	FixtureItemModes.stand(game, P1, east)
	FixtureGiveModes.interact_item(game, P1, box.id, 3)
	world.walls.clear()
	FixtureGiveModes.interact_item(game, P1, box.id, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"unavailable", &"out_of_reach", &"blocked"]
	)
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).has_size(1)


func test_a_downed_or_dead_sender_naming_a_box_is_not_accepted() -> void:
	for life: PlayerState.Life in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD]:
		var game := FixtureGiveModes.in_round([P1, P2])
		game.state.player(P1).life = life
		FixtureGiveModes.interact_item(game, P1, FixtureGiveModes.box_of(game).id, 7)
		assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
		assert_array(FixtureGiveModes.ids_of(game, &"bun")).is_empty()
