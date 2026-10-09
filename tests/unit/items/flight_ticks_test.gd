extends GdUnitTestSuite
## FlightTicks (ARCHITECTURE §7.1.16, §9.4; the throwing ADR, TE3 under TD3 (b), TD9 (a), TD11 (a),
## TD12 (a)): each tick after the launch one more segment of the arc is swept; the world or a
## living player other than the thrower ends the flight; the item drops to the floor below the
## stop and rests with the cause `thrown`, or at the fallback below the thrower's feet; the longest
## flight; a pause and its resume. Driven by a Use whose rule launches the hand item (FixtureThrow,
## for 37c's ThrowItem) on a seeded match; the fixture capsule is 0.4 m by 1.8 m, the eye 1.6 m,
## the throw 10 m/s with g 9.8 m/s² and a radius of 0.15 m.

const P1 := 1
const P2 := 2
const R := 0.15
const NEAR := Vector3(1e-4, 1e-4, 1e-4)


func test_the_launch_tick_does_not_move_it_and_each_later_tick_sweeps_one_segment() -> void:
	var world := FixtureFlightWorld.new()
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, world)
	var item := FixtureFlightModes.flying(game)
	var flight := item.flight
	var seen := game.view_of(P2).events.size()
	# The launch tick L: the Use ran in it, then its tick systems.
	FixtureModes.run_ticks(game, 1)
	assert_int(flight.ticks).is_equal(0)
	assert_array(world.sweeps).is_empty()
	# Each later tick adds one and sweeps p(n - 1) to p(n), exactly those points.
	FixtureModes.run_ticks(game, 4)
	assert_int(flight.ticks).is_equal(4)
	assert_int(world.sweeps.size()).is_equal(4)
	for n in 4:
		assert_array(world.sweeps[n]).is_equal([flight.at(n), flight.at(n + 1), R])
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_vector(item.position).is_equal(flight.origin)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()


func test_items_fly_in_id_order() -> void:
	var world := FixtureFlightWorld.new()
	var game := FixtureItemModes.in_round(FixtureFlightModes.basic(), [P1, P2], world)
	var first := FixtureFlightModes.holding(game, P1, Vector3.ZERO)
	var second := FixtureFlightModes.holding(game, P2, Vector3(0, 0, 3))
	assert_int(first.id).is_less(second.id)
	# The higher id is thrown first, and the dictionary holds the items in the reverse order, so
	# only the sort in FlightTicks puts the sweeps in id order.
	FixtureFlightModes.throw(game, P2, Vector3.LEFT)
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	var ids: Array = game.state.items.keys()
	ids.reverse()
	var kept: Dictionary[int, ItemState] = game.state.items.duplicate()
	game.state.items.clear()
	for id: int in ids:
		game.state.items[id] = kept[id]
	assert_int(game.state.items.keys()[0]).is_equal(second.id)
	FixtureModes.run_ticks(game, 2)
	assert_int(world.sweeps.size()).is_equal(2)
	assert_vector(world.sweeps[0][0]).is_equal(first.flight.origin)
	assert_vector(world.sweeps[1][0]).is_equal(second.flight.origin)


func test_a_wall_stops_it_and_it_drops_to_the_floor_below() -> void:
	var world := FixtureFlightWorld.new()
	world.add_wall(AABB(Vector3(3, 0, -1), Vector3(1, 3, 2)))
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, world)
	var item := FixtureFlightModes.flying(game)
	var seen := game.view_of(P2).events.size()
	# p(6).x is 3.0, past the wall's face less the radius (2.85): the sixth segment meets it.
	FixtureModes.run_ticks(game, 6)
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	FixtureModes.run_ticks(game, 1)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_object(item.flight).is_null()
	assert_int(item.holder).is_equal(0)
	assert_vector(item.position).is_equal_approx(Vector3(3 - R, 0, 0), NEAR)
	assert_float(item.position.y).is_equal(0.0)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[-1] as ItemPlacedEvent
	assert_dict(placed.to_dict()).is_equal(
		{"item": item.id, "position": item.position, "cause": &"thrown"}
	)
	assert_array(FixtureModes.notes(game)).contains(
		[FixtureRestedNote.text(item.id, &"thrown", item.position)]
	)


