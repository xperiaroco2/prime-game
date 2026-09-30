extends GdUnitTestSuite
## Delivery's deal, its demands and its mode check (ARCHITECTURE §3.3, §9.4, §9.5). DealTasks is
## 2c's: FixtureDealTasks calls Delivery.deal from the `lobby, all_ready -> round` row, before
## PlacePlayers, as the base mode's deal row will.

const P1 := 1
const P2 := 2


func test_the_deal_places_players_x_tasks_x_subtasks_circles_and_packages() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(2, 2), [P1, P2])
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.stations.size()).is_equal(8)
	assert_int(game.state.items.size()).is_equal(8)
	assert_int(game.state.tasks.size()).is_equal(4)
	var owners: Array[int] = []
	for id: int in game.state.tasks:
		var task := game.state.tasks[id]
		owners.append(task.owner)
		assert_object(task.type).is_same(FixtureDeliveryModes.delivery_of(game.mode))
		assert_int(task.state.total()).is_equal(2)
		assert_int(task.state.done_count()).is_equal(0)
	# Per player in peer-id order, tasks per player each.
	assert_array(owners).is_equal([P1, P1, P2, P2])
	assert_array(Array(game.diagnostics)).is_empty()


func test_ids_follow_spawn_point_order() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1, P2])
	var last_x := -1.0
	for id: int in game.state.stations:
		var station := game.state.stations[id]
		assert_float(station.position.z).is_equal(20.0)
		assert_bool(station.position.x > last_x).is_true()
		last_x = station.position.x
	last_x = -1.0
	for id: int in game.state.items:
		var item := game.state.items[id]
		assert_float(item.position.z).is_equal(-20.0)
		assert_bool(item.position.x > last_x).is_true()
		last_x = item.position.x
		assert_str(item.kind.id).is_equal("package")
		assert_int(item.where).is_equal(ItemState.Where.GROUND)


func test_each_package_has_a_circle_of_its_own_whose_colour_never_repeats() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(2, 2), [P1, P2])
	var packages: Array[int] = []
	var circles: Array[int] = []
	for id: int in game.state.tasks:
		var task_state := game.state.tasks[id].state as Delivery.State
		packages.append_array(Array(task_state.packages))
		circles.append_array(Array(task_state.circles))
	packages.sort()
	circles.sort()
	assert_array(packages).is_equal([1, 2, 3, 4, 5, 6, 7, 8])
	assert_array(circles).is_equal([1, 2, 3, 4, 5, 6, 7, 8])
	var colours: Array[Color] = []
	for id: int in game.state.stations:
		var colour := game.state.stations[id].colour
		assert_bool(FixtureDeliveryModes.PALETTE.has(colour)).is_true()
		assert_bool(colours.has(colour)).is_false()
		colours.append(colour)


func test_everyone_sees_the_circles_then_the_packages_in_id_order() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 2), [P1, P2])
	var bound := _circle_by_package(game)
	for peer: int in [P1, P2]:
		var view := game.view_of(peer)
		var placed := view.events_named(&"StationPlaced")
		var spawned := view.events_named(&"ItemSpawned")
		assert_array(placed).has_size(4)
		assert_array(spawned).has_size(4)
		for i in 4:
			var station := game.state.stations[i + 1]
			assert_dict(placed[i].to_dict()).is_equal(
				{
					"station": station.id,
					"kind": &"circle",
					"colour": station.colour,
					"position": station.position
				}
			)
			var item := game.state.items[i + 1]
			var circle := game.state.stations[bound[item.id]]
			assert_dict(spawned[i].to_dict()).is_equal(
				{
					"item": item.id,
					"kind": &"package",
					"position": item.position,
					"station": circle.id,
					"colour": circle.colour
				}
			)
		var names := view.event_names()
		var first_spawned := names.find(&"ItemSpawned")
		assert_int(names.rfind(&"StationPlaced")).is_less(first_spawned)
		# The deal runs before PlacePlayers and the entry into Round.
		assert_int(names.find(&"TasksAssigned")).is_greater(names.rfind(&"ItemSpawned"))
		assert_int(names.find(&"PlayersPlaced")).is_greater(names.find(&"TasksAssigned"))


func test_tasks_assigned_reaches_only_the_owner() -> void:
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(2, 2), [P1, P2])
	for peer: int in [P1, P2]:
		var assigned := game.view_of(peer).events_named(&"TasksAssigned")
		assert_array(assigned).has_size(1)
		var expected: Array[Dictionary] = []
		for task: MatchTask in FixtureDeliveryModes.tasks_of(game, peer):
			var task_state := task.state as Delivery.State
			var targets: Array[Dictionary] = []
			for item: int in task_state.packages:
				targets.append({"item": item})
			expected.append({"task": task.id, "type": &"delivery", "subtasks": targets})
		assert_dict(assigned[0].to_dict()).is_equal({"tasks": expected})
	# Who owns a task never leaves the host: each view names its own tasks only.
	var of_p1 := game.view_of(P1).events_named(&"TasksAssigned")[0] as TasksAssignedEvent
	for entry: Dictionary in of_p1.tasks:
		var task_id: int = entry["task"]
		assert_int(game.state.tasks[task_id].owner).is_equal(P1)
	var emitted := _emitted_named(game, &"TasksAssigned")
	assert_array(emitted).has_size(2)
	assert_array(Array(emitted[0].recipients)).is_equal([P1])
	assert_array(Array(emitted[1].recipients)).is_equal([P2])


