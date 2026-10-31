extends GdUnitTestSuite
## The ship engine's check, kinds, demands and deal (core/tasks/ship_engine.gd, ProblemKind; #1453):
## what ModeCheck refuses, which station kinds it reports and where they are placed, what it asks of
## a map, and a map short of markers. Built on FixtureEngineModes, never on content (§9.6).


func _errors(mode: GameMode) -> String:
	return ";".join(ModeCheck.run(mode).errors)


func test_the_fixture_mode_passes_the_mode_check() -> void:
	var check := ModeCheck.run(FixtureEngineModes.basic())
	assert_array(Array(check.errors)).is_empty()


func test_its_blast_needs_a_respawn_where_task_ticks_run() -> void:
	assert_bool(TaskType.new().knocks_down()).is_false()
	assert_bool(ShipEngine.new().knocks_down()).is_true()
	var mode := FixtureEngineModes.basic()
	FixtureCombatModes.life_ticks(mode).respawn = null
	assert_str(_errors(mode)).contains(
		"phase round lists TaskTicks, and task type engine can knock down"
	)


func test_the_check_refuses_a_broken_engine() -> void:
	var mode := FixtureEngineModes.basic()
	var engine := FixtureEngineModes.type_of(mode)
	engine.start = null
	engine.stage_problems = PackedInt32Array([2, 0, 17, 1, 1, 1, 1])
	engine.stage_seconds = 0.0
	engine.what_rng = engine.when_rng
	engine.kinds[1].id = &"stub_a"
	engine.kinds[0].seconds = 0.0
	engine.kinds[0].site_count = 0
	(engine.kinds[1].fixtures[0] as StationKind).spawn_tag = &"engine_aboard"
	var found := ";".join(engine.check(mode))
	for expected: String in [
		"ShipEngine engine has no start station kind",
		"ShipEngine engine has 7 stages, outside 1 to 6",
		"ShipEngine engine stage problems is 0, outside 1 to 16",
		"ShipEngine engine stage problems is 17, outside 1 to 16",
		"ShipEngine engine stage_seconds is 0, outside",
		"ShipEngine engine needs two different RNG purposes",
		"ShipEngine engine has two problem kinds with the id stub_a",
		"problem kind stub_a seconds is 0, outside",
		"problem kind stub_a has 0 sites, fewer than 1",
		"station kind fixture_b spawns on the aboard tag engine_aboard",
	]:
		assert_str(found).contains(expected)


func test_the_check_refuses_an_engine_without_kinds_and_a_station_without_its_use() -> void:
	var mode := FixtureEngineModes.basic()
	var engine := FixtureEngineModes.type_of(mode)
	engine.kinds[0].site.actions = []
	assert_str(";".join(engine.check(mode))).contains(
		"station kind site_a has no Interact rule with UseStation"
	)
	engine.stage_problems = PackedInt32Array([2])
	assert_str(";".join(engine.check(mode))).contains(
		"setting engine_stages goes up to 3, above its 1 stages"
	)
	engine.kinds = []
	assert_str(";".join(engine.check(mode))).contains("ShipEngine engine has no problem kinds")


func test_its_station_kinds_are_the_console_and_each_kind_s_in_data_order() -> void:
	var mode := FixtureEngineModes.basic()
	var engine := FixtureEngineModes.type_of(mode)
	var ids: Array[StringName] = []
	for kind: StationKind in engine.station_kinds():
		ids.append(kind.id)
		assert_object(Stations.owner_of(mode, kind)).is_same(engine)
	assert_array(ids).is_equal([&"engine_start", &"site_a", &"site_b", &"fixture_b"])


func test_it_asks_a_map_for_its_markers_whatever_the_players() -> void:
	var mode := FixtureEngineModes.basic()
	var demands := Demands.new(mode)
	FixtureEngineModes.type_of(mode).add_demands({&"engine_stages": 3}, 16, demands)
	assert_dict(demands.markers).is_equal(
		{&"engine_start": 1, &"engine_aboard": 2, &"site_a": 2, &"site_b": 3, &"fixture_b": 1}
	)
	for tag: StringName in [&"engine_start", &"engine_aboard", &"site_a", &"site_b"]:
		assert_bool(demands.exact.get(tag, false)).is_true()
	assert_bool(demands.exact.get(&"fixture_b", false)).is_false()


