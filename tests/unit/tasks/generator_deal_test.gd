extends GdUnitTestSuite
## The Generator's deal (the Generator ADR's rule 2.1, GD2, GE5, GE9, GE14; ARCHITECTURE
## §3.3, §9.5): the generator's station on the one `generator` marker, then a switch station on N
## of the `switch` markers, N the subtasks setting, drawn from the purpose `switches_rng`; the
## other markers get no station; ids the generator first, then the switches in level order;
## StationPlaced in id order, then the charge's ZoneProgress at 0, then the task's TaskState and
## TaskProgress. With N = 0 the generator is placed and done, its progress goes out full, and a
## press is refused `unavailable`. Driven on FixtureGeneratorModes; fixture values only.

const P1 := 1
const P2 := 2
## The tick of the deal: the match has not ticked yet.
const DEAL_TICK := 0


func test_the_deal_places_the_generator_and_n_switches() -> void:
	var game := _dealt(2, [P1])
	assert_int(game.state.tasks.size()).is_equal(1)
	var task := FixtureGeneratorModes.task_of(game)
	assert_str(task.type.id).is_equal("generator")
	assert_int(task.state.total()).is_equal(2)
	assert_int(task.state.done_count()).is_equal(0)
	assert_bool(task.state.is_done()).is_false()
	assert_int(game.state.stations.size()).is_equal(3)
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_array(task_state.on).is_equal([false, false])
	assert_int(task_state.ticks).is_equal(0)
	assert_bool(task_state.running).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_generator_comes_first_then_the_switches_in_level_order() -> void:
	var game := _dealt(3, [P1])
	var task_state := FixtureGeneratorModes.state_of(game)
	var ids: Array = game.state.stations.keys()
	ids.sort()
	assert_int(task_state.generator).is_equal(ids[0])
	assert_array(Array(task_state.switches)).is_equal(ids.slice(1))
	var button := game.state.stations[task_state.generator]
	assert_str(button.kind.id).is_equal("generator")
	assert_vector(button.position).is_equal(FixtureGeneratorModes.GENERATOR_AT)
	var previous := -INF
	for id: int in task_state.switches:
		var station := game.state.stations[id]
		assert_str(station.kind.id).is_equal("switch")
		assert_bool(FixtureGeneratorModes.SWITCH_SPOTS.has(station.position)).is_true()
		assert_float(station.position.x).is_greater(previous)
		previous = station.position.x


func test_the_markers_not_drawn_get_no_station() -> void:
	for active: int in [0, 1, 2, 3, 4]:
		var game := _dealt(active, [P1])
		var used := 0
		for spot: Vector3 in FixtureGeneratorModes.SWITCH_SPOTS:
			if _spots(game).has(spot):
				used += 1
		assert_int(used).override_failure_message(str(active)).is_equal(active)
		assert_int(game.state.stations.size()).is_equal(active + 1)


func test_everyone_sees_the_stations_then_the_charge_at_zero_then_the_task() -> void:
	var game := _dealt(2, [P1, P2])
	var task_state := FixtureGeneratorModes.state_of(game)
	for peer: int in [P1, P2]:
		var names := FixtureGeneratorModes.stream(
			game, peer, [&"StationPlaced", &"ZoneProgress", &"TaskState", &"TaskProgress"]
		)
		(
			assert_array(names)
			. is_equal(
				[
					&"StationPlaced",
					&"StationPlaced",
					&"StationPlaced",
					&"ZoneProgress",
					&"TaskState",
					&"TaskProgress",
				]
			)
		)
		var placed: Array[Dictionary] = []
		for event: MatchEvent in game.view_of(peer).events_named(&"StationPlaced"):
			placed.append(event.to_dict())
		var ids: Array[int] = [task_state.generator]
		ids.append_array(Array(task_state.switches))
		for i in ids.size():
			var station := game.state.stations[ids[i]]
			assert_dict(placed[i]).is_equal(
				{
					"station": ids[i],
					"kind": station.kind.id,
					"colour": Color.WHITE,
					"position": station.position
				}
			)
		assert_array(FixtureGeneratorModes.progress(game, peer)).is_equal(
			[FixtureGeneratorModes.sent(task_state.generator, 0, false, DEAL_TICK)]
		)
		assert_dict(game.view_of(peer).events_named(&"TaskState")[0].to_dict()).is_equal(
			{
				"task": FixtureGeneratorModes.task_of(game).id,
				"type": &"generator",
				"done": 0,
				"total": 2
			}
		)
	assert_array(game.view_of(P1).events_named(&"SwitchChanged")).is_empty()