func test_a_ceiling_stops_it_and_it_drops_straight_down() -> void:
	var world := FixtureFlightWorld.new()
	world.add_wall(AABB(Vector3(-5, 3, -5), Vector3(10, 0.5, 10)))
	var game := FixtureFlightModes.thrown(Vector3(1, 2, 0), Vector3.ZERO, world)
	var item := FixtureFlightModes.flying(game)
	var flight := item.flight
	FixtureModes.run_ticks(game, 1)
	while item.is_in_flight():
		FixtureModes.run_ticks(game, 1)
	# The sphere's top met the ceiling's underside: its centre stopped at 3 - R, in the last
	# segment, and the rest is right below that point.
	var last := flight.ticks
	var low := flight.at(last - 1)
	var high := flight.at(last)
	assert_float(high.y).is_greater(3 - R)
	var at := low.lerp(high, (3 - R - low.y) / (high.y - low.y))
	assert_vector(item.position).is_equal_approx(Vector3(at.x, 0, at.z), NEAR)
	assert_float(item.position.x).is_less(1.0)


func test_a_lob_lands_on_the_floor() -> void:
	var game := FixtureFlightModes.thrown(Vector3(1, 1, 0), Vector3.ZERO, FixtureFlightWorld.new())
	var item := FixtureFlightModes.flying(game)
	var speed := 10.0 / sqrt(2.0)
	# The centre comes down to R above the floor: 1.6 + v s - 4.9 s² = R.
	var s := (speed + sqrt(speed * speed + 4 * 4.9 * (1.6 - R))) / (2 * 4.9)
	FixtureModes.run_ticks(game, 40)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_float(item.position.y).is_equal(0.0)
	assert_float(item.position.x).is_equal_approx(speed * s, speed / Ticks.RATE)


func test_a_living_player_stops_it_and_it_falls_at_their_feet() -> void:
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
	FixtureItemModes.stand(game, P2, Vector3(5, 0, 0))
	var item := FixtureFlightModes.flying(game)
	var health := game.state.player(P2).health
	FixtureModes.run_ticks(game, 12)
	# Met at the capsule's side: 0.4 + R short of its axis (the floor alone would land it at 5.44).
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal_approx(Vector3(5 - 0.4 - R, 0, 0), NEAR)
	assert_int(game.state.player(P2).health).is_equal(health)


func test_an_invulnerable_living_player_stops_it_too() -> void:
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
	FixtureItemModes.stand(game, P2, Vector3(5, 0, 0))
	game.state.player(P2).invulnerable_until = game.ticked_through() + 100
	var item := FixtureFlightModes.flying(game)
	FixtureModes.run_ticks(game, 12)
	assert_vector(item.position).is_equal_approx(Vector3(5 - 0.4 - R, 0, 0), NEAR)


func test_an_item_starting_in_a_players_capsule_stops_at_once() -> void:
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
	FixtureItemModes.stand(game, P2, Vector3(0.3, 0, 0))
	var item := FixtureFlightModes.flying(game)
	FixtureModes.run_ticks(game, 2)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal(Vector3.ZERO)


func test_an_arc_over_a_head_flies_on_and_one_coming_down_on_it_stops() -> void:
	# From a 3 m platform, the item passes 4 m above a player at x = 3 and lands near x = 9.5.
	var over := _from_platform()
	FixtureItemModes.stand(over, P2, Vector3(3, 0, 0))
	var item := FixtureFlightModes.flying(over)
	FixtureModes.run_ticks(over, 30)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_float(item.position.x).is_greater(9.0)
	# A player near the landing: the item comes down on its head's cap, above its side.
	var on := _from_platform()
	FixtureItemModes.stand(on, P2, Vector3(8, 0, 0))
	var falling := FixtureFlightModes.flying(on)
	FixtureModes.run_ticks(on, 30)
	assert_float(falling.position.x).is_between(7.0, 8.0)
	assert_float(falling.position.y).is_equal(0.0)


