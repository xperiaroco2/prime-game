extends GdUnitTestSuite
## Delivery's check on item_rested (ARCHITECTURE §7.1, §9.2, §9.5): a package of an undone
## subtask that rests within its own circle's radius, on the circle's floor, is delivered, however
## it got there; holding it over the circle never counts. Driven by PickUp, PutDown and a stand-in
## for the life rule (FixtureDropHeld) on a seeded match whose deal ran (DealTasks).

const P1 := 1
const P2 := 2
const P3 := 3


func test_a_package_put_down_in_its_own_circle_is_delivered() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1, P2])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	var seen_1 := game.view_of(P1).events.size()
	var seen_2 := game.view_of(P2).events.size()
	FixtureDeliveryModes.carry_to(game, P1, package, circle.position)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(package.position).is_equal(circle.position)
	assert_bool(circle.done).is_true()
	assert_int(task.state.done_count()).is_equal(1)
	assert_array(FixtureItemModes.names_after(game, P1, seen_1)).is_equal(
		[&"ItemPickedUp", &"ItemPlaced", &"PackageDelivered", &"TaskProgress", &"TaskUpdated"]
	)
	# The other player learns the delivery and the shared progress, never whose task it was.
	assert_array(FixtureItemModes.names_after(game, P2, seen_2)).is_equal(
		[&"ItemPickedUp", &"ItemPlaced", &"PackageDelivered", &"TaskProgress"]
	)
	var view := game.view_of(P2)
	assert_dict(view.events_named(&"PackageDelivered")[0].to_dict()).is_equal(
		{"item": package.id, "station": circle.id}
	)
	assert_dict(view.events_named(&"TaskProgress")[0].to_dict()).is_equal({"done": 1, "total": 4})
	assert_dict(game.view_of(P1).events_named(&"TaskUpdated")[0].to_dict()).is_equal(
		{"task": task.id, "done": 1}
	)
	assert_array(game.view_of(P2).events_named(&"TaskUpdated")).is_empty()


func test_subtask_done_carries_the_task_its_owner_and_the_detail() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1, P2])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 1)
	FixtureDeliveryModes.carry_to(
		game, P1, package, FixtureDeliveryModes.circle_of(game, task, 1).position
	)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureSubtaskNote.text(task.id, P1, {"subtask": 1, "item": package.id})]
	)
	# The fact is raised after the events of the delivery.
	var names := FixtureModes.names(game)
	assert_int(names.rfind(&"FixtureNote")).is_greater(names.rfind(&"TaskUpdated"))


func test_anyone_may_deliver_and_only_the_owner_is_updated() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1, P2, P3])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	FixtureDeliveryModes.carry_to(
		game, P2, package, FixtureDeliveryModes.circle_of(game, task, 0).position
	)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_array(game.view_of(P1).events_named(&"TaskUpdated")).has_size(1)
	assert_array(game.view_of(P2).events_named(&"TaskUpdated")).is_empty()
	assert_array(game.view_of(P3).events_named(&"TaskUpdated")).is_empty()
	for peer: int in [P1, P2, P3]:
		assert_array(game.view_of(peer).events_named(&"PackageDelivered")).has_size(1)


func test_progress_counts_every_task_and_the_update_counts_the_owners() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(2, 2), [P1, P2])
	var task := FixtureDeliveryModes.tasks_of(game, P2)[1]
	for index in 2:
		FixtureDeliveryModes.carry_to(
			game,
			P2,
			FixtureDeliveryModes.package_of(game, task, index),
			FixtureDeliveryModes.circle_of(game, task, index).position
		)
	var progress: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(P1).events_named(&"TaskProgress"):
		progress.append(event.to_dict())
	assert_array(progress).is_equal([{"done": 1, "total": 8}, {"done": 2, "total": 8}])
	var updates: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(P2).events_named(&"TaskUpdated"):
		updates.append(event.to_dict())
	assert_array(updates).is_equal([{"task": task.id, "done": 1}, {"task": task.id, "done": 2}])
	assert_bool(task.state.is_done()).is_true()


