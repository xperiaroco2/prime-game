extends GdUnitTestSuite
## DealTasks (ARCHITECTURE §3.3, §9.4; the engineer's decision of 2026-09-30, #79), with fake task
## types: `tasks` different task types drawn at random (purpose `task_types`) from the mode's
## task types minus the banned ones, each dealing one shared task in the mode's order; then
## TaskProgress to everyone. Its demands hold for any draw, and its settings_problem refuses
## more tasks than types left.

const P1 := 1
const P2 := 2
const P3 := 3


## A task type that only demands `items` item markers and `stations` station markers and colours.
class Demanding:
	extends TaskType

	var items := 0
	var stations := 0
	var station: StationKind

	static func of(
		type_id: StringName, item_count: int, station_count: int, kind: StationKind
	) -> Demanding:
		var made := Demanding.new()
		made.id = type_id
		made.description = "A demanding task."
		made.items = item_count
		made.stations = station_count
		made.station = kind
		return made

	func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
		into.add_markers(FixtureDealModes.ITEM_TAG, items)
		into.add_markers(station.spawn_tag, stations)
		into.add_colours(station, stations)


func test_it_draws_different_task_types_and_deals_one_shared_task_of_each() -> void:
	var mode := FixtureDealModes.deal_mode(_three_types())
	var game := FixtureDealModes.dealt(mode, [P1, P2], {&"tasks": 2})
	var types := _dealt_types(game)
	assert_int(types.size()).is_equal(2)
	assert_bool(types[0] != types[1]).is_true()
	# Dealt in the mode's order, whatever the draw.
	assert_bool(_mode_index(mode, types[0]) < _mode_index(mode, types[1])).is_true()
	for id: int in game.state.tasks:
		assert_int(game.state.tasks[id].state.total()).is_equal(2)
	assert_array(Array(game.diagnostics)).is_empty()


func test_all_the_types_of_the_pool_are_each_dealt_once() -> void:
	var mode := FixtureDealModes.deal_mode(_three_types())
	var game := FixtureDealModes.dealt(mode, [P1], {&"tasks": 3})
	assert_array(_dealt_types(game)).is_equal([&"first", &"second", &"third"])


func test_a_banned_type_is_never_drawn() -> void:
	for seed_value in range(1, 21):
		var game := FixtureDealModes.dealt(
			FixtureDealModes.deal_mode(_three_types()),
			[P1],
			{&"tasks": 2},
			seed_value,
			FixtureDealModes.ITEM_MARKERS,
			PackedStringArray(["second"])
		)
		assert_array(_dealt_types(game)).is_equal([&"first", &"third"])


func test_the_same_seed_draws_the_same_and_the_draw_is_random() -> void:
	var drawn := {}
	for seed_value in range(1, 21):
		var game := _one_of_three(seed_value)
		var again := _one_of_three(seed_value)
		assert_array(_dealt_types(again)).is_equal(_dealt_types(game))
		assert_array(FixtureModes.describe(again)).is_equal(FixtureModes.describe(game))
		drawn[_dealt_types(game)[0]] = true
	# One type of three over 20 seeds: each seed's draw is its own.
	assert_int(drawn.size()).is_greater(1)


func test_the_draw_has_its_own_rng_purpose() -> void:
	var moved := false
	for seed_value in range(1, 21):
		var game := _one_of_three(seed_value)
		var mode := FixtureDealModes.deal_mode(_three_types())
		(mode.transitions[0].actions[1] as DealTasks).rng_purpose = &"other_purpose"
		var other := FixtureDealModes.dealt(mode, [P1, P2, P3], {&"tasks": 1}, seed_value)
		moved = moved or _dealt_types(other) != _dealt_types(game)
		# Another purpose for the draw leaves the roles' draw where it was.
		for peer: int in [P1, P2, P3]:
			assert_str(other.state.player(peer).role).is_equal(game.state.player(peer).role)
	assert_bool(moved).is_true()


