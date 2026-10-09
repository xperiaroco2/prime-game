extends GdUnitTestSuite
## The zone task's deal, demands and check (ARCHITECTURE §3.3, §9.4, §9.5; ZE1 of the zone task
## ADR): one shared task of N zones, N its subtasks setting, whatever the player count, on distinct
## random `zone` markers in distinct random palette colours, from its own RNG purpose; zone i is
## subtask i in station-id order, which follows the markers' level order. Fixture values only.

const P1 := 1
const P2 := 2
const P3 := 3


func test_the_deal_places_one_shared_task_of_n_zones() -> void:
	var game := _dealt(3, [P1])
	assert_int(game.state.tasks.size()).is_equal(1)
	var task := FixtureZoneModes.task_of(game)
	assert_str(task.type.id).is_equal("zone")
	assert_int(task.state.total()).is_equal(3)
	assert_int(task.state.done_count()).is_equal(0)
	assert_int(game.state.stations.size()).is_equal(3)
	var task_state := FixtureZoneModes.state_of(game)
	assert_array(Array(task_state.ticks)).is_equal([0, 0, 0])
	assert_array(task_state.counting).is_equal([false, false, false])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_player_count_does_not_change_the_deal() -> void:
	var alone := _dealt(3, [P1])
	var three := _dealt(3, [P1, P2, P3])
	assert_int(FixtureZoneModes.task_of(three).state.total()).is_equal(3)
	assert_array(_spots(three)).is_equal(_spots(alone))


func test_zone_i_is_subtask_i_and_ids_follow_level_order() -> void:
	var game := _dealt(4, [P1])
	var task_state := FixtureZoneModes.state_of(game)
	var ids: Array[int] = []
	ids.assign(Array(task_state.stations))
	var sorted := ids.duplicate()
	sorted.sort()
	assert_array(ids).is_equal(sorted)
	var previous := -INF
	for id: int in ids:
		var station := game.state.stations[id]
		assert_float(station.position.x).is_greater(previous)
		previous = station.position.x
		assert_str(station.kind.id).is_equal("zone")


func test_zones_take_distinct_markers_and_colours() -> void:
	var game := _dealt(6, [P1])
	var spots: Array[Vector3] = []
	var colours: Array[Color] = []
	for id: int in game.state.stations:
		var station := game.state.stations[id]
		assert_bool(spots.has(station.position)).is_false()
		assert_bool(colours.has(station.colour)).is_false()
		assert_bool(FixtureZoneModes.far_spots(10).has(station.position)).is_true()
		assert_bool(FixtureDeliveryModes.PALETTE.has(station.colour)).is_true()
		spots.append(station.position)
		colours.append(station.colour)


func test_everyone_sees_the_zones_in_id_order_and_nothing_private() -> void:
	var game := _dealt(3, [P1, P2])
	var expected: Array[Dictionary] = []
	for id: int in game.state.stations:
		var station := game.state.stations[id]
		expected.append(
			{"station": id, "kind": &"zone", "colour": station.colour, "position": station.position}
		)
	for peer: int in [P1, P2]:
		var placed: Array[Dictionary] = []
		for event: MatchEvent in game.view_of(peer).events_named(&"StationPlaced"):
			placed.append(event.to_dict())
		assert_array(placed).is_equal(expected)
		var task_events := game.view_of(peer).events_named(&"TaskState")
		assert_dict(task_events[0].to_dict()).is_equal(
			{"task": FixtureZoneModes.task_of(game).id, "type": &"zone", "done": 0, "total": 3}
		)
	assert_array(game.view_of(P1).events_named(&"ZoneProgress")).is_empty()


func test_the_same_seed_deals_the_same_and_another_seed_differs() -> void:
	var first := _dealt(3, [P1, P2], 11)
	var again := _dealt(3, [P1, P2], 11)
	var other := _dealt(3, [P1, P2], 12)
	assert_array(FixtureModes.describe(again)).is_equal(FixtureModes.describe(first))
	assert_array(_spots(other)).is_not_equal(_spots(first))