func test_the_same_seed_deals_the_same_and_another_seed_differs() -> void:
	var mode := FixtureDeliveryModes.basic(2, 2)
	var first := FixtureDeliveryModes.in_round(mode, [P1, P2], {}, null, 11)
	var again := FixtureDeliveryModes.in_round(mode, [P1, P2], {}, null, 11)
	var other := FixtureDeliveryModes.in_round(mode, [P1, P2], {}, null, 12)
	assert_array(FixtureModes.describe(again)).is_equal(FixtureModes.describe(first))
	assert_array(FixtureModes.describe(other)).is_not_equal(FixtureModes.describe(first))


func test_each_draw_has_its_own_rng_purpose() -> void:
	var mode := FixtureDeliveryModes.basic(2, 2)
	var first := FixtureDeliveryModes.in_round(mode, [P1, P2], {}, null, 11)
	var other_mode := FixtureDeliveryModes.basic(2, 2)
	FixtureDeliveryModes.delivery_of(other_mode).circles_rng = &"other_circles"
	var second := FixtureDeliveryModes.in_round(other_mode, [P1, P2], {}, null, 11)
	# Another circles purpose moves the circles; the packages keep their spots.
	assert_array(_item_spots(second)).is_equal(_item_spots(first))
	assert_array(_station_spots(second)).is_not_equal(_station_spots(first))


func test_a_package_that_spawns_inside_its_own_circle_is_delivered_at_once() -> void:
	var found := FixtureModes.layouts()
	found[FixtureModes.MAP].add_marker(&"circle", Vector3(3, 0, 3))
	found[FixtureModes.MAP].add_marker(&"package", Vector3(3.5, 0, 3))
	var game := FixtureDeliveryModes.in_round(FixtureDeliveryModes.basic(1, 1), [P1], found)
	assert_int(game.state.items[1].where).is_equal(ItemState.Where.LOCKED)
	assert_bool(game.state.stations[1].done).is_true()
	var names := game.view_of(P1).event_names()
	var spawned := names.find(&"ItemSpawned")
	var assigned := names.find(&"TasksAssigned")
	assert_array(names.slice(spawned, assigned + 4)).is_equal(
		[&"ItemSpawned", &"TasksAssigned", &"PackageDelivered", &"TaskProgress", &"TaskUpdated"]
	)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureSubtaskNote.text(1, P1, {"subtask": 0, "item": 1})]
	)


func test_a_map_without_enough_markers_deals_nothing_and_says_so() -> void:
	var game := FixtureDeliveryModes.in_round(
		FixtureDeliveryModes.basic(1, 2), [P1, P2], FixtureDeliveryModes.layouts(3, 10)
	)
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.tasks.size()).is_equal(0)
	assert_int(game.state.items.size()).is_equal(0)
	assert_str(game.diagnostics[0]).contains("4 packages need")
	assert_array(game.view_of(P1).events_named(&"StationPlaced")).is_empty()


func test_packages_skip_a_package_marker_where_an_item_already_rests() -> void:
	# A deal puts at most one item on a marker (§3.3): an item placed earlier in the row keeps
	# its marker, and the packages take the free ones.
	var mode := _with_a_tool_on_the_first_package_marker(FixtureDeliveryModes.basic(1, 2))
	var game := FixtureDeliveryModes.in_round(mode, [P1, P2], FixtureDeliveryModes.layouts(10, 5))
	assert_array(Array(game.diagnostics)).is_empty()
	var packages: Array[Vector3] = []
	for id: int in game.state.items:
		var item := game.state.items[id]
		if item.kind.id == &"package":
			packages.append(item.position)
	assert_array(packages).is_equal(
		[Vector3(10, 0, -20), Vector3(20, 0, -20), Vector3(30, 0, -20), Vector3(40, 0, -20)]
	)


