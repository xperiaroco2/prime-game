extends GdUnitTestSuite
## The mode check over `content/` (ARCHITECTURE §9.1): every game mode in `content/modes/` loads as
## a GameMode and passes ModeCheck. The check with the levels' layouts runs on the real levels
## from 2j, when the marker reader exists; until then a match of the base mode is created with
## layouts built in code. Also the base mode's data that 2b settles: its numbers, and ResetMatch
## before PlacePlayers on `End -> Lobby`; and the deal that 2c adds: the actions of the
## `Loading, all_loaded -> Round` row in order, the Crew, Dissident and Knife entries, and that
## row run by a match entering the round (roles, Delivery, knives, placement). One of
## the two tests that load `content/` (§9.6).

const MODES_DIR := "res://content/modes/"
const BASE_MODE := "res://content/modes/base_mode.tres"


func test_every_mode_in_content_passes_the_mode_check() -> void:
	var paths := _mode_paths(MODES_DIR)
	assert_array(paths).contains(["res://content/modes/base_mode.tres"])
	for path: String in paths:
		var mode := load(path) as GameMode
		assert_object(mode).override_failure_message("%s is not a GameMode" % path).is_not_null()
		if mode == null:
			continue
		var check := ModeCheck.run(mode)
		(
			assert_array(Array(check.errors))
			. override_failure_message("%s: %s" % [path, "\n".join(check.errors)])
			. is_empty()
		)


func test_a_match_of_the_base_mode_starts_in_the_lobby() -> void:
	var mode := _base_mode()
	var game := Match.new(mode, 1, FlatWorldQuery.new(), _layouts_for(mode))
	assert_array(Array(game.refusals)).is_empty()
	assert_bool(game.start(0)).is_true()
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.command_log.mode_path).is_equal("res://content/modes/base_mode.tres")
	assert_int(game.command_log.mode_hash).is_equal(ContentHash.of(mode))


func test_the_base_mode_writes_its_numbers() -> void:
	# The engineer's answer on #49: the §9.5 numbers are in the data, the class defaults neutral.
	var mode := _base_mode()
	assert_int(mode.min_players).is_equal(1)
	assert_int(mode.max_players).is_equal(10)
	assert_float(mode.find_phase(&"countdown").settings[&"seconds"]).is_equal(5.0)
	assert_float(mode.find_phase(&"loading").settings[&"deadline_seconds"]).is_equal(60.0)
	var defaults := GameMode.new()
	assert_int(defaults.min_players).is_equal(0)
	assert_int(defaults.max_players).is_equal(0)


func test_end_to_lobby_resets_the_match_before_placing_players() -> void:
	# Placed first, a ghost would still be a ghost when PlayersPlaced goes to everyone (#58).
	var mode := _base_mode()
	var row := mode.find_transition(&"end", &"back")
	assert_int(row.actions.size()).is_equal(2)
	assert_object(row.actions[0]).is_instanceof(ResetMatch)
	assert_object(row.actions[1]).is_instanceof(PlacePlayers)
	assert_str((row.actions[1] as PlacePlayers).tag).is_equal("lobby_player")


func test_the_deal_runs_roles_tasks_knives_then_placement() -> void:
	var mode := _base_mode()
	var row := mode.find_transition(&"loading", &"all_loaded")
	assert_str(row.to).is_equal("round")
	# StartClock (2h) comes last, after PlacePlayers.
	assert_int(row.actions.size()).is_greater_equal(4)
	var roles := row.actions[0] as DealRoles
	assert_object(roles).is_not_null()
	assert_int(roles.quotas.size()).is_equal(1)
	assert_str(roles.quotas[0].role.id).is_equal("dissident")
	assert_str(roles.quotas[0].count_setting).is_equal("dissidents")
	assert_int(roles.quotas[0].leave_at_least).is_equal(1)
	assert_str(roles.default_role.id).is_equal("crew")
	assert_str(roles.rng_purpose).is_equal("roles")
	var tasks := row.actions[1] as DealTasks
	assert_object(tasks).is_not_null()
	assert_str(tasks.tasks_setting).is_equal("tasks_per_player")
	var knives := row.actions[2] as SpawnItems
	assert_object(knives).is_not_null()
	assert_str(knives.kind.id).is_equal("knife")
	assert_str(knives.count_setting).is_equal("knives")
	assert_str(knives.rng_purpose).is_equal("knives")
	var place := row.actions[3] as PlacePlayers
	assert_object(place).is_not_null()
	assert_str(place.tag).is_equal("round_player")