func test_the_zones_draw_from_their_own_purpose() -> void:
	var first := _dealt(3, [P1], 11)
	var mode := FixtureZoneModes.basic(3)
	FixtureZoneModes.zone_task_of(mode).zones_rng = &"other_zones"
	var moved := FixtureZoneModes.in_round(
		mode, [P1], FixtureZoneModes.layouts(FixtureZoneModes.far_spots(10)), {}, 11
	)
	assert_array(_spots(moved)).is_not_equal(_spots(first))


func test_adding_the_zone_task_leaves_deliverys_deal_as_it_was() -> void:
	var alone := FixtureDeliveryModes.basic(3)
	var both := FixtureDeliveryModes.basic(3)
	both.find_setting(&"tasks").max_value = 2
	both.find_setting(&"tasks").default_value = 2
	both.settings.append(FixtureModes.setting(&"zones", 3, 0, 12))
	both.task_types.append(FixtureZoneModes.zone_task())
	both.find_phase(&"round").tick_systems.append(TaskTicks.new())
	var found := FixtureDeliveryModes.layouts()
	for spot: Vector3 in FixtureZoneModes.far_spots(10):
		found[FixtureModes.MAP].add_marker(&"zone", spot + Vector3(0, 0, 20))
	var first := FixtureDeliveryModes.in_round(alone, [P1], found, null, 11)
	var second := FixtureDeliveryModes.in_round(both, [P1], found, null, 11)
	assert_int(second.state.tasks.size()).is_equal(2)
	assert_int(second.state.stations.size()).is_equal(6)
	for id: int in first.state.stations:
		assert_vector(second.state.stations[id].position).is_equal(
			first.state.stations[id].position
		)
		assert_bool(second.state.stations[id].colour == first.state.stations[id].colour).is_true()
	for id: int in first.state.items:
		assert_vector(second.state.items[id].position).is_equal(first.state.items[id].position)
	assert_array(Array(second.diagnostics)).is_empty()


func test_zero_zones_deal_a_task_with_no_subtasks_which_is_done() -> void:
	var game := _dealt(0, [P1, P2])
	assert_int(game.state.tasks.size()).is_equal(1)
	var task := FixtureZoneModes.task_of(game)
	assert_int(task.state.total()).is_equal(0)
	assert_bool(task.state.is_done()).is_true()
	assert_bool(Tasks.all_done(game.state)).is_true()
	assert_dict(game.state.stations).is_empty()
	assert_dict(game.view_of(P1).events_named(&"TaskProgress")[0].to_dict()).is_equal(
		{"done": 0, "total": 0}
	)
	FixtureModes.run_ticks(game, 3)
	assert_array(game.view_of(P1).events_named(&"ZoneProgress")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_map_without_enough_markers_deals_nothing_and_says_so() -> void:
	var game := FixtureZoneModes.in_round(
		FixtureZoneModes.basic(3), [P1], FixtureZoneModes.layouts(FixtureZoneModes.far_spots(2))
	)
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.tasks.size()).is_equal(0)
	assert_dict(game.state.stations).is_empty()
	assert_str(game.diagnostics[0]).contains("3 zones need as many zone markers and colours")
	assert_str(game.diagnostics[0]).contains("the map has 2, the palette 12")
	assert_str(game.diagnostics[0]).contains("row lobby, all_ready, deal of task type zone: ")
	assert_array(game.view_of(P1).events_named(&"StationPlaced")).is_empty()
	assert_int(game.row_error_count()).is_equal(game.diagnostics.size())
	assert_int(game.row_error_count()).is_greater(0)


func test_a_palette_too_small_deals_nothing_and_says_so() -> void:
	var mode := FixtureZoneModes.basic(3)
	FixtureZoneModes.zone_task_of(mode).zone.palette = PackedColorArray([Color.RED, Color.BLUE])
	var game := FixtureZoneModes.in_round(
		mode, [P1], FixtureZoneModes.layouts(FixtureZoneModes.far_spots(10))
	)
	assert_int(game.state.tasks.size()).is_equal(0)
	assert_str(game.diagnostics[0]).contains("the map has 10, the palette 2")