func test_too_few_free_package_markers_deals_nothing_and_says_so() -> void:
	var mode := _with_a_tool_on_the_first_package_marker(FixtureDeliveryModes.basic(1, 2))
	var game := FixtureDeliveryModes.in_round(mode, [P1, P2], FixtureDeliveryModes.layouts(10, 4))
	assert_int(game.state.tasks.size()).is_equal(0)
	assert_int(game.state.items.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("4 packages need")
	assert_str(game.diagnostics[0]).contains("the map has 10 and 3")


func test_a_palette_too_small_deals_nothing_and_says_so() -> void:
	var mode := FixtureDeliveryModes.basic(1, 2)
	FixtureDeliveryModes.delivery_of(mode).circle.palette = PackedColorArray(
		[Color.RED, Color.BLUE, Color.GREEN]
	)
	var game := FixtureDeliveryModes.in_round(mode, [P1, P2])
	assert_int(game.state.stations.size()).is_equal(0)
	assert_str(game.diagnostics[0]).contains("the palette 3")


func test_demands_are_packages_per_tag_and_colours_per_circle() -> void:
	var mode := FixtureDeliveryModes.basic()
	var delivery := FixtureDeliveryModes.delivery_of(mode)
	var demands := Demands.new(mode)
	var settings: Dictionary[StringName, int] = {&"subtasks_per_task": 2}
	delivery.add_demands(settings, 10, 2, demands)
	assert_dict(demands.markers).is_equal({&"circle": 40, &"package": 40})
	assert_dict(demands.colours).is_equal({&"circle": 40})
	var layout := LevelLayout.new(FixtureModes.MAP)
	for i in 40:
		layout.add_marker(&"circle", Vector3(i, 0, 0))
		layout.add_marker(&"package", Vector3(i, 0, 1))
	assert_array(Array(demands.shortfalls(layout))).is_equal(
		["40 circle colour(s) needed, the palette has 12"]
	)


func test_the_fixture_mode_passes_the_mode_check() -> void:
	var check := ModeCheck.run(FixtureDeliveryModes.basic())
	assert_array(Array(check.errors)).is_empty()


func test_the_mode_check_refuses_a_delivery_without_its_parts() -> void:
	var mode := FixtureDeliveryModes.basic()
	var delivery := FixtureDeliveryModes.delivery_of(mode)
	delivery.package = null
	delivery.circle = null
	delivery.subtasks_setting = &""
	delivery.tasks_rng = &""
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Delivery delivery has no package item kind")
	assert_str(errors).contains("Delivery delivery has no circle station kind")
	assert_str(errors).contains("Delivery delivery has no subtasks_setting")
	assert_str(errors).contains("Delivery delivery has an empty RNG purpose")


func test_the_mode_check_refuses_undeclared_names_and_numbers_out_of_bounds() -> void:
	var mode := FixtureDeliveryModes.basic()
	var delivery := FixtureDeliveryModes.delivery_of(mode)
	delivery.package = FixtureItemModes.item_kind(&"parcel", [])
	delivery.subtasks_setting = &"parcels_per_task"
	delivery.floor_tolerance_m = 0.0
	delivery.circle.radius_m = 0.1
	delivery.circle.palette = PackedColorArray([Color.RED, Color.RED])
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("names item kind parcel, which the mode does not declare")
	assert_str(errors).contains("names setting parcels_per_task, which the mode does not declare")
	assert_str(errors).contains("floor_tolerance_m is 0, outside 0.01 to 2")
	assert_str(errors).contains("radius_m is 0.1, outside 0.2 to 10")
	assert_str(errors).contains("repeats palette colour 1")


func test_the_mode_check_refuses_circles_and_packages_sharing_a_spawn_tag() -> void:
	var mode := FixtureDeliveryModes.basic()
	var delivery := FixtureDeliveryModes.delivery_of(mode)
	delivery.circle.spawn_tag = delivery.package.spawn_tag
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Delivery delivery: circle and package share spawn tag package")


## Item id -> the id of its circle, from the task states.
func _circle_by_package(game: Match) -> Dictionary[int, int]:
	var found: Dictionary[int, int] = {}
	for id: int in game.state.tasks:
		var task_state := game.state.tasks[id].state as Delivery.State
		for i in task_state.packages.size():
			found[task_state.packages[i]] = task_state.circles[i]
	return found


func _emitted_named(game: Match, event_name: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event.event_name() == event_name:
			found.append(emitted)
	return found


func _item_spots(game: Match) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for id: int in game.state.items:
		found.append(game.state.items[id].position)
	return found


func _station_spots(game: Match) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for id: int in game.state.stations:
		found.append(game.state.stations[id].position)
	return found


func test_a_circle_that_forgot_its_radius_is_refused() -> void:
	var mode := FixtureDeliveryModes.basic()
	var circle := StationKind.new()
	circle.id = &"circle"
	circle.spawn_tag = &"circle"
	circle.palette = PackedColorArray(FixtureDeliveryModes.PALETTE)
	FixtureDeliveryModes.delivery_of(mode).circle = circle
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("station kind circle radius_m is 0, outside 0.2 to 10")


## `mode` with a `tool` placed on the first package marker, (0, 0, -20), at the start of the deal
## row, before Delivery deals.
func _with_a_tool_on_the_first_package_marker(mode: GameMode) -> GameMode:
	var tool := FixtureSpawnItem.new()
	tool.kind = mode.find_item_kind(&"tool")
	tool.at = Vector3(0, 0, -20)
	mode.find_transition(&"lobby", &"all_ready").actions.insert(0, tool)
	return mode