func test_the_thrower_is_flown_through_wherever_it_stands() -> void:
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
	var item := FixtureFlightModes.flying(game)
	FixtureModes.run_ticks(game, 3)
	# The eye is inside the thrower's own capsule; later it steps into the path.
	FixtureItemModes.stand(game, P1, Vector3(3, 0, 0))
	FixtureModes.run_ticks(game, 12)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_float(item.position.x).is_greater(5.0)


func test_the_downed_the_dead_and_the_gone_are_flown_over() -> void:
	for life: int in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD, PlayerState.Life.LEFT]:
		var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
		FixtureItemModes.stand(game, P2, Vector3(5, 0, 0))
		game.state.player(P2).life = life as PlayerState.Life
		var item := FixtureFlightModes.flying(game)
		FixtureModes.run_ticks(game, 15)
		assert_int(item.where).is_equal(ItemState.Where.GROUND)
		assert_float(item.position.x).override_failure_message(str(life)).is_greater(5.4)


func test_the_earlier_of_a_wall_and_a_player_ends_it() -> void:
	# The player's side at 4.45, a wall's face (less R) at 4.0: the wall's.
	var walled := FixtureFlightWorld.new()
	walled.add_wall(AABB(Vector3(4 + R, 0, -1), Vector3(1, 3, 2)))
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, walled)
	FixtureItemModes.stand(game, P2, Vector3(5, 0, 0))
	FixtureModes.run_ticks(game, 12)
	assert_vector(game.state.items[1].position).is_equal_approx(Vector3(4, 0, 0), NEAR)
	# The wall behind the player: the player's.
	var behind := FixtureFlightWorld.new()
	behind.add_wall(AABB(Vector3(5.5, 0, -1), Vector3(1, 3, 2)))
	game = FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, behind)
	FixtureItemModes.stand(game, P2, Vector3(5, 0, 0))
	FixtureModes.run_ticks(game, 12)
	assert_vector(game.state.items[1].position).is_equal_approx(Vector3(5 - 0.4 - R, 0, 0), NEAR)


func test_it_rests_on_the_floor_below_the_stop_not_the_ground() -> void:
	var world := FixtureFlightWorld.new()
	world.add_wall(AABB(Vector3(3, 0, -1), Vector3(1, 3, 2)))
	# A low crate right in front of the wall.
	world.add_platform(2.0, -1, 2.95, 1, 0.5)
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, world)
	var item := FixtureFlightModes.flying(game)
	FixtureModes.run_ticks(game, 8)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal_approx(Vector3(3 - R, 0.5, 0), NEAR)


func test_the_longest_flight_stops_it_at_its_last_point() -> void:
	# A floor far below, the thrower on a pillar: only the longest flight (5 ticks) ends it.
	var world := FixtureFlightWorld.new(-50.0)
	world.add_platform(-1, -1, 1, 1, 0.0)
	var game := FixtureFlightModes.thrown(
		Vector3.RIGHT, Vector3.ZERO, world, FixtureFlightModes.basic(FixtureThrow.of(10.0, 5))
	)
	var item := FixtureFlightModes.flying(game)
	var flight := item.flight
	FixtureModes.run_ticks(game, 5)
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_int(flight.ticks).is_equal(4)
	FixtureModes.run_ticks(game, 1)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	var last := flight.at(5)
	assert_vector(item.position).is_equal(Vector3(last.x, -50, last.z))
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_longest_flight_of_one_tick_rests_after_one_tick() -> void:
	var game := FixtureFlightModes.thrown(
		Vector3.RIGHT,
		Vector3.ZERO,
		FixtureFlightWorld.new(),
		FixtureFlightModes.basic(FixtureThrow.of(10.0, 1))
	)
	var item := FixtureFlightModes.flying(game)
	var last := item.flight.at(1)
	FixtureModes.run_ticks(game, 2)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal(Vector3(last.x, 0, last.z))