func test_crew_and_dissident() -> void:
	var mode := _base_mode()
	var crew := mode.find_role(&"crew")
	assert_str(crew.display_name).is_equal("Crew")
	assert_str(crew.side).is_equal("crew")
	assert_bool(crew.knows_teammates).is_false()
	assert_array(crew.actions).is_empty()
	var dissident := mode.find_role(&"dissident")
	assert_str(dissident.display_name).is_equal("Dissident")
	assert_str(dissident.side).is_equal("dissidents")
	assert_bool(dissident.knows_teammates).is_true()
	assert_array(dissident.actions).is_empty()


func test_knife() -> void:
	var mode := _base_mode()
	var knife := mode.find_item_kind(&"knife")
	assert_str(knife.display_name).is_equal("Knife")
	assert_str(knife.spawn_tag).is_equal("knife")
	# The knife's Use rule is 2g's (#63).
	assert_array(knife.actions).is_empty()


func test_the_deal_demands_knife_markers_at_the_default_settings() -> void:
	var mode := _base_mode()
	var demands := Demands.new(mode)
	for action: RuleEffect in mode.find_transition(&"loading", &"all_loaded").actions:
		action.add_demands(mode.default_settings(), 10, demands)
	assert_int(demands.markers.get(&"knife", 0)).is_equal(2)
	assert_int(demands.markers.get(&"round_player", 0)).is_equal(10)