func test_nobody_owns_a_task_and_everyone_learns_the_same_progress() -> void:
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(_three_types()), [P1, P2, P3], {&"tasks": 2}
	)
	var progress := _emitted_named(game, &"TaskProgress")
	assert_int(progress.size()).is_equal(1)
	assert_array(Array(progress[0].recipients)).is_equal([P1, P2, P3])
	assert_dict(progress[0].event.to_dict()).is_equal({"done": 0, "total": 4})
	# TaskProgress comes after the task types' events and before the knives.
	var names := FixtureModes.names(game)
	assert_int(names.find(&"TaskProgress")).is_greater(names.find(&"ItemSpawned"))
	assert_int(names.find(&"TaskProgress")).is_less(names.find(&"PlayersPlaced"))


func test_every_dealt_task_is_announced_to_everyone_in_id_order_before_the_progress() -> void:
	# The task screen's data (E30): one TaskState per task, after the task types' events.
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(_three_types()), [P1, P2, P3], {&"tasks": 2}
	)
	var states := _emitted_named(game, &"TaskState")
	assert_int(states.size()).is_equal(2)
	var ids := game.state.tasks.keys()
	ids.sort()
	for i in states.size():
		var task := game.state.tasks[ids[i] as int]
		assert_array(Array(states[i].recipients)).is_equal([P1, P2, P3])
		assert_dict(states[i].event.to_dict()).is_equal(
			{"task": task.id, "type": task.type.id, "done": 0, "total": 2}
		)
	var names := FixtureModes.names(game)
	assert_int(names.find(&"TaskState")).is_greater(
		names.rfind(&"ItemSpawned", names.find(&"TaskProgress"))
	)
	assert_int(names.rfind(&"TaskState")).is_less(names.find(&"TaskProgress"))


func test_zero_tasks_deals_nothing_and_every_task_is_done() -> void:
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [P1, P2], {&"tasks": 0})
	assert_dict(game.state.tasks).is_empty()
	assert_array(FixtureDealModes.items_of(game, &"token")).is_empty()
	assert_dict(game.view_of(P1).events_named(&"TaskProgress")[0].to_dict()).is_equal(
		{"done": 0, "total": 0}
	)
	assert_array(game.view_of(P1).events_named(&"TaskState")).is_empty()
	assert_bool(Tasks.all_done(game.state)).is_true()


func test_its_demand_is_the_largest_demands_of_the_types_left_per_tag() -> void:
	# Per tag the sum of the `tasks` largest demands among the types not banned: any draw fits.
	var mode := FixtureDealModes.deal_mode(_demanding_types())
	var deal := mode.transitions[0].actions[1] as DealTasks
	assert_dict(_markers(deal, mode, 1)).is_equal({&"item": 5, FixtureDealModes.STATION_TAG: 4})
	assert_dict(_colours(deal, mode, 1)).is_equal({&"circle": 4})
	assert_dict(_markers(deal, mode, 2)).is_equal({&"item": 7, FixtureDealModes.STATION_TAG: 5})
	assert_dict(_colours(deal, mode, 2)).is_equal({&"circle": 5})
	# Banned, `big` no longer counts.
	var banned := PackedStringArray(["big"])
	assert_dict(_markers(deal, mode, 1, banned)).is_equal(
		{&"item": 2, FixtureDealModes.STATION_TAG: 4}
	)
	# Every draw of one type fits the demand for one: neither alone needs 5 items and 4 stations.
	for type: TaskType in mode.task_types:
		var own := Demands.new(mode)
		type.add_demands({}, 2, own)
		for tag: StringName in own.markers:
			assert_int(own.markers[tag]).is_less_equal(_markers(deal, mode, 1)[tag])


func test_without_a_mode_it_demands_nothing() -> void:
	var deal := FixtureDealModes.deal_tasks()
	var none := Demands.new(null)
	deal.add_demands({&"tasks": 1}, 4, none)
	assert_dict(none.markers).is_empty()


func test_its_settings_problem_refuses_more_tasks_than_types_left() -> void:
	var mode := FixtureDealModes.deal_mode(_three_types())
	var deal := mode.transitions[0].actions[1] as DealTasks
	var none: Dictionary[StringName, PackedStringArray] = {}
	var one: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["first"])
	}
	var all: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["first", "second", "third"])
	}
	assert_str(deal.settings_problem({&"tasks": 3}, none, mode)).is_empty()
	assert_str(deal.settings_problem({&"tasks": 2}, one, mode)).is_empty()
	assert_str(deal.settings_problem({&"tasks": 3}, one, mode)).is_equal("out_of_bounds")
	# Every type banned is refused even with 0 tasks.
	assert_str(deal.settings_problem({&"tasks": 0}, all, mode)).is_equal("out_of_bounds")


