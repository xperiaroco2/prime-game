extends GdUnitTestSuite
## Delivery with a thrown package (ARCHITECTURE §7.1.14, §7.1.16; TD4 (a)): the rule is "the
## package rests inside its circle, however it got there", so a throw counts when its rest, at
## the end of the flight (FlightTicks, the cause `thrown`), is inside; a package flying over its
## circle counts for nothing until it rests. Delivery's code is unchanged. Driven by PickUp and a
## Use that throws the hand item (FixtureThrow, 10 m/s, from the 1.6 m eye: a level throw lands
## about 5.44 m ahead) on a seeded match whose deal ran.

const P1 := 1
const P2 := 2
## Where a level throw's sphere (radius 0.15 m) comes down to the floor: 1.6 - 4.9 s² = 0.15.
const LEVEL_RANGE_M := 5.44


func test_a_package_thrown_into_its_circle_is_delivered_with_the_cause_thrown() -> void:
	var game := _round()
	var task := FixtureDeliveryModes.task_of(game)
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	_pick_up(game, P1, package)
	FixtureItemModes.stand(game, P1, circle.position - Vector3(LEVEL_RANGE_M, 0, 0))
	var seen := game.view_of(P2).events.size()
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	FixtureModes.run_ticks(game, 20)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_float(package.position.distance_to(circle.position)).is_less(
		FixtureDeliveryModes.RADIUS_M
	)
	assert_bool(circle.done).is_true()
	assert_int(task.state.done_count()).is_equal(1)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemPlaced", &"PackageDelivered", &"TaskState", &"TaskProgress"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[-1] as ItemPlacedEvent
	assert_str(placed.cause).is_equal("thrown")
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureSubtaskNote.text(task.id, {"subtask": 0, "item": package.id})]
	)


func test_a_package_thrown_short_of_its_circle_rests_and_can_be_picked_up() -> void:
	var game := _round()
	var task := FixtureDeliveryModes.task_of(game)
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	_pick_up(game, P1, package)
	FixtureItemModes.stand(game, P1, circle.position - Vector3(LEVEL_RANGE_M + 3, 0, 0))
	FixtureFlightModes.throw(game, P1, Vector3.RIGHT)
	FixtureModes.run_ticks(game, 20)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_bool(circle.done).is_false()
	assert_array(game.view_of(P2).events_named(&"PackageDelivered")).is_empty()
	_pick_up(game, P2, package)
	assert_int(game.state.player(P2).held_item).is_equal(package.id)


func test_a_package_flying_over_its_circle_is_not_delivered() -> void:
	var game := _round()
	var task := FixtureDeliveryModes.task_of(game)
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	_pick_up(game, P1, package)
	# A lob from 2 m short: over the circle within half a second, down about 11.5 m out.
	FixtureItemModes.stand(game, P1, circle.position - Vector3(2, 0, 0))
	FixtureFlightModes.throw(game, P1, Vector3(1, 1, 0))
	FixtureModes.run_ticks(game, 7)
	assert_int(package.where).is_equal(ItemState.Where.FLYING)
	var over := package.flight.at(package.flight.ticks) - circle.position
	assert_float(Vector2(over.x, over.z).length()).is_less(FixtureDeliveryModes.RADIUS_M)
	assert_bool(circle.done).is_false()
	FixtureModes.run_ticks(game, 40)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_float(package.position.x - circle.position.x).is_greater(5.0)
	assert_bool(circle.done).is_false()
	assert_array(game.view_of(P2).events_named(&"PackageDelivered")).is_empty()


## A round of P1 and P2 on the delivery fixture mode (two packages) with the throw.
func _round() -> Match:
	return FixtureDeliveryModes.in_round(
		FixtureFlightModes.with_throw(FixtureDeliveryModes.basic(2)), [P1, P2]
	)


## `peer` stands beside `item` and picks it up.
func _pick_up(game: Match, peer: int, item: ItemState) -> void:
	FixtureItemModes.stand(game, peer, item.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, peer, item)
	assert_int(game.state.player(peer).held_item).is_equal(item.id)