func test_just_inside_the_radius_counts_and_just_outside_does_not() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var outside := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureDeliveryModes.carry_to(game, P1, outside, circle.position + Vector3(0.6, 0, 0.9))
	assert_int(outside.where).is_equal(ItemState.Where.GROUND)
	assert_bool(circle.done).is_false()
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).is_empty()
	var inside := FixtureDeliveryModes.package_of(game, task, 1)
	var other := FixtureDeliveryModes.circle_of(game, task, 1)
	FixtureDeliveryModes.carry_to(game, P1, inside, other.position + Vector3(0.6, 0, 0.7))
	assert_int(inside.where).is_equal(ItemState.Where.LOCKED)
	assert_bool(other.done).is_true()


func test_exactly_on_the_radius_counts() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 1), [P1])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureDeliveryModes.carry_to(game, P1, package, circle.position + Vector3(1.0, 0, 0))
	assert_float(package.position.x - circle.position.x).is_equal(1.0)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)


func test_a_package_on_a_floor_below_the_circle_within_the_tolerance_counts() -> void:
	var game := FixtureDeliveryModes.in_round(
		FixtureDeliveryModes.basic(1, 1), [P1], {}, FlatWorldQuery.new(-0.25)
	)
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	FixtureDeliveryModes.carry_to(
		game, P1, package, FixtureDeliveryModes.circle_of(game, task, 0).position
	)
	assert_float(package.position.y).is_equal_approx(-0.25, 0.0001)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)


func test_a_package_on_a_floor_below_the_circle_by_more_than_the_tolerance_does_not_count() -> void:
	var game := FixtureDeliveryModes.in_round(
		FixtureDeliveryModes.basic(1, 1), [P1], {}, FlatWorldQuery.new(-0.4)
	)
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureDeliveryModes.carry_to(game, P1, package, circle.position)
	assert_float(package.position.y).is_equal_approx(-0.4, 0.0001)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_bool(circle.done).is_false()


func test_another_packages_circle_does_not_count() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var wrong := FixtureDeliveryModes.circle_of(game, task, 1)
	FixtureDeliveryModes.carry_to(game, P1, package, wrong.position)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_bool(wrong.done).is_false()
	assert_int(task.state.done_count()).is_equal(0)
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).is_empty()


func test_an_item_that_is_no_package_of_a_task_does_nothing_in_a_circle() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1])
	var circle := FixtureDeliveryModes.circle_of(
		game, FixtureDeliveryModes.tasks_of(game, P1)[0], 0
	)
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(40, 0, 0))
	var stray := FixtureItemModes.lay(game, &"package", Vector3(45, 0, 0))
	FixtureDeliveryModes.carry_to(game, P1, tool, circle.position)
	FixtureDeliveryModes.carry_to(game, P1, stray, circle.position + Vector3(0, 0, 0.5))
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	assert_int(stray.where).is_equal(ItemState.Where.GROUND)
	assert_bool(circle.done).is_false()
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).is_empty()


func test_a_package_on_a_floor_above_the_circle_by_more_than_the_tolerance_does_not_count() -> void:
	# The world's floor is 0.4 m above the circle markers, beyond the 0.3 m tolerance.
	var game := FixtureDeliveryModes.in_round(
		FixtureDeliveryModes.basic(1, 1), [P1], {}, FlatWorldQuery.new(0.4)
	)
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureDeliveryModes.carry_to(game, P1, package, circle.position)
	assert_float(package.position.y).is_equal_approx(0.4, 0.0001)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_bool(circle.done).is_false()


func test_a_package_on_a_floor_within_the_tolerance_counts() -> void:
	var game := FixtureDeliveryModes.in_round(
		FixtureDeliveryModes.basic(1, 1), [P1], {}, FlatWorldQuery.new(0.25)
	)
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	FixtureDeliveryModes.carry_to(
		game, P1, package, FixtureDeliveryModes.circle_of(game, task, 0).position
	)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)


func test_holding_a_package_over_its_circle_never_counts() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 1), [P1])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureItemModes.stand(game, P1, package.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, package)
	FixtureItemModes.stand(game, P1, circle.position)
	FixtureModes.run_ticks(game, 3)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	assert_bool(circle.done).is_false()
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).is_empty()
	# Put down at the feet (a facing straight down): now it rests in the circle.
	FixtureItemModes.put_down(game, P1, Vector3.DOWN)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)


