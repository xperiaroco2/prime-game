extends GdUnitTestSuite
## The car repair's deal (the car repair ADR's §2.1, RD3 (g), RD4 (a), RE14; #807): a station on
## every marker in id order (the car, the panel, the bins in `parts` order, the picture), the
## needed parts drawn with no kind twice in a row, PartNeeded after the StationPlaced events, a deal
## of no parts done at once, and the exact demands.

const P1 := 1
const P2 := 2


func test_the_deal_places_every_station_in_id_order_then_names_the_first_part() -> void:
	var game := FixtureCarRepairModes.in_round(FixtureCarRepairModes.basic(3), [P1, P2])
	var task_state := FixtureCarRepairModes.state_of(game)
	assert_int(task_state.car).is_less(task_state.panel)
	assert_int(task_state.panel).is_less(task_state.bins[0])
	assert_int(task_state.bins[2]).is_less(task_state.picture)
	var placed: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(P2).events_named(&"StationPlaced"):
		var fields := event.to_dict()
		placed.append({"station": fields["station"], "kind": fields["kind"]})
	(
		assert_array(placed)
		. is_equal(
			[
				{"station": task_state.car, "kind": &"car"},
				{"station": task_state.panel, "kind": &"lift_panel"},
				{"station": task_state.bins[0], "kind": &"bin_spark_plug"},
				{"station": task_state.bins[1], "kind": &"bin_filter"},
				{"station": task_state.bins[2], "kind": &"bin_belt"},
				{"station": task_state.picture, "kind": &"part_picture"},
			]
		)
	)
	assert_vector(game.state.stations[task_state.car].position).is_equal(
		FixtureCarRepairModes.CAR_AT
	)
	assert_vector(task_state.car_end).is_equal(FixtureCarRepairModes.CAR_END_AT)
	assert_int(task_state.needed.size()).is_equal(3)
	assert_int(task_state.fitted).is_equal(0)
	assert_int(task_state.held_since).is_equal(-1)
	var names := FixtureCarRepairModes.stream(game, P1, [&"StationPlaced", &"PartNeeded"])
	assert_str(String(names[names.size() - 1])).is_equal("PartNeeded")
	var needed := game.view_of(P1).events_named(&"PartNeeded")
	assert_int(needed.size()).is_equal(1)
	assert_dict(needed[0].to_dict()).is_equal(
		{"station": task_state.picture, "kind": task_state.needed[0]}
	)
	assert_array(game.view_of(P2).events_named(&"PartNeeded")).has_size(1)


func test_the_draw_never_repeats_a_kind_and_uses_every_kind_over_seeds() -> void:
	var seen: Dictionary[StringName, bool] = {}
	var firsts: Dictionary[StringName, bool] = {}
	for seed_value: int in range(1, 41):
		var game := FixtureCarRepairModes.in_round(
			FixtureCarRepairModes.basic(FixtureCarRepairModes.MAX_PARTS), [P1], {}, {}, seed_value
		)
		var needed := FixtureCarRepairModes.state_of(game).needed
		assert_int(needed.size()).is_equal(FixtureCarRepairModes.MAX_PARTS)
		firsts[needed[0]] = true
		for i in needed.size():
			seen[needed[i]] = true
			if i > 0:
				assert_str(String(needed[i])).is_not_equal(String(needed[i - 1]))
	assert_int(seen.size()).is_equal(FixtureCarRepairModes.PARTS.size())
	assert_int(firsts.size()).is_equal(FixtureCarRepairModes.PARTS.size())


func test_the_draw_is_the_seeds_alone() -> void:
	var mode := FixtureCarRepairModes.basic(FixtureCarRepairModes.MAX_PARTS)
	var first := FixtureCarRepairModes.in_round(mode, [P1], {}, {}, 11)
	var second := FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.basic(FixtureCarRepairModes.MAX_PARTS), [P1], {}, {}, 11
	)
	assert_array(FixtureCarRepairModes.state_of(second).needed).is_equal(
		FixtureCarRepairModes.state_of(first).needed
	)


