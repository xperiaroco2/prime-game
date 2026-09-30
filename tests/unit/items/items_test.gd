extends GdUnitTestSuite
## Items (ARCHITECTURE §7.1, §9.2, §9.4): the drop of a dying or leaving player's held item to the
## floor below its last accepted position (the function the life rule, 2g, calls), item_rested at
## a spawn, `Use` with a package in hand, and the mode check of the item parts. The drop is
## driven by FixtureDropHeld on a `Use` of the mode, standing in for 2g's player_died and
## player_left.

const P1 := 1
const P2 := 2


func test_a_death_drops_the_held_item_to_the_floor_below() -> void:
	var game := _holding_with_drop(Items.DEATH, FlatWorldQuery.new())
	var item := game.state.items[1]
	# A jump: the last accepted position is in mid-air.
	FixtureItemModes.stand(game, P1, Vector3(3, 0.9, 3))
	var seen := game.view_of(P2).events.size()
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.GHOST)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_int(item.holder).is_equal(0)
	assert_vector(item.position).is_equal(Vector3(3, 0, 3))
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_dict(placed.to_dict()).is_equal(
		{"item": item.id, "position": Vector3(3, 0, 3), "cause": &"death"}
	)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureRestedNote.text(item.id, &"death", Vector3(3, 0, 3)), "task item_rested"]
	)
	# The dead are still players: the ghost learns where its item fell, like everyone.
	assert_array(game.view_of(P1).events_named(&"ItemPlaced")).has_size(1)


func test_a_leave_drops_it_and_the_leaver_is_told_nothing() -> void:
	var game := _holding_with_drop(Items.LEAVE, FlatWorldQuery.new())
	var item := game.state.items[1]
	FixtureItemModes.stand(game, P1, Vector3(-2, 0, 4))
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.LEFT)
	assert_vector(item.position).is_equal(Vector3(-2, 0, 4))
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_str(placed.cause).is_equal("leave")
	assert_array(game.view_of(P1).events_named(&"ItemPlaced")).is_empty()
	assert_array(FixtureModes.notes(game)).contains(
		[FixtureRestedNote.text(item.id, &"leave", Vector3(-2, 0, 4))]
	)


func test_a_drop_lands_on_the_floor_found_below() -> void:
	var game := _holding_with_drop(Items.DEATH, FlatWorldQuery.new(1.5))
	FixtureItemModes.stand(game, P1, Vector3(1, 2.2, 1))
	FixtureModes.send(game, Intents.USE, P1)
	assert_vector(game.state.items[1].position).is_equal(Vector3(1, 1.5, 1))


func test_a_drop_from_feet_a_hair_below_the_floor_still_finds_it() -> void:
	# The floor is asked from just above the feet (Items.lifted): feet that a float error put
	# under the floor, or a physics ray that starts on the floor, still find it.
	var game := _holding_with_drop(Items.DEATH, FlatWorldQuery.new())
	FixtureItemModes.stand(game, P1, Vector3(1, -0.001, 1))
	FixtureModes.send(game, Intents.USE, P1)
	assert_vector(game.state.items[1].position).is_equal(Vector3(1, 0, 1))
	assert_array(Array(game.diagnostics)).is_empty()


func test_with_no_floor_below_the_item_rests_where_the_player_was_and_it_is_logged() -> void:
	var game := _holding_with_drop(Items.DEATH, FlatWorldQuery.new(5.0))
	FixtureItemModes.stand(game, P1, Vector3(1, 0, 1))
	FixtureModes.send(game, Intents.USE, P1)
	assert_vector(game.state.items[1].position).is_equal(Vector3(1, 0, 1))
	assert_int(game.state.items[1].where).is_equal(ItemState.Where.GROUND)
	assert_str(game.diagnostics[0]).contains("no floor below")


func test_an_empty_hand_drops_nothing() -> void:
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.DEATH)]))
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.GHOST)
	assert_array(game.view_of(P2).events_named(&"ItemPlaced")).is_empty()
	assert_array(FixtureModes.notes(game)).is_empty()


func test_a_spawn_raises_item_rested_without_item_placed() -> void:
	var mode := FixtureItemModes.basic()
	var spawn := FixtureSpawnItem.new()
	spawn.kind = mode.find_item_kind(&"package")
	spawn.at = Vector3(4, 0, 4)
	mode.find_transition(&"lobby", &"all_ready").actions.append(spawn)
	var game := FixtureItemModes.in_round(mode, [P1])
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.items[1].where).is_equal(ItemState.Where.GROUND)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureRestedNote.text(1, &"spawn", Vector3(4, 0, 4)), "task item_rested"]
	)
	assert_array(game.view_of(P1).events_named(&"ItemPlaced")).is_empty()


func test_use_with_a_package_in_hand_is_nothing_to_do() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	var package := FixtureItemModes.lay(game, &"package", Vector3(1, 0, 0))
	FixtureItemModes.pick_up(game, P1, package)
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P1, tool)
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do", &"nothing_to_do"])
	assert_array(FixtureModes.notes(game)).contains(["tool used"])


func test_a_ghost_cannot_use() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1])
	game.state.player(P1).life = PlayerState.Life.GHOST
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])


func test_the_item_rules_pass_the_mode_check_without_warnings() -> void:
	var check := ModeCheck.run(FixtureItemModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_the_mode_check_refuses_a_reach_or_distance_the_data_did_not_set() -> void:
	var mode := FixtureItemModes.basic()
	mode.actions = [FixtureItemModes.pick_up_rule(0.0), FixtureItemModes.put_down_rule(0.0)]
	var errors := ModeCheck.run(mode).errors
	assert_str(";".join(errors)).contains("InReach reach_m is 0, outside 0.1 to 10")
	assert_str(";".join(errors)).contains("PutDownInFront distance_m is 0, outside 0.3 to 3")
	mode.actions = [FixtureItemModes.pick_up_rule(10.5), FixtureItemModes.put_down_rule(3.5)]
	errors = ModeCheck.run(mode).errors
	assert_str(";".join(errors)).contains("InReach reach_m is 10.5, outside 0.1 to 10")
	assert_str(";".join(errors)).contains("PutDownInFront distance_m is 3.5, outside 0.3 to 3")


## A round of P1 and P2 in `world` whose mode's `Use` drops the actor's held item for `cause`,
## with P1 holding item 1, a package.
func _holding_with_drop(cause: StringName, world: WorldQuery) -> Match:
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(cause)]))
	var game := FixtureItemModes.in_round(mode, [P1, P2], world)
	var at := Vector3(0, world.floor_below(Vector3(0, 100, 0)).y, 0)
	FixtureItemModes.stand(game, P1, at)
	FixtureItemModes.pick_up(game, P1, FixtureItemModes.lay(game, &"package", at))
	assert_int(game.state.player(P1).held_item).is_equal(1)
	return game
