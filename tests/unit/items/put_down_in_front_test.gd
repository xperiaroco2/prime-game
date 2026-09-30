extends GdUnitTestSuite
## PutDown (ARCHITECTURE §7.1, §9.4): HoldsItem, then PutDownInFront, which places the held item
## along the horizontal facing from the host's position of the player, through WorldQuery: stopped
## before a wall and dropped to the floor. Driven by commands through the fixture item mode.

const P1 := 1
const P2 := 2
const HERE := Vector3(0, 0, 0)
const NORTH := Vector3(0, 0, -1)


func test_the_item_rests_its_distance_along_the_horizontal_facing() -> void:
	var game := _holding(FlatWorldQuery.new(), HERE)
	var item := game.state.items[1]
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.put_down(game, P1, Vector3(0, -0.5, -1))
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_int(item.holder).is_equal(0)
	assert_vector(item.position).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 1e-5)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_int(placed.item).is_equal(item.id)
	assert_str(placed.cause).is_equal("put_down")
	assert_vector(placed.position).is_equal(item.position)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureRestedNote.text(item.id, &"put_down", item.position), "task item_rested"]
	)
	assert_array(game.view_of(P1).events_named(&"ItemPlaced")).has_size(1)


func test_the_facing_gives_only_a_direction() -> void:
	var game := _holding(FlatWorldQuery.new(), Vector3(3, 0, 3))
	FixtureItemModes.put_down(game, P1, Vector3(0, 0, -50))
	assert_vector(game.state.items[1].position).is_equal_approx(
		Vector3(3, 0, 2), Vector3.ONE * 1e-5
	)


func test_a_wall_stops_the_item_before_it() -> void:
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(-1, 0, -0.6), Vector3(2, 3, 0.2)))
	var game := _holding(world, HERE)
	FixtureItemModes.put_down(game, P1, NORTH)
	var at := game.state.items[1].position
	assert_float(at.z).is_equal_approx(-0.4 + FlatWorldQuery.WALL_MARGIN, 1e-5)
	assert_float(at.y).is_equal(0.0)


func test_the_item_drops_to_the_floor_below() -> void:
	var game := _holding(FlatWorldQuery.new(0.5), Vector3(0, 1.4, 0))
	FixtureItemModes.put_down(game, P1, NORTH)
	assert_vector(game.state.items[1].position).is_equal_approx(
		Vector3(0, 0.5, -1), Vector3.ONE * 1e-5
	)


func test_the_placement_starts_at_the_eye() -> void:
	# A low wall in front of the feet but below the eye: the item goes over it and drops.
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(-1, 0, -0.6), Vector3(2, 0.3, 0.2)))
	var game := _holding(world, HERE)
	FixtureItemModes.put_down(game, P1, NORTH)
	assert_vector(game.state.items[1].position).is_equal_approx(
		Vector3(0, 0, -1), Vector3.ONE * 1e-5
	)


func test_a_jump_does_not_raise_the_eye_over_a_wall() -> void:
	# A 2.2 m partition in front: from the top of a jump (feet 1 m up) the eye would be 2.6 m and
	# the item would go over it. The eye is taken from the floor below, so the partition stops it.
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(-1, 0, -0.6), Vector3(2, 2.2, 0.2)))
	var game := _holding(world, HERE)
	FixtureItemModes.stand(game, P1, Vector3(0, 1, 0))
	FixtureItemModes.put_down(game, P1, NORTH)
	var at := game.state.items[1].position
	assert_float(at.z).is_equal_approx(-0.4 + FlatWorldQuery.WALL_MARGIN, 1e-5)
	assert_float(at.y).is_equal(0.0)


func test_a_facing_without_a_horizontal_direction_puts_it_at_the_feet() -> void:
	# Not finite: a probe on 4.7.2 showed Vector3.normalized() returns (0, 0, 0) for (NAN, 0, 1)
	# and (INF, 0, 0) too, so the effect's own is_finite() check does not change this result; the
	# test pins the outcome either way.
	for facing: Vector3 in [Vector3.DOWN, Vector3.ZERO, Vector3(NAN, 0, 1), Vector3(INF, 0, 0)]:
		var game := _holding(FlatWorldQuery.new(), Vector3(2, 0, 2))
		FixtureItemModes.put_down(game, P1, facing)
		# The put-down happened: a no-op would also leave the item's position at the feet.
		assert_int(game.state.items[1].where).is_equal(ItemState.Where.GROUND)
		assert_int(game.state.player(P1).held_item).is_equal(-1)
		assert_array(game.view_of(P2).events_named(&"ItemPlaced")).has_size(1)
		assert_array(game.view_of(P1).events_named(&"Rejected")).is_empty()
		assert_vector(game.state.items[1].position).is_equal(Vector3(2, 0, 2))
		assert_array(Array(game.diagnostics)).is_empty()


func test_the_distance_comes_from_the_rule() -> void:
	var mode := FixtureItemModes.basic()
	(mode.actions[1].effects[0] as PutDownInFront).distance_m = 2.5
	var game := _holding(FlatWorldQuery.new(), HERE, mode)
	FixtureItemModes.put_down(game, P1, Vector3(1, 0, 0))
	assert_vector(game.state.items[1].position).is_equal_approx(
		Vector3(2.5, 0, 0), Vector3.ONE * 1e-5
	)


func test_an_empty_hand_is_rejected_to_the_sender_only() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1, P2])
	FixtureItemModes.put_down(game, P1, NORTH, 6)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"empty_hand"])
	assert_array(game.view_of(P2).events_named(&"Rejected")).is_empty()
	assert_array(game.view_of(P2).events_named(&"ItemPlaced")).is_empty()


func test_a_ghost_cannot_put_down() -> void:
	var game := _holding(FlatWorldQuery.new(), HERE)
	var item := game.state.items[1]
	# As if the life rule had not dropped it yet: the allowlist still refuses the ghost.
	game.state.player(P1).life = PlayerState.Life.GHOST
	FixtureItemModes.put_down(game, P1, NORTH, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_int(item.holder).is_equal(P1)
	assert_array(game.view_of(P2).events_named(&"ItemPlaced")).is_empty()


## A round of P1 and P2 in `world`, with P1 standing at `at` and holding item 1, a package it
## picked up from its feet.
func _holding(world: WorldQuery, at: Vector3, mode: GameMode = null) -> Match:
	var game := FixtureItemModes.in_round(
		mode if mode != null else FixtureItemModes.basic(), [P1, P2], world
	)
	FixtureItemModes.stand(game, P1, at)
	var item := FixtureItemModes.lay(game, &"package", at)
	FixtureItemModes.pick_up(game, P1, item)
	assert_int(game.state.player(P1).held_item).is_equal(item.id)
	return game
