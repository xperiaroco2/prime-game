extends GdUnitTestSuite
## Items (ARCHITECTURE §7.1, §9.2, §9.4): the drop of a dying or leaving player's items, the
## hand's first, then the belt's, to the floor below its last accepted position (the function the
## life rule, 2g, calls), item_rested at a spawn, `Use` with a package in hand, and the mode check
## of the item parts. The drop is driven by FixtureDropHeld on a `Use` of the mode, standing in for
## 2g's player_died and player_left.

const P1 := 1
const P2 := 2
const HERE := Vector3.ZERO


func test_a_death_drops_the_held_item_to_the_floor_below() -> void:
	var game := _holding_with_drop(Items.DEATH, FlatWorldQuery.new())
	var item := game.state.items[1]
	# A jump: the last accepted position is in mid-air.
	FixtureItemModes.stand(game, P1, Vector3(3, 0.9, 3))
	var seen := game.view_of(P2).events.size()
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DOWNED)
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
	# The dead are still players: the downed player learns where its item fell, like everyone.
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


func test_a_death_drops_both_slots_the_hand_first() -> void:
	var game := FixtureItemModes.in_round(_with_drop(Items.DEATH), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	var belted := FixtureItemModes.lay(game, &"tool", HERE)
	var held := FixtureItemModes.lay(game, &"package", HERE)
	FixtureItemModes.pick_up(game, P1, belted)
	FixtureItemModes.pick_up(game, P1, held)
	var seen := game.view_of(P2).events.size()
	FixtureModes.send(game, Intents.USE, P1)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(-1)
	assert_int(player.belt_item).is_equal(-1)
	assert_int(belted.where).is_equal(ItemState.Where.GROUND)
	assert_int(held.where).is_equal(ItemState.Where.GROUND)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[
			&"ItemPlaced",
			&"FixtureNote",
			&"FixtureNote",
			&"ItemPlaced",
			&"FixtureNote",
			&"FixtureNote"
		]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")
	assert_int((placed[0] as ItemPlacedEvent).item).is_equal(held.id)
	assert_int((placed[1] as ItemPlacedEvent).item).is_equal(belted.id)
	assert_str(String((placed[1] as ItemPlacedEvent).cause)).is_equal("death")


func test_a_leave_drops_a_lone_belt_item() -> void:
	var game := FixtureItemModes.in_round(
		FixtureItemModes.swapping(_with_drop(Items.LEAVE)), [P1, P2]
	)
	FixtureItemModes.stand(game, P1, HERE)
	var tool := FixtureItemModes.lay(game, &"tool", HERE)
	FixtureItemModes.pick_up(game, P1, tool)
	FixtureItemModes.swap(game, P1)
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).belt_item).is_equal(-1)
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")
	assert_dict(placed[0].to_dict()).is_equal(
		{"item": tool.id, "position": HERE, "cause": &"leave"}
	)


func test_an_empty_hand_drops_nothing() -> void:
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.DEATH)]))
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DOWNED)
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


func test_a_downed_player_cannot_use() -> void:
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1])
	game.state.player(P1).life = PlayerState.Life.DOWNED
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


func test_the_eye_stands_on_the_footprint_and_a_drop_asks_one_ray() -> void:
	# E10 (b): the player's standing (the eye of InSight) asks the capsule's footprint; the drop of
	# its item asks one ray below it, as for any item or body.
	var world := FixtureLevelWorld.new()
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.LEAVE)]))
	var game := FixtureItemModes.in_round(mode, [P1, P2], world)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	var package := FixtureItemModes.lay(game, &"package", Vector3.ZERO)
	world.calls.clear()
	FixtureItemModes.pick_up(game, P1, package)
	assert_int(game.state.player(P1).held_item).is_equal(package.id)
	assert_array(Array(world.calls)).is_equal(["stand_floor_below"])
	world.calls.clear()
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(Array(world.calls)).is_equal(["floor_below"])


