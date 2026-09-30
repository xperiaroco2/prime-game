extends GdUnitTestSuite
## DealTasks (ARCHITECTURE §3.3, §9.4), with a fake task type: each present player gets
## `tasks_per_player` tasks through TaskType.deal(), split over several task types in the mode's
## order; TasksAssigned reaches only the owner, and nobody receives another player's tasks (§5).


func test_each_player_gets_the_tasks_per_player() -> void:
	var peers: Array[int] = [3, 1, 2]
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(), peers, {&"tasks_per_player": 3}
	)
	var per_owner := {}
	var owners: Array[int] = []
	for id: int in game.state.tasks:
		var task := game.state.tasks[id]
		assert_str(task.type.id).is_equal("fixture_dealt")
		per_owner[task.owner] = per_owner.get(task.owner, 0) + 1
		owners.append(task.owner)
	assert_dict(per_owner).is_equal({1: 3, 2: 3, 3: 3})
	# Dealt in peer-id order, so task ids follow the owners.
	assert_array(owners).is_equal([1, 1, 1, 2, 2, 2, 3, 3, 3])


func test_tasks_assigned_reaches_only_its_owner_and_matches_the_state() -> void:
	var peers: Array[int] = [1, 2, 3, 4]
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers)
	for emitted: EmittedEvent in game.emitted():
		if emitted.event is TasksAssignedEvent:
			assert_array(Array(emitted.recipients)).is_equal(
				[(emitted.event as TasksAssignedEvent).peer]
			)
	for peer: int in peers:
		var assigned := game.view_of(peer).events_named(&"TasksAssigned")
		assert_int(assigned.size()).is_equal(1)
		var tasks := (assigned[0] as TasksAssignedEvent).tasks
		assert_int(tasks.size()).is_equal(2)
		for entry: Dictionary in tasks:
			var task := game.state.tasks[entry["task"] as int]
			assert_int(task.owner).is_equal(peer)
			var state := task.state as FixtureDealtTaskType.FixtureDealtState
			assert_array(entry["subtasks"] as Array).is_equal([{"item": state.targets[0]}])


func test_nobody_receives_another_players_tasks() -> void:
	# §5's invariant, from the state: every task id and target a peer was told belongs to it.
	var peers: Array[int] = [1, 2, 3, 4, 5]
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers, {&"dissidents": 2})
	for peer: int in peers:
		var told: Array[int] = []
		for event: MatchEvent in game.view_of(peer).events:
			var fields := event.to_dict()
			if fields.has("tasks"):
				for entry: Dictionary in fields["tasks"] as Array:
					told.append(entry["task"] as int)
		var own: Array[int] = []
		for id: int in game.state.tasks:
			if game.state.tasks[id].owner == peer:
				own.append(id)
		assert_array(told).is_equal(own)


func test_several_task_types_split_the_tasks_in_the_modes_order() -> void:
	var first := FixtureDealtTaskType.new(&"first", FixtureDealModes.item_kind(&"token"))
	var second := FixtureDealtTaskType.new(&"second", FixtureDealModes.item_kind(&"token"))
	var mode := FixtureDealModes.deal_mode([first, second])
	var game := FixtureDealModes.dealt(mode, [1, 2], {&"tasks_per_player": 3})
	assert_dict(_tasks_by_type(game, 1)).is_equal({&"first": 2, &"second": 1})
	assert_dict(_tasks_by_type(game, 2)).is_equal({&"first": 2, &"second": 1})
	var one := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode([first, second]), [1, 2], {&"tasks_per_player": 1}
	)
	assert_dict(_tasks_by_type(one, 1)).is_equal({&"first": 1})
	# The second type's share is 0: it deals nothing, so it tells nobody anything.
	assert_int(game.view_of(1).events_named(&"TasksAssigned").size()).is_equal(2)
	assert_int(one.view_of(1).events_named(&"TasksAssigned").size()).is_equal(1)