func test_the_deal_places_the_console_then_each_kind_s_sites_and_fixtures() -> void:
	var game := FixtureEngineModes.in_round(FixtureEngineModes.basic(), [1, 2])
	var task_state := FixtureEngineModes.state_of(game)
	var placed := FixtureEngineModes.dicts(game, 2, &"StationPlaced")
	var kinds: Array[StringName] = []
	var ids: Array[int] = []
	for station: Dictionary in placed:
		kinds.append(station["kind"] as StringName)
		ids.append(station["station"] as int)
	assert_array(kinds).is_equal(
		[&"engine_start", &"site_a", &"site_a", &"site_b", &"site_b", &"site_b", &"fixture_b"]
	)
	assert_array(ids).is_equal(Array(task_state.stations))
	assert_int(task_state.console).is_equal(ids[0])
	assert_array(Array(task_state.sites[0])).is_equal(ids.slice(1, 3))
	assert_array(Array(task_state.sites[1])).is_equal(ids.slice(3, 6))
	assert_vector(task_state.aboard_low).is_equal(FixtureEngineModes.INSIDE_LOW)
	assert_vector(task_state.aboard_high).is_equal(FixtureEngineModes.INSIDE_HIGH)
	assert_array(FixtureEngineModes.dicts(game, 2, &"ZoneProgress")).is_equal(
		[
			{
				"station": ids[0],
				"ticks": 0,
				"needed": 3 * FixtureEngineModes.STAGE_TICKS,
				"counting": false,
				"tick": game.ticked_through() + 1
			}
		]
	)
	var states := FixtureEngineModes.dicts(game, 2, &"TaskState")
	assert_int(states[0]["done"]).is_equal(0)
	assert_int(states[0]["total"]).is_equal(3)
	# A fixture takes no use by default.
	FixtureEngineModes.use(game, 1, ids[6])
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 1)).is_equal([StationUsable.UNAVAILABLE])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_map_short_of_markers_deals_nothing_and_says_so() -> void:
	# The load check (LayoutCheck) refuses such a map, so the shortfall comes in after the start: a
	# tag the map lacks, set between the join and the ready.
	var no_sites := func(engine: ShipEngine) -> void: engine.kinds[1].site.spawn_tag = &"elsewhere"
	var no_box := func(engine: ShipEngine) -> void: engine.aboard_tag = &"elsewhere"
	for change: Callable in [no_sites, no_box]:
		var mode := FixtureEngineModes.basic()
		var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureEngineModes.layouts())
		game.keep_history = true
		game.start(0)
		FixtureModes.send(game, Intents.HELLO, 1, {"name": "p1"})
		change.call(FixtureEngineModes.type_of(mode))
		FixtureModes.send(game, Intents.SET_READY, 1, {"ready": true})
		assert_str(game.phase_id()).is_equal("round")
		assert_object(FixtureEngineModes.task_of(game)).is_null()
		assert_dict(game.state.stations).is_empty()
		assert_str(";".join(game.diagnostics)).contains(
			"ShipEngine: the map is short of markers: 0 elsewhere markers of "
		)


func test_a_point_on_the_aboard_box_s_edge_is_aboard_and_one_past_it_is_not() -> void:
	var low := Vector3(0, 0, 0)
	var high := Vector3(10, 4, 10)
	assert_bool(ShipEngine.in_box(Vector3(10, 4, 10), low, high)).is_true()
	assert_bool(ShipEngine.in_box(Vector3(0, 0, 0), low, high)).is_true()
	assert_bool(ShipEngine.in_box(Vector3(10.1, 0, 5), low, high)).is_false()
	assert_bool(ShipEngine.in_box(Vector3(5, -0.1, 5), low, high)).is_false()
	assert_bool(ShipEngine.in_box(Vector3(5, 2, 10.1), low, high)).is_false()