func test_with_one_kind_the_draw_gives_that_kind_every_time() -> void:
	var type := FixtureCarRepairModes.car_repair_type()
	type.parts = [type.parts[0]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_array(type.draw(4, rng)).is_equal(
		[&"spark_plug", &"spark_plug", &"spark_plug", &"spark_plug"]
	)


func test_no_parts_deals_a_done_task_whose_picture_names_none() -> void:
	var game := FixtureCarRepairModes.in_round(FixtureCarRepairModes.basic(0), [P1])
	var task_state := FixtureCarRepairModes.state_of(game)
	assert_bool(task_state.is_done()).is_true()
	assert_int(task_state.total()).is_equal(0)
	var needed := game.view_of(P1).events_named(&"PartNeeded")
	assert_dict(needed[0].to_dict()).is_equal({"station": task_state.picture, "kind": &""})
	assert_array(game.view_of(P1).events_named(&"StationPlaced")).has_size(6)
	# RD11 (a): a done task takes no new hold.
	FixtureCarRepairModes.hold(game, P1, 4)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(game.view_of(P1).events_named(&"LiftChanged")).is_empty()


func test_the_demands_are_one_marker_of_each_kind_and_of_car_end_exactly() -> void:
	var mode := FixtureCarRepairModes.basic(3)
	var into := Demands.new(mode)
	FixtureCarRepairModes.type_of(mode).add_demands({&"car_parts": 6}, 8, into)
	var tags: Array[StringName] = [
		&"car",
		&"lift_panel",
		&"bin_spark_plug",
		&"bin_filter",
		&"bin_belt",
		&"part_picture",
		&"car_end",
	]
	assert_array(into.markers.keys()).contains_exactly_in_any_order(tags)
	for tag: StringName in tags:
		assert_int(into.markers[tag]).is_equal(1)
		assert_bool(into.exact.has(tag)).is_true()
	assert_dict(into.colours).is_empty()


func test_a_map_with_two_car_markers_is_refused_by_the_layout_check() -> void:
	# Exact demands (RE14): one more car marker is a device nobody uses.
	var layouts := _lobby_layouts(FixtureCarRepairModes.CAR_END_AT)
	layouts[FixtureBaseMode.MAP].add_marker(&"car", Vector3(20, 0, 30))
	var game := Match.new(_lobby_mode(), 7, FlatWorldQuery.new(), layouts)
	assert_str(str(game.refusals)).contains(
		"fixture://map has 2 car marker(s), and the row loading, all_loaded needs exactly 1"
	)


func test_a_short_axis_holds_the_lobby_back_with_short_axis() -> void:
	# RE14: the car_end marker nearer the car marker than the car's radius (1 m).
	var near := FixtureCarRepairModes.CAR_AT + Vector3(0.6, 0, 0)
	var game := _joined_and_ready(_lobby_layouts(near))
	assert_str(String(game.phase_id())).is_equal("lobby")
	assert_array(_shortfalls(game)).is_equal(
		[
			{
				"id": HostText.SHORT_AXIS,
				"ids": PackedStringArray(["car_end", "car"]),
				"numbers": {&"need": 100, &"have": 60}
			}
		]
	)
	# The axis at the radius fits: all_ready fires.
	var fits := _joined_and_ready(_lobby_layouts(FixtureCarRepairModes.CAR_AT + Vector3(0, 0, 1)))
	assert_array(_shortfalls(fits)).is_empty()
	assert_str(String(fits.phase_id())).is_not_equal("lobby")


## FixtureBaseMode's lobby (JoinRules, FitCheck) with the car repair dealt on the map's
## `all_loaded` row.
func _lobby_mode() -> GameMode:
	var made := FixtureBaseMode.mode()
	var type := FixtureCarRepairModes.car_repair_type()
	type.maps = PackedStringArray([FixtureBaseMode.MAP])
	# The mode plays that map alone too: a map no task type plays on fails the load check (#800).
	made.maps = PackedStringArray([FixtureBaseMode.MAP])
	made.task_types = [type]
	made.item_kinds.append_array(type.parts)
	made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	made.settings.append(FixtureDealModes.banned_setting())
	made.settings.append(FixtureModes.setting(&"car_parts", 3, 0, 6))
	made.find_transition(&"loading", LoadingPhase.ALL_LOADED).actions.insert(
		0, FixtureDealModes.deal_tasks()
	)
	return made


## FixtureBaseMode's layouts with the car repair's markers on its map, `car_end` at `car_end_at`.
func _lobby_layouts(car_end_at: Vector3) -> Dictionary[String, LevelLayout]:
	var found := FixtureBaseMode.layouts()
	var car_layout := FixtureCarRepairModes.layouts(car_end_at)[FixtureModes.MAP]
	for tag: StringName in car_layout.tags():
		if tag == &"round_player" or tag == &"respawn":
			continue
		for at: Vector3 in car_layout.positions(tag):
			found[FixtureBaseMode.MAP].add_marker(tag, at)
	return found


func _joined_and_ready(layouts: Dictionary[String, LevelLayout]) -> Match:
	var game := Match.new(_lobby_mode(), 7, FlatWorldQuery.new(), layouts)
	game.keep_history = true
	game.start(0)
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.ready(game, P1)
	return game


## The shortfalls of the last SettingsChanged P1 received (the fit check's, #548).
func _shortfalls(game: Match) -> Array:
	var changed := game.view_of(P1).events_named(&"SettingsChanged")
	return changed[changed.size() - 1].to_dict()["shortfalls"]