func test_a_launch_takes_the_item_out_of_the_hand_into_its_flight() -> void:
	var game := FixtureItemModes.in_round(FixtureFlightModes.basic(), [P1, P2])
	var item := FixtureFlightModes.holding(game, P1, Vector3(2, 0, 3))
	var seen := game.view_of(P2).events.size()
	var launch_tick := game.ticked_through() + 1
	FixtureFlightModes.throw(game, P1, Vector3(0, 0, -4))
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_int(item.holder).is_equal(0)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	var flight := item.flight
	assert_object(flight).is_not_null()
	assert_vector(flight.origin).is_equal(Vector3(2, 1.6, 3))
	assert_vector(item.position).is_equal(flight.origin)
	assert_vector(flight.velocity).is_equal(Vector3(0, 0, -10))
	assert_vector(flight.gravity).is_equal(Vector3(0, -9.8, 0))
	assert_vector(flight.fallback).is_equal(Vector3(2, 0, 3))
	assert_int(flight.thrower).is_equal(P1)
	assert_int(flight.ticks).is_equal(0)
	assert_int(flight.launch_tick).is_equal(launch_tick)
	# The launch announces nothing: the throw's own effect does (37c).
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()


func test_the_fallback_rest_is_the_floor_below_the_feet() -> void:
	var world := FixtureTerrainWorld.new().add_platform(-1, -1, 1, 1, 0.5)
	var game := FixtureItemModes.in_round(FixtureFlightModes.basic(), [P1], world)
	# Feet a hair under the platform's top still find it (lifted, as for a drop).
	var item := FixtureFlightModes.holding(game, P1, Vector3(0.5, 0.49, 0))
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	assert_vector(item.flight.fallback).is_equal(Vector3(0.5, 0.5, 0))


func test_an_item_in_flight_rests_on_no_marker() -> void:
	var mode := FixtureFlightModes.basic()
	# Each throw then notes the markers a deal would count as free.
	mode.actions[-1].effects.append(FixtureFreeMarkers.of(&"round_player"))
	var game := FixtureItemModes.in_round(mode, [P1])
	var item := FixtureFlightModes.holding(game, P1, Vector3(-3, 0, 0))
	FixtureFlightModes.throw(game, P1, Vector3.FORWARD)
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	# A flight launched right over a marker: its position is the origin, not a rest.
	item.flight.origin = Vector3(10, 0, 5)
	item.position = item.flight.origin
	FixtureFlightModes.holding(game, P1, Vector3(-3, 0, 0))
	FixtureFlightModes.throw(game, P1, Vector3.FORWARD)
	var markers := game.layout(FixtureModes.MAP).positions(&"round_player")
	assert_bool(markers.has(item.position)).is_true()
	assert_str(FixtureModes.notes(game)[-1]).is_equal(
		FixtureFreeMarkers.text(&"round_player", markers)
	)


func test_an_item_in_flight_cannot_be_picked_up() -> void:
	var game := FixtureItemModes.in_round(FixtureFlightModes.basic(), [P1, P2])
	var item := FixtureFlightModes.holding(game, P1, Vector3.ZERO)
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	FixtureItemModes.stand(game, P2, Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P2, item)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_int(game.state.player(P2).held_item).is_equal(-1)


func test_the_snapshot_shows_an_item_in_flight_at_its_origin_to_everyone() -> void:
	var game := FixtureItemModes.in_round(FixtureFlightModes.basic(), [P1, P2])
	var item := FixtureFlightModes.holding(game, P1, Vector3(1, 0, 1))
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	for viewer: int in [P1, P2]:
		var items: Dictionary = (
			Snapshots.for_peer(game.state, viewer, game.ticked_through())["items"]
		)
		assert_dict(items[item.id]).is_equal(
			{"where": ItemState.Where.FLYING, "holder": 0, "position": Vector3(1, 1.6, 1)}
		)


## The fixture item mode whose `Use` drops the actor's items for `cause`.
func _with_drop(cause: StringName) -> GameMode:
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(cause)]))
	return mode


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