func test_with_no_floor_below_the_stop_it_rests_below_the_throwers_feet_and_it_is_logged() -> void:
	# The floor ends at x = 1: the item flies out over the hole for its longest flight (10 ticks).
	var world := FixtureFlightWorld.new(0.0, 1.0)
	var game := FixtureFlightModes.thrown(
		Vector3.RIGHT,
		Vector3(0.5, 0, 0),
		world,
		FixtureFlightModes.basic(FixtureThrow.of(10.0, 10))
	)
	var item := FixtureFlightModes.flying(game)
	var seen := game.view_of(P2).events.size()
	FixtureModes.run_ticks(game, 11)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal(Vector3(0.5, 0, 0))
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("no floor below")
	assert_array(FixtureItemModes.names_after(game, P2, seen)).contains([&"ItemPlaced"])
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[-1] as ItemPlacedEvent
	assert_vector(placed.position).is_equal(Vector3(0.5, 0, 0))


func test_a_thrower_at_a_ledges_edge_gets_it_back_on_the_floor_below_its_feet() -> void:
	# A 1 m ledge ends at x = 1; the thrower stands on its rim (the footprint), its feet 0.2 m past
	# it, so its eye is raised from the ledge and the eye less the eye height is in the air. The
	# ground below ends at x = 3, and the item flies out over the hole for 10 ticks.
	var world := FixtureFlightWorld.new(0.0, 3.0)
	world.add_platform(-2, -1, 1, 1, 1.0)
	world.footprint_radius = 0.4
	var feet := Vector3(1.2, 1, 0)
	var game := FixtureFlightModes.thrown(
		Vector3.RIGHT, feet, world, FixtureFlightModes.basic(FixtureThrow.of(10.0, 10))
	)
	var item := FixtureFlightModes.flying(game)
	var origin := item.flight.origin
	assert_vector(origin).is_equal(Vector3(1.2, 2.6, 0))
	var below_feet := Vector3(1.2, 0, 0)
	assert_vector(item.flight.fallback).is_equal(below_feet)
	FixtureModes.run_ticks(game, 11)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal(below_feet)
	assert_vector(item.position).is_not_equal(origin - Vector3.UP * FixtureItemModes.EYE_HEIGHT_M)
	assert_str(game.diagnostics[0]).contains("no floor below")


func test_a_phase_without_flight_ticks_pauses_it_and_a_later_one_resumes_it() -> void:
	var mode := FixtureFlightModes.basic()
	var round_spec := mode.find_phase(&"round")
	var world := FixtureFlightWorld.new()
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, world, mode)
	var item := FixtureFlightModes.flying(game)
	var flight := item.flight
	FixtureModes.run_ticks(game, 3)
	assert_int(flight.ticks).is_equal(2)
	var flying := round_spec.tick_systems.duplicate()
	round_spec.tick_systems = [LifeTicks.new()]
	FixtureModes.run_ticks(game, 10)
	assert_int(flight.ticks).is_equal(2)
	assert_int(world.sweeps.size()).is_equal(2)
	assert_vector(item.position).is_equal(flight.origin)
	round_spec.tick_systems = flying
	FixtureModes.run_ticks(game, 1)
	# It goes on from p(2), not from where the host's ticks would put it.
	assert_array(world.sweeps[-1]).is_equal([flight.at(2), flight.at(3), R])
	FixtureModes.run_ticks(game, 20)
	var twin := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
	FixtureModes.run_ticks(twin, 20)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal(twin.state.items[1].position)


func test_the_thrower_downed_dead_or_gone_does_not_touch_the_flight() -> void:
	var control := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
	FixtureModes.run_ticks(control, 20)
	for life: int in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD, PlayerState.Life.LEFT]:
		var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, FixtureFlightWorld.new())
		var item := FixtureFlightModes.flying(game)
		FixtureModes.run_ticks(game, 2)
		game.state.player(P1).life = life as PlayerState.Life
		FixtureModes.run_ticks(game, 18)
		assert_int(item.where).is_equal(ItemState.Where.GROUND)
		assert_vector(item.position).is_equal(control.state.items[1].position)