func test_entering_the_round_runs_the_whole_deal() -> void:
	# The base mode's own data from the lobby into the round, 4 players at the default settings
	# (1 dissident, 2 tasks per player, 2 subtasks per task, 2 knives).
	var mode := _base_mode()
	var layouts := _layouts_for(mode)
	var map := layouts[mode.maps[0]]
	var game := Match.new(mode, 7, FlatWorldQuery.new(), layouts)
	game.keep_history = true
	game.start(0)
	var peers: Array[int] = [1, 2, 3, 4]
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	for i in 1000:
		if game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	assert_str(game.phase_id()).is_equal("round")
	assert_array(Array(game.diagnostics)).is_empty()
	# Roles: one dissident, who alone learns the dissidents; everyone learns only its own role.
	var dissidents: Array[int] = []
	for peer: int in peers:
		var role := game.state.player(peer).role
		if role == &"dissident":
			dissidents.append(peer)
		else:
			assert_str(role).is_equal("crew")
		var told := game.view_of(peer).events_named(&"RoleAssigned")
		assert_int(told.size()).is_equal(1)
		assert_str((told[0] as RoleAssignedEvent).role).is_equal(role)
		var teammates := game.view_of(peer).events_named(&"Teammates").size()
		assert_int(teammates).is_equal(1 if role == &"dissident" else 0)
	assert_int(dissidents.size()).is_equal(1)
	# Delivery through DealTasks: 4 x 2 tasks, 16 circles and 16 packages; then 2 knives.
	assert_int(game.state.tasks.size()).is_equal(8)
	assert_int(game.state.stations.size()).is_equal(16)
	var kinds: Dictionary[StringName, int] = {}
	var taken: Dictionary[Vector3, int] = {}
	for id: int in game.state.items:
		var item := game.state.items[id]
		kinds[item.kind.id] = kinds.get(item.kind.id, 0) + 1
		assert_bool(Array(map.positions(item.kind.spawn_tag)).has(item.position)).is_true()
		assert_bool(taken.has(item.position)).is_false()
		taken[item.position] = id
	assert_dict(kinds).is_equal({&"package": 16, &"knife": 2})
	for peer: int in peers:
		var view := game.view_of(peer)
		assert_int(view.events_named(&"StationPlaced").size()).is_equal(16)
		assert_int(view.events_named(&"ItemSpawned").size()).is_equal(18)
		var assigned := view.events_named(&"TasksAssigned")
		assert_int(assigned.size()).is_equal(1)
		var tasks := (assigned[0] as TasksAssignedEvent).tasks
		assert_int(tasks.size()).is_equal(2)
		for entry: Dictionary in tasks:
			assert_int(game.state.tasks[entry["task"] as int].owner).is_equal(peer)
			assert_int((entry["subtasks"] as Array).size()).is_equal(2)
		# No package spawned inside its own circle: markers lie 10 m apart.
		assert_array(view.events_named(&"PackageDelivered")).is_empty()
	# Placement last: every player on a distinct round_player marker.
	var spots: Array[Vector3] = []
	for peer: int in peers:
		var at := game.state.player(peer).position
		assert_bool(Array(map.positions(&"round_player")).has(at)).is_true()
		assert_bool(spots.has(at)).is_false()
		spots.append(at)
	# The row's order: roles, Delivery's deal, the knives, then placement.
	var deal_events: Array[StringName] = [
		&"RoleAssigned", &"StationPlaced", &"ItemSpawned", &"TasksAssigned", &"PlayersPlaced"
	]
	var order: Array[String] = []
	for emitted: EmittedEvent in game.emitted():
		var event_name := emitted.event.event_name()
		if not deal_events.has(event_name):
			continue
		var step := String(event_name)
		if emitted.event is ItemSpawnedEvent:
			step += "(%s)" % (emitted.event as ItemSpawnedEvent).kind
		if order.is_empty() or order.back() != step:
			order.append(step)
	(
		assert_array(order)
		. is_equal(
			[
				"RoleAssigned",
				"StationPlaced",
				"ItemSpawned(package)",
				"TasksAssigned",
				"ItemSpawned(knife)",
				"PlayersPlaced",
			]
		)
	)


## Layouts built in code for the mode's levels until the marker reader exists (2j): every tag the
## rows place on, with a marker for each of the mode's players, 10 m apart.
func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var layouts: Dictionary[String, LevelLayout] = {}
	var lobby := LevelLayout.new(mode.lobby_level)
	for i in mode.max_players:
		lobby.add_marker(LayoutCheck.LOBBY_PLAYER, Vector3(i, 0, 0))
	layouts[mode.lobby_level] = lobby
	var needed := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), mode.max_players
	)
	for map: String in mode.maps:
		var layout := LevelLayout.new(map)
		var x := 0
		for tag: StringName in needed.markers:
			for i in needed.markers[tag]:
				layout.add_marker(tag, Vector3(10 * x, 0, 0))
				x += 1
		layouts[map] = layout
	return layouts


func test_the_base_mode_writes_the_mvp_player_rules() -> void:
	# PlayerRules' class defaults are 0, so each number below is written in the file (§9.5).
	var mode := load(MODES_DIR.path_join("base_mode.tres")) as GameMode
	var expected := FixtureModes.player_rules()
	for property: Dictionary in expected.get_property_list():
		var number: String = property["name"]
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var got: float = mode.player_rules.get(number)
		var want: float = expected.get(number)
		(
			assert_float(got)
			. override_failure_message("PlayerRules_base.%s is %s, not %s" % [number, got, want])
			. is_equal_approx(want, 1e-6)
		)


func _mode_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			found.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		found.append_array(_mode_paths(dir_path.path_join(sub)))
	found.sort()
	return found


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode
