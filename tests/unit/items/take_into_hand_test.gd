extends GdUnitTestSuite
## PickUp (ARCHITECTURE §7.1, §9.4): ItemOnGround, InReach and InSight from the host's position of
## the player, then TakeIntoHand, which swaps a held item onto the picked-up one's spot. Driven by
## commands through the fixture item mode; asserted on the events, view_of and the match state.

const P1 := 1
const P2 := 2
const HERE := Vector3(0, 0, 0)


func test_a_living_player_picks_up_an_item_within_reach() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	var item := FixtureItemModes.lay(game, &"package", Vector3(1.5, 0, 0))
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.pick_up(game, P1, item)
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	assert_int(item.holder).is_equal(P1)
	assert_int(game.state.player(P1).held_item).is_equal(item.id)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal([&"ItemPickedUp"])
	var picked := game.view_of(P2).events_named(&"ItemPickedUp")[0] as ItemPickedUpEvent
	assert_dict(picked.to_dict()).is_equal({"peer": P1, "item": item.id})
	assert_array(game.view_of(P1).events_named(&"ItemPickedUp")).has_size(1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_reach_is_measured_from_the_last_accepted_position_never_the_intent() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3(5, 0, 0))
	var item := FixtureItemModes.lay(game, &"package", HERE)
	var claim := {"item": item.id, "position": HERE}
	FixtureModes.send(game, Intents.PICK_UP, P1, claim, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	var rejected := game.view_of(P1).events_named(&"Rejected")[0] as RejectedEvent
	assert_int(rejected.seq).is_equal(4)
	assert_array(game.view_of(P2).events_named(&"Rejected")).is_empty()
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.state.player(P1).held_item).is_equal(-1)


func test_the_reach_includes_its_bound() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1])
	FixtureItemModes.stand(game, P1, HERE)
	var far := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 2.01))
	var edge := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 2))
	FixtureItemModes.pick_up(game, P1, far)
	FixtureItemModes.pick_up(game, P1, edge)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	assert_int(game.state.player(P1).held_item).is_equal(edge.id)


func test_a_wall_between_the_eye_and_the_item_blocks_it() -> void:
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(0.9, 0, -1), Vector3(0.2, 3, 2)))
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2], world)
	FixtureItemModes.stand(game, P1, HERE)
	var item := FixtureItemModes.lay(game, &"package", Vector3(1.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"blocked"])
	assert_array(game.view_of(P2).events_named(&"Rejected")).is_empty()
	assert_int(item.where).is_equal(ItemState.Where.GROUND)


func test_the_line_of_sight_starts_at_the_eye() -> void:
	# A low wall between the feet and the item, below the line from the eye (1.6 m) to it.
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(1.0, 0, -1), Vector3(0.1, 0.3, 2)))
	assert_bool(world.line_of_sight(HERE, Vector3(1.5, 0, 0))).is_false()
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1], world)
	FixtureItemModes.stand(game, P1, HERE)
	var item := FixtureItemModes.lay(game, &"package", Vector3(1.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(game.state.player(P1).held_item).is_equal(item.id)


func test_the_line_of_sight_ends_just_above_the_item() -> void:
	# The floor as a solid slab: a line that ends on the item's rest position touches it, so the
	# line ends just above it (Items.lifted), and the surface the item lies on does not block it.
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(-5, -1, -5), Vector3(10, 1, 10)))
	assert_bool(world.line_of_sight(Vector3(0, 1.6, 0), Vector3(1.5, 0, 0))).is_false()
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1], world)
	FixtureItemModes.stand(game, P1, HERE)
	var item := FixtureItemModes.lay(game, &"package", Vector3(1.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(game.state.player(P1).held_item).is_equal(item.id)


func test_the_eye_height_comes_from_the_mode() -> void:
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(1.0, 0, -1), Vector3(0.1, 0.3, 2)))
	var mode := FixtureItemModes.basic()
	mode.player_rules.eye_height_m = 0.1
	var game := FixtureItemModes.in_round(mode, [P1], world)
	FixtureItemModes.stand(game, P1, HERE)
	var item := FixtureItemModes.lay(game, &"package", Vector3(1.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"blocked"])