func test_a_package_swapped_into_its_circle_is_delivered() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var held := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureItemModes.stand(game, P1, held.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, held)
	# A tool lies inside the held package's circle; picking it up swaps the package onto its spot.
	var tool := FixtureItemModes.lay(game, &"tool", circle.position + Vector3(0.3, 0, 0))
	FixtureItemModes.stand(game, P1, circle.position + Vector3(1.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, tool)
	assert_int(tool.where).is_equal(ItemState.Where.HAND)
	assert_int(held.where).is_equal(ItemState.Where.LOCKED)
	var placed := game.view_of(P1).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_str(placed.cause).is_equal("swap")
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).has_size(1)


func test_a_package_dropped_at_a_death_inside_its_circle_is_delivered() -> void:
	var mode := FixtureDeliveryModes.basic(1, 1)
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.DEATH)]))
	var game := FixtureDeliveryModes.in_round(mode, [P1, P2])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureItemModes.stand(game, P1, package.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, package)
	# Mid-jump over the circle: the drop falls to the floor below.
	FixtureItemModes.stand(game, P1, circle.position + Vector3(0, 0.8, 0.4))
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.GHOST)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(package.position).is_equal(circle.position + Vector3(0, 0, 0.4))
	# The ghost still owns its task and is told; the living see only the public part.
	assert_array(game.view_of(P1).events_named(&"TaskUpdated")).has_size(1)
	assert_array(game.view_of(P2).events_named(&"PackageDelivered")).has_size(1)


func test_an_owner_who_leaves_over_its_circle_delivers_and_is_told_nothing() -> void:
	var mode := FixtureDeliveryModes.basic(1, 1)
	mode.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureDropHeld.of(Items.LEAVE)]))
	var game := FixtureDeliveryModes.in_round(mode, [P1, P2])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureItemModes.stand(game, P1, package.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, package)
	FixtureItemModes.stand(game, P1, circle.position)
	var seen := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_array(game.view_of(P1).events.slice(seen)).is_empty()
	assert_array(game.view_of(P2).events_named(&"PackageDelivered")).has_size(1)
	assert_array(_emitted_named(game, &"TaskUpdated")).has_size(1)
	assert_array(Array(_emitted_named(game, &"TaskUpdated")[0].recipients)).is_empty()


func test_a_delivered_package_cannot_be_picked_up_and_shows_as_locked() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 1), [P1, P2])
	var task := FixtureDeliveryModes.tasks_of(game, P1)[0]
	var package := FixtureDeliveryModes.package_of(game, task, 0)
	var circle := FixtureDeliveryModes.circle_of(game, task, 0)
	FixtureDeliveryModes.carry_to(game, P1, package, circle.position)
	FixtureItemModes.stand(game, P2, circle.position + Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P2, package, 9)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	FixtureModes.run_ticks(game, 1)
	var snapshots := game.view_of(P2).snapshots
	var last: Dictionary = snapshots[game.ticked_through()]
	var items: Dictionary = last["items"]
	var shown: Dictionary = items[package.id]
	assert_int(shown["where"]).is_equal(ItemState.Where.LOCKED)
	assert_array(game.view_of(P1).events_named(&"PackageDelivered")).has_size(1)


func _emitted_named(game: Match, event_name: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event.event_name() == event_name:
			found.append(emitted)
	return found


func test_a_replay_deals_and_delivers_the_same() -> void:
	# One package spawns inside its own circle: the replay must deal it there and deliver it.
	var found := FixtureModes.layouts()
	found[FixtureModes.MAP].add_marker(&"circle", Vector3(3, 0, 3))
	found[FixtureModes.MAP].add_marker(&"package", Vector3(3.5, 0, 3))
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 1), [P1], found)
	FixtureModes.run_ticks(game, 2)
	var replayed := Match.replay(game.command_log, FixtureDeliveryModes.basic(1, 1))
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))
	assert_int(replayed.state.items[1].where).is_equal(ItemState.Where.LOCKED)