func test_shares() -> void:
	assert_int(DealTasks.share_of(2, 1, 0)).is_equal(2)
	assert_int(DealTasks.share_of(3, 2, 0)).is_equal(2)
	assert_int(DealTasks.share_of(3, 2, 1)).is_equal(1)
	assert_int(DealTasks.share_of(1, 3, 2)).is_equal(0)
	assert_int(DealTasks.share_of(0, 1, 0)).is_equal(0)
	assert_int(DealTasks.share_of(4, 0, 0)).is_equal(0)


func test_zero_tasks_per_player_deals_nothing() -> void:
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(), [1, 2], {&"tasks_per_player": 0}
	)
	assert_dict(game.state.tasks).is_empty()
	assert_array(FixtureModes.names(game)).not_contains([&"TasksAssigned"])


func test_it_forwards_its_demand_to_the_modes_task_types() -> void:
	var first := FixtureDealtTaskType.new(&"first", FixtureDealModes.item_kind(&"token"))
	var mode := FixtureDealModes.deal_mode([first])
	var deal := FixtureDealModes.deal_tasks()
	var settings: Dictionary[StringName, int] = {&"tasks_per_player": 3}
	var none := Demands.new(null)
	deal.add_demands(settings, 4, none)
	# No mode: nothing to forward to.
	assert_dict(none.markers).is_empty()
	var demands := Demands.new(mode)
	deal.add_demands(settings, 4, demands)
	assert_dict(demands.markers).is_equal({FixtureDealModes.ITEM_TAG: 12})


func test_the_mode_check_refuses_it_without_its_setting() -> void:
	var mode := FixtureDealModes.deal_mode()
	(mode.transitions[0].actions[1] as DealTasks).tasks_setting = &""
	assert_str("\n".join(ModeCheck.run(mode).errors)).contains("DealTasks has no tasks_setting")
	(mode.transitions[0].actions[1] as DealTasks).tasks_setting = &"tasks"
	assert_str("\n".join(ModeCheck.run(mode).errors)).contains(
		"tasks_setting names setting tasks, which the mode does not declare"
	)


func test_stations_reach_everyone_in_id_order_with_their_items_colours() -> void:
	# The chain Delivery's deal emits (§9.5; the real one is 2f's): StationPlaced to every peer in
	# station-id order, and each item's ItemSpawned carries its station and that station's colour.
	var circle := StationKind.new()
	circle.id = &"circle"
	circle.spawn_tag = FixtureDealModes.STATION_TAG
	for i in 6:
		circle.palette.append(Color.from_hsv(i / 6.0, 1.0, 1.0))
	var type := FixtureDealtTaskType.new(&"fixture_dealt", FixtureDealModes.item_kind(&"token"))
	type.station = circle
	var peers: Array[int] = [1, 2, 3]
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode([type]), peers)
	var expected: Array[Dictionary] = []
	for id: int in game.state.stations:
		var placed := game.state.stations[id]
		(
			expected
			. append(
				{
					"station": id,
					"kind": &"circle",
					"colour": placed.colour,
					"position": placed.position,
				}
			)
		)
	assert_int(expected.size()).is_equal(6)
	for peer: int in peers:
		var seen: Array[Dictionary] = []
		var colour_of := {}
		for event: MatchEvent in game.view_of(peer).events_named(&"StationPlaced"):
			var fields := event.to_dict()
			seen.append(fields)
			colour_of[fields["station"]] = fields["colour"]
		assert_array(seen).is_equal(expected)
		var tokens := 0
		for event: MatchEvent in game.view_of(peer).events_named(&"ItemSpawned"):
			var spawned := event as ItemSpawnedEvent
			if spawned.kind == &"token":
				tokens += 1
				assert_bool(colour_of.has(spawned.station)).is_true()
				assert_that(spawned.colour).is_equal(colour_of[spawned.station])
				assert_that(game.state.stations[spawned.station].colour).is_equal(spawned.colour)
		assert_int(tokens).is_equal(6)


## Task type id -> the number of `peer`'s tasks of that type.
func _tasks_by_type(game: Match, peer: int) -> Dictionary:
	var found := {}
	for id: int in game.state.tasks:
		var task := game.state.tasks[id]
		if task.owner == peer:
			found[task.type.id] = found.get(task.type.id, 0) + 1
	return found