func test_a_held_locked_or_unknown_item_is_unavailable() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	FixtureItemModes.stand(game, P2, Vector3(0.5, 0, 0))
	var held := FixtureItemModes.lay(game, &"package", Vector3(1, 0, 0))
	FixtureItemModes.pick_up(game, P2, held)
	var locked := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1))
	locked.where = ItemState.Where.LOCKED
	FixtureItemModes.pick_up(game, P1, held)
	FixtureItemModes.pick_up(game, P1, locked)
	FixtureModes.send(game, Intents.PICK_UP, P1, {"item": 99})
	FixtureModes.send(game, Intents.PICK_UP, P1, {})
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"unavailable", &"unavailable", &"unavailable", &"unavailable"]
	)
	assert_int(held.holder).is_equal(P2)
	assert_int(locked.where).is_equal(ItemState.Where.LOCKED)
	assert_int(game.state.player(P1).held_item).is_equal(-1)


func test_the_conditions_run_in_order() -> void:
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(0.9, 0, -10), Vector3(0.2, 3, 20)))
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1], world)
	FixtureItemModes.stand(game, P1, HERE)
	var far_behind := FixtureItemModes.lay(game, &"package", Vector3(5, 0, 0))
	FixtureItemModes.pick_up(game, P1, far_behind)
	far_behind.where = ItemState.Where.LOCKED
	FixtureItemModes.pick_up(game, P1, far_behind)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach", &"unavailable"])


func test_a_full_hand_swaps_onto_the_picked_up_items_spot() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	var first := FixtureItemModes.lay(game, &"package", Vector3(1, 0, 0))
	var second := FixtureItemModes.lay(game, &"tool", Vector3(0, 0, 1.5))
	FixtureItemModes.pick_up(game, P1, first)
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.pick_up(game, P1, second)
	assert_int(game.state.player(P1).held_item).is_equal(second.id)
	assert_int(second.where).is_equal(ItemState.Where.HAND)
	assert_int(first.where).is_equal(ItemState.Where.GROUND)
	assert_int(first.holder).is_equal(0)
	assert_vector(first.position).is_equal(Vector3(0, 0, 1.5))
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemPickedUp", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_dict(placed.to_dict()).is_equal(
		{"item": first.id, "position": Vector3(0, 0, 1.5), "cause": &"swap"}
	)
	(
		assert_array(FixtureModes.notes(game))
		. is_equal(
			[
				FixtureRestedNote.text(first.id, &"swap", Vector3(0, 0, 1.5)),
				"task item_rested",
			]
		)
	)
	assert_array(game.view_of(P1).events_named(&"ItemPlaced")).has_size(1)


func test_a_ghost_cannot_pick_up() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P2, HERE)
	game.state.player(P2).life = PlayerState.Life.GHOST
	var item := FixtureItemModes.lay(game, &"package", Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P2, item, 3)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.state.player(P2).held_item).is_equal(-1)
	assert_array(game.view_of(P1).events_named(&"ItemPickedUp")).is_empty()


func test_the_held_item_shows_in_the_snapshots() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	var item := FixtureItemModes.lay(game, &"package", Vector3(1, 0, 0))
	FixtureItemModes.pick_up(game, P1, item)
	FixtureModes.run_ticks(game, 1)
	var at := game.ticked_through()
	var other: Dictionary = game.view_of(P2).snapshots[at]
	assert_int(other["avatars"][P1]["held_item"]).is_equal(item.id)
	assert_int(other["items"][item.id]["where"]).is_equal(ItemState.Where.HAND)
	assert_int(other["items"][item.id]["holder"]).is_equal(P1)
	var own: Dictionary = game.view_of(P1).snapshots[at]
	var own_avatars: Dictionary = own["avatars"]
	assert_bool(own_avatars.has(P1)).is_false()
	assert_int(own["items"][item.id]["holder"]).is_equal(P1)


func test_taking_an_item_that_is_not_on_the_ground_is_a_rule_error() -> void:
	# A mode whose PickUp forgot ItemOnGround must not take an item out of another hand.
	var mode := FixtureItemModes.basic()
	mode.actions[0].conditions = []
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	var item := FixtureItemModes.lay(game, &"package", HERE)
	FixtureItemModes.pick_up(game, P2, item)
	FixtureItemModes.pick_up(game, P1, item)
	assert_int(item.holder).is_equal(P2)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	assert_int(game.state.player(P2).held_item).is_equal(item.id)
	assert_array(game.view_of(P1).events_named(&"ItemPickedUp")).has_size(1)
	assert_str(game.diagnostics[0]).contains("is not on the ground for player 1")
