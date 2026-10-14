extends GdUnitTestSuite
## A task type plays only on the maps it lists (TaskType.maps; the Generator ADR's GE15, #803),
## on FixtureMapTaskModes: `anywhere` lists no map (every map), `map_only` the map alone. DealTasks
## draws only the types that play on the match's map and deals that map's whole pool when `tasks`
## asks for more, with no error; the demands (DealTasks.add_demands, LayoutCheck.demands_of, the
## load check) ask a map only for its own types' markers.

const MAP := FixtureBaseMode.MAP
const SMALL_MAP := FixtureBaseMode.SMALL_MAP


func test_a_type_is_never_drawn_on_a_map_it_does_not_list() -> void:
	for seed_value in range(1, 11):
		# `tasks` 1 of the two types: on the map either may be drawn, on the small map only one.
		var game := FixtureMapTaskModes.in_round(SMALL_MAP, {"tasks": 1}, seed_value)
		assert_str(game.phase_id()).is_equal("round")
		assert_array(FixtureMapTaskModes.dealt_types(game)).is_equal([&"anywhere"])
		assert_array(FixtureDealModes.items_of(game, &"lone_token")).is_empty()
		assert_array(Array(game.diagnostics)).is_empty()


func test_on_the_map_it_lists_it_is_drawn() -> void:
	var drawn: Dictionary[StringName, bool] = {}
	for seed_value in range(1, 11):
		var game := FixtureMapTaskModes.in_round(MAP, {"tasks": 1}, seed_value)
		assert_str(game.phase_id()).is_equal("round")
		for type: StringName in FixtureMapTaskModes.dealt_types(game):
			drawn[type] = true
		assert_array(Array(game.diagnostics)).is_empty()
	assert_bool(drawn.has(&"map_only")).is_true()
	assert_bool(drawn.has(&"anywhere")).is_true()


func test_tasks_above_the_maps_pool_deal_the_pool_with_no_error() -> void:
	# `tasks` is 2 by default, and the small map plays one type.
	var game := FixtureMapTaskModes.in_round(SMALL_MAP)
	assert_int(game.state.settings[&"tasks"]).is_equal(2)
	assert_str(game.phase_id()).is_equal("round")
	assert_array(FixtureMapTaskModes.dealt_types(game)).is_equal([&"anywhere"])
	assert_array(Array(game.diagnostics)).is_empty()
	var progress := game.view_of(FixtureBaseMode.HOST).events_named(&"TaskProgress")
	assert_dict(progress[-1].to_dict()).is_equal({"done": 0, "total": 1})
	# On the map both are dealt.
	var both := FixtureMapTaskModes.in_round(MAP)
	assert_array(FixtureMapTaskModes.dealt_types(both)).is_equal([&"anywhere", &"map_only"])
	assert_array(Array(both.diagnostics)).is_empty()


func test_the_demands_are_per_map() -> void:
	var mode := FixtureMapTaskModes.mode()
	var settings := mode.default_settings()
	var on_map := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, 1, {}, MAP)
	assert_int(on_map.markers[FixtureMapTaskModes.TOKEN_TAG]).is_equal(1)
	assert_int(on_map.markers[FixtureMapTaskModes.LONE_TAG]).is_equal(2)
	var on_small := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, 1, {}, SMALL_MAP)
	assert_int(on_small.markers[FixtureMapTaskModes.TOKEN_TAG]).is_equal(1)
	assert_bool(on_small.markers.has(FixtureMapTaskModes.LONE_TAG)).is_false()
	assert_bool(on_small.no_task_types).is_false()
	# No map in particular: every type, the worst case over the maps.
	var anywhere := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, 1)
	assert_int(anywhere.markers[FixtureMapTaskModes.LONE_TAG]).is_equal(2)
	# DealTasks asked directly, with its Demands' map.
	var deal := mode.find_transition(&"loading", LoadingPhase.ALL_LOADED).actions[0] as DealTasks
	var small := Demands.new(mode, SMALL_MAP)
	deal.add_demands(settings, 1, small)
	assert_dict(small.markers).is_equal({FixtureMapTaskModes.TOKEN_TAG: 1})


func test_the_settings_changed_shows_the_chosen_maps_demands() -> void:
	var game := FixtureMapTaskModes.started()
	FixtureBaseMode.join(game, FixtureBaseMode.HOST)
	var changed := FixtureBanModes.last_change(game, FixtureBaseMode.HOST)
	assert_int(changed.needed_markers[FixtureMapTaskModes.LONE_TAG]).is_equal(2)
	FixtureModes.send(
		game,
		Intents.CHANGE_SETTINGS,
		FixtureBaseMode.HOST,
		{"map": SMALL_MAP, "settings": {"knives": 1}}
	)
	changed = FixtureBanModes.last_change(game, FixtureBaseMode.HOST)
	assert_bool(changed.needed_markers.has(FixtureMapTaskModes.LONE_TAG)).is_false()
	assert_array(changed.shortfalls).is_empty()


func test_a_map_with_none_of_a_types_markers_passes_the_load_check_when_the_type_skips_it() -> void:
	# The small map has no `lone` marker, and only `map_only` places on that tag.
	var mode := FixtureMapTaskModes.mode()
	assert_array(Array(LayoutCheck.run(mode, FixtureMapTaskModes.layouts()))).is_empty()
	assert_array(Array(FixtureMapTaskModes.started().refusals)).is_empty()
	# The same type on every map: the small map must hold its markers.
	(mode.task_types[1] as TaskType).maps = PackedStringArray()
	assert_array(Array(LayoutCheck.run(mode, FixtureMapTaskModes.layouts()))).is_equal(
		["fixture://small_map has no lone marker, which the row loading, all_loaded places on"]
	)


## A map on which no task type plays at the defaults is a data mistake the load check refuses
## (#800, the engineer's follow-up of #853), not only the lobby's fit check (`no_task_types`).
func test_a_map_no_task_type_plays_on_fails_the_load_check() -> void:
	var mode := FixtureMapTaskModes.mode()
	(mode.task_types[0] as TaskType).maps = PackedStringArray([MAP])
	assert_array(Array(LayoutCheck.run(mode, FixtureMapTaskModes.layouts()))).is_equal(
		[
			(
				"fixture://small_map has no task type that plays on it, which the row loading,"
				+ " all_loaded deals"
			)
		]
	)
	# With `tasks` at 0 by default no row deals a task, so no map needs a type.
	for i in mode.settings.size():
		if mode.settings[i].id == &"tasks":
			mode.settings[i] = FixtureModes.setting(&"tasks", 0, 0, 2)
	assert_array(Array(LayoutCheck.run(mode, FixtureMapTaskModes.layouts()))).is_empty()