func test_demands_are_zone_markers_and_colours_per_zone() -> void:
	var mode := FixtureZoneModes.basic()
	var zone_task := FixtureZoneModes.zone_task_of(mode)
	var demands := Demands.new(mode)
	zone_task.add_demands({&"zones": 6}, 10, demands)
	assert_dict(demands.markers).is_equal({&"zone": 6})
	assert_dict(demands.colours).is_equal({&"zone": 6})
	var many := Demands.new(mode)
	zone_task.add_demands({&"zones": 13}, 1, many)
	var layout := LevelLayout.new(FixtureModes.MAP)
	for i in 13:
		layout.add_marker(&"zone", Vector3(i, 0, 0))
	assert_array(Array(demands.shortfalls(layout))).is_empty()
	assert_array(Array(many.shortfalls(layout))).is_equal(
		["13 zone colour(s) needed, the palette has 12"]
	)
	var few := LevelLayout.new(FixtureModes.MAP)
	few.add_marker(&"zone", Vector3.ZERO)
	assert_str("\n".join(demands.shortfalls(few))).contains("zone")


func test_the_fixture_modes_pass_the_mode_check() -> void:
	assert_array(Array(ModeCheck.run(FixtureZoneModes.basic()).errors)).is_empty()
	assert_array(Array(ModeCheck.run(FixtureZoneModes.winning()).errors)).is_empty()


func test_the_mode_check_refuses_a_zone_task_without_its_parts() -> void:
	var mode := FixtureZoneModes.basic()
	var zone_task := FixtureZoneModes.zone_task_of(mode)
	zone_task.zone = null
	zone_task.subtasks_setting = &""
	zone_task.zones_rng = &""
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("ZoneTask zone has no zone station kind")
	assert_str(errors).contains("ZoneTask zone has no subtasks_setting")
	assert_str(errors).contains("ZoneTask zone has an empty RNG purpose")


func test_the_mode_check_refuses_an_undeclared_setting() -> void:
	var mode := FixtureZoneModes.basic()
	FixtureZoneModes.zone_task_of(mode).subtasks_setting = &"spots"
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains(
		"subtasks_setting names setting spots, which the mode does not declare"
	)


func test_seconds_must_be_within_the_channels_bounds_and_default_outside_them() -> void:
	assert_float(ZoneTask.new().seconds).is_equal(0.0)
	var cases := {0.0: "is 0, outside", 0.04: "is 0.04, outside", 601.0: "is 601, outside"}
	for seconds: float in cases:
		var mode := FixtureZoneModes.basic(1, seconds)
		var errors := "\n".join(ModeCheck.run(mode).errors)
		assert_str(errors).contains("ZoneTask zone seconds %s 0.05 to 600" % cases[seconds])
	for seconds: float in [0.05, 600.0]:
		assert_array(Array(ModeCheck.run(FixtureZoneModes.basic(1, seconds)).errors)).is_empty()


func test_the_time_is_converted_once_and_is_at_least_one_tick() -> void:
	var zone_task := FixtureZoneModes.zone_task()
	var cases := {1.0: 20, 0.05: 1, 0.04: 1, 0.99: 19, 10.0: 200, 600.0: 12000}
	for seconds: float in cases:
		zone_task.seconds = seconds
		assert_int(zone_task.needed_ticks()).override_failure_message(str(seconds)).is_equal(
			cases[seconds]
		)


func test_it_ticks() -> void:
	assert_bool(ZoneTask.new().has_tick()).is_true()


## A round of the zone fixture mode with `zones` zones on 10 far markers, `peers` joined.
func _dealt(zones: int, peers: Array[int], seed_value: int = 7) -> Match:
	return FixtureZoneModes.in_round(
		FixtureZoneModes.basic(zones),
		peers,
		FixtureZoneModes.layouts(FixtureZoneModes.far_spots(10)),
		{},
		seed_value
	)


func _spots(game: Match) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for id: int in game.state.stations:
		found.append(game.state.stations[id].position)
	return found