func test_the_mode_check_refuses_it_without_its_settings_or_purpose() -> void:
	var mode := FixtureDealModes.deal_mode()
	var deal := mode.transitions[0].actions[1] as DealTasks
	deal.tasks_setting = &""
	deal.rng_purpose = &""
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("DealTasks has no tasks_setting")
	assert_str(errors).contains("DealTasks has an empty rng_purpose")
	deal.tasks_setting = &"tasks_left"
	assert_str("\n".join(ModeCheck.run(mode).errors)).contains(
		"tasks_setting names setting tasks_left, which the mode does not declare"
	)


func test_the_mode_check_refuses_more_tasks_than_task_types_and_wrong_kinds() -> void:
	var mode := FixtureDealModes.deal_mode()
	var deal := mode.transitions[0].actions[1] as DealTasks
	mode.find_setting(&"tasks").max_value = 2
	deal.banned_setting = &"knives"
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("DealTasks: setting tasks goes up to 2, the mode has 1 task types")
	assert_str(errors).contains("DealTasks: setting knives is not a set of task types")
	deal.tasks_setting = &"banned_task_types"
	assert_str("\n".join(ModeCheck.run(mode).errors)).contains(
		"DealTasks: setting banned_task_types is not a whole number"
	)


func test_stations_reach_everyone_in_id_order_with_their_items_colours() -> void:
	# The chain Delivery's deal emits (§9.5): StationPlaced to every peer in station-id order, and
	# each item's ItemSpawned carries its station and that station's colour.
	var circle := StationKind.new()
	circle.id = &"circle"
	circle.spawn_tag = FixtureDealModes.STATION_TAG
	for i in 6:
		circle.palette.append(Color.from_hsv(i / 6.0, 1.0, 1.0))
	var type := FixtureDealtTaskType.new(&"fixture_dealt", FixtureDealModes.item_kind(&"token"), 6)
	type.station = circle
	var peers: Array[int] = [P1, P2, P3]
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


## Three fake task types, `first`, `second` and `third`, of two tokens each.
func _three_types() -> Array[TaskType]:
	var token := FixtureDealModes.item_kind(&"token")
	return [
		FixtureDealtTaskType.new(&"first", token, 2),
		FixtureDealtTaskType.new(&"second", token, 2),
		FixtureDealtTaskType.new(&"third", token, 2),
	]


## `big`: 5 item markers and 1 station marker; `wide`: 2 item markers and 4 station markers;
## as many `circle` colours as station markers.
func _demanding_types() -> Array[TaskType]:
	var circle := StationKind.new()
	circle.id = &"circle"
	circle.spawn_tag = FixtureDealModes.STATION_TAG
	circle.palette = PackedColorArray([Color.RED, Color.BLUE])
	return [Demanding.of(&"big", 5, 1, circle), Demanding.of(&"wide", 2, 4, circle)]


func _one_of_three(seed_value: int) -> Match:
	return FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(_three_types()), [P1, P2, P3], {&"tasks": 1}, seed_value
	)


func _markers(
	deal: DealTasks, mode: GameMode, tasks: int, banned: PackedStringArray = PackedStringArray()
) -> Dictionary[StringName, int]:
	return _demands(deal, mode, tasks, banned).markers


func _colours(deal: DealTasks, mode: GameMode, tasks: int) -> Dictionary[StringName, int]:
	return _demands(deal, mode, tasks, PackedStringArray()).colours


func _demands(deal: DealTasks, mode: GameMode, tasks: int, banned: PackedStringArray) -> Demands:
	var demands := Demands.new(mode)
	demands.id_sets[&"banned_task_types"] = banned
	deal.add_demands({&"tasks": tasks}, 2, demands)
	return demands


## The ids of the task types of the match's tasks, in task-id order.
func _dealt_types(game: Match) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: int in game.state.tasks:
		found.append(game.state.tasks[id].type.id)
	return found


func _mode_index(mode: GameMode, type_id: StringName) -> int:
	for i in mode.task_types.size():
		if mode.task_types[i].id == type_id:
			return i
	return -1


func _emitted_named(game: Match, event_name: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event.event_name() == event_name:
			found.append(emitted)
	return found