func test_the_same_seed_deals_the_same_and_the_seed_moves_the_switches() -> void:
	var first := _dealt(2, [P1, P2], 11)
	var again := _dealt(2, [P1, P2], 11)
	assert_array(FixtureModes.describe(again)).is_equal(FixtureModes.describe(first))
	var draws := {}
	for seed_value in 12:
		draws[str(_spots(_dealt(2, [P1], seed_value)))] = true
	assert_int(draws.size()).is_greater(1)


func test_the_switches_draw_from_their_own_purpose() -> void:
	var own: Array[String] = []
	var other: Array[String] = []
	for seed_value in 12:
		own.append(str(_spots(_dealt(2, [P1], seed_value))))
		var mode := FixtureGeneratorModes.basic(2)
		FixtureGeneratorModes.type_of(mode).switches_rng = &"other_switches"
		other.append(str(_spots(FixtureGeneratorModes.in_round(mode, [P1], {}, {}, seed_value))))
	assert_array(other).is_not_equal(own)


func test_zero_switches_place_the_generator_done_and_its_progress_full() -> void:
	var game := _dealt(0, [P1, P2])
	var task := FixtureGeneratorModes.task_of(game)
	assert_int(task.state.total()).is_equal(0)
	assert_bool(task.state.is_done()).is_true()
	assert_bool(Tasks.all_done(game.state)).is_true()
	assert_int(game.state.stations.size()).is_equal(1)
	var button := FixtureGeneratorModes.button_of(game)
	assert_bool(game.state.stations[button].done).is_true()
	var full := FixtureGeneratorModes.sent(button, FixtureGeneratorModes.NEEDED, false, DEAL_TICK)
	assert_array(FixtureGeneratorModes.progress(game, P2)).is_equal([full])
	assert_dict(game.view_of(P1).events_named(&"TaskProgress")[0].to_dict()).is_equal(
		{"done": 0, "total": 0}
	)
	FixtureGeneratorModes.use(game, P1, button)
	FixtureModes.run_ticks(game, 10)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(game.view_of(P2).events_named(&"ButtonPressed")).is_empty()
	assert_array(FixtureGeneratorModes.progress(game, P2)).is_equal([full])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_map_short_of_markers_deals_nothing_and_says_so() -> void:
	# The load check (LayoutCheck) refuses such a map, so the shortfall comes in after the start:
	# a setting above the markers, then a generator kind whose tag the map lacks.
	var short_switches := _joined(FixtureGeneratorModes.basic(4))
	short_switches.state.settings[&"active_switches"] = 5
	_set_ready(short_switches)
	assert_str(short_switches.phase_id()).is_equal("round")
	assert_int(short_switches.state.tasks.size()).is_equal(0)
	assert_dict(short_switches.state.stations).is_empty()
	assert_str(short_switches.diagnostics[0]).contains(
		"5 switches need a generator marker and as many switch markers; the map has 1 and 4"
	)
	assert_array(short_switches.view_of(P1).events_named(&"StationPlaced")).is_empty()
	var mode := FixtureGeneratorModes.basic(0)
	var no_generator := _joined(mode)
	FixtureGeneratorModes.type_of(mode).generator.spawn_tag = &"elsewhere"
	_set_ready(no_generator)
	assert_int(no_generator.state.tasks.size()).is_equal(0)
	assert_str(no_generator.diagnostics[0]).contains("the map has 0 and 4")


func test_reset_match_and_a_new_round_deal_afresh() -> void:
	var game := FixtureGeneratorModes.in_round(FixtureGeneratorModes.winning(2), [P1, P2])
	FixtureGeneratorModes.switch_all_on(game, P1)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.button_of(game))
	FixtureModes.run_ticks(game, 5)
	game.state.clock_ticks_left = 1
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_dict(game.state.tasks).is_empty()
	assert_dict(game.state.stations).is_empty()
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_int(task_state.ticks).is_equal(0)
	assert_bool(task_state.running).is_false()
	assert_array(task_state.on).is_equal([false, false])


## A round of the generator fixture mode with `active` switches, `peers` joined.
func _dealt(active: int, peers: Array[int], seed_value: int = 7) -> Match:
	return FixtureGeneratorModes.in_round(
		FixtureGeneratorModes.basic(active), peers, {}, {}, seed_value
	)


func _spots(game: Match) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for id: int in game.state.stations:
		found.append(game.state.stations[id].position)
	return found


## A match of `mode` on the fixture layouts, P1 joined, still in the lobby.
func _joined(mode: GameMode) -> Match:
	var game := FixtureGeneratorModes.in_round(mode, [])
	FixtureModes.send(game, Intents.HELLO, P1, {"name": "p1"})
	return game


func _set_ready(game: Match) -> void:
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