func test_a_mode_without_player_rules_logs_it_and_the_world_still_ends_the_flight() -> void:
	var world := FixtureFlightWorld.new()
	world.add_wall(AABB(Vector3(3, 0, -1), Vector3(1, 3, 2)))
	var game := FixtureFlightModes.thrown(Vector3.RIGHT, Vector3.ZERO, world)
	var item := FixtureFlightModes.flying(game)
	game.state.player_rules = null
	FixtureModes.run_ticks(game, 8)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal_approx(Vector3(3 - R, 0, 0), NEAR)
	assert_bool(game.diagnostics.is_empty()).is_false()
	assert_str(game.diagnostics[0]).contains("the mode has no PlayerRules")


func test_the_same_commands_land_it_the_same_way() -> void:
	var runs: Array[Match] = []
	for i in 2:
		var world := FixtureFlightWorld.new()
		world.add_wall(AABB(Vector3(3, 0, -1), Vector3(1, 3, 2)))
		var game := FixtureFlightModes.thrown(Vector3(1, 0.5, 0.2), Vector3.ZERO, world)
		FixtureItemModes.stand(game, P2, Vector3(2, 0, 1))
		FixtureModes.run_ticks(game, 20)
		runs.append(game)
	assert_array(FixtureModes.describe(runs[1])).is_equal(FixtureModes.describe(runs[0]))
	assert_array(runs[1].command_log.world_answers).is_equal(runs[0].command_log.world_answers)


func test_the_capsule_contact_on_its_side_its_caps_and_inside() -> void:
	# The side: 0.4 + R = 0.55 m from the axis.
	assert_float(_contact(Vector3(-2, 1, 0), Vector3(0, 1, 0))).is_equal_approx(0.725, 1e-6)
	# Over the head: the top cap's centre is at 1.4, 0.6 m below the path.
	assert_float(_contact(Vector3(-2, 2, 0), Vector3(2, 2, 0))).is_equal(-1.0)
	# Straight down onto the head: the top cap reaches 1.95.
	assert_float(_contact(Vector3(0, 3, 0), Vector3(0, 1, 0))).is_equal_approx(0.525, 1e-6)
	# Already touching, moving away, and stopping short.
	assert_float(_contact(Vector3(0.5, 1, 0), Vector3(2, 1, 0))).is_equal(0.0)
	assert_float(_contact(Vector3(1, 1, 0), Vector3(2, 1, 0))).is_equal(-1.0)
	assert_float(_contact(Vector3(-2, 1, 0), Vector3(-1, 1, 0))).is_equal(-1.0)
	# From below: the bottom cap's centre is at 0.4, so it reaches down to -0.15.
	assert_float(_contact(Vector3(0, -2, 0), Vector3.ZERO)).is_equal_approx(0.925, 1e-6)
	# A capsule lower than its two caps is a ball at half its height.
	var low := _contact(Vector3(-2, 0.25, 0), Vector3(0, 0.25, 0), Vector3.ZERO, 0.5)
	assert_float(low).is_equal_approx(0.725, 1e-6)
	# Standing elsewhere: the capsule moves with the feet.
	var elsewhere := _contact(Vector3(3, 1, -2), Vector3(3, 1, 0), Vector3(3, 0, 0))
	assert_float(elsewhere).is_equal_approx(0.725, 1e-6)


func test_a_mode_listing_flight_ticks_passes_the_mode_check_without_warnings() -> void:
	var check := ModeCheck.run(FixtureFlightModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


## A round where P1 stands on a 3 m platform (x and z from -1 to 1) and throws along +x.
func _from_platform() -> Match:
	var world := FixtureFlightWorld.new()
	world.add_platform(-1, -1, 1, 1, 3.0)
	return FixtureFlightModes.thrown(Vector3.RIGHT, Vector3(0, 3, 0), world)


## FlightTicks.contact_fraction for the fixture capsule (radius 0.4) of `height` at `feet`.
func _contact(from: Vector3, to: Vector3, feet := Vector3.ZERO, height := 1.8) -> float:
	return FlightTicks.contact_fraction(from, to, feet, 0.4, height, R)
