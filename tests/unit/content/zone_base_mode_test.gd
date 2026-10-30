extends "res://tests/unit/content/content_modes_test.gd"
## The base mode with the zone task (#649's base mode, ZD8 (a)), on the fixture
## FixtureBaseModeWithZones: the engineer took the zone task out of the shipped base mode on #842
## ("only from the mode, now"), so the checks content_modes_test and lone_player_test made of the
## base mode dealing both task types run here, with the same assertions, on the House in the
## host's world, the one map the zone task plays on (TaskType.maps, GD13 (b), #804; the
## greybox until then): entering the round deals
## Delivery and the zone, in the row's order; a whole match where the crew holds the zone and
## delivers every package, then one that runs out of time; and a lone engineer who must do both.
## Extends content_modes_test for its helpers; GdUnit4 runs only this script's own tests.

const LONE := 1


func test_entering_the_round_runs_the_whole_deal_with_the_zone() -> void:
	# The fixture's data from the lobby into the round, 4 players at the default settings
	# (1 dissident; 2 tasks: the House's Delivery by meaning's 6 items on its 4 drop-offs (#828)
	# and Hold the zone's 1 zone; 2 knives).
	var mode := FixtureBaseModeWithZones.mode()
	var world := _house_world(mode)
	var layouts := _house_layouts(mode, world)
	# The zone task plays on the House alone (GD13 (b), #804), in the host's world.
	var map := layouts[HOUSE]
	var game := Match.new(mode, 7, world, layouts)
	game.state.map = HOUSE
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
	_pregame_in_silence_then_round(game, peers)
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
	# Both task types the House plays drawn by DealTasks (#649, ZD8 (a)): Delivery by meaning's
	# 4 drop-offs and 6 items (every route at least once, #828), then Hold the zone's 1 zone on a
	# `zone` marker; then 2 knives.
	assert_int(game.state.tasks.size()).is_equal(2)
	assert_int(game.state.stations.size()).is_equal(5)
	var zone := FixtureZoneModes.zone_of(game, 0)
	assert_bool(Array(map.positions(&"zone")).has(zone.position)).is_true()
	var kinds: Dictionary[StringName, int] = {}
	var taken: Dictionary[Vector3, int] = {}
	for id: int in game.state.items:
		var item := game.state.items[id]
		kinds[item.kind.id] = kinds.get(item.kind.id, 0) + 1
		assert_bool(Array(map.positions(item.kind.spawn_tag)).has(item.position)).is_true()
		assert_bool(taken.has(item.position)).is_false()
		taken[item.position] = id
	assert_int(kinds.get(&"knife", 0)).is_equal(2)
	var routed := 0
	for kind: StringName in [&"wine", &"oil", &"gnome", &"parasol"]:
		assert_int(kinds.get(kind, 0)).override_failure_message(kind).is_greater_equal(1)
		routed += kinds.get(kind, 0)
	assert_int(routed).is_equal(6)
	assert_int(kinds.size()).is_equal(5)
	for peer: int in peers:
		var view := game.view_of(peer)
		assert_int(view.events_named(&"StationPlaced").size()).is_equal(5)
		assert_int(view.events_named(&"ItemSpawned").size()).is_equal(8)
		assert_dict(view.events_named(&"TaskProgress")[0].to_dict()).is_equal(
			{"done": 0, "total": 7}
		)
		# No item spawned inside its own drop-off.
		assert_array(view.events_named(&"PackageDelivered")).is_empty()
	# Placement last: every player on a distinct round_player marker.
	var spots: Array[Vector3] = []
	for peer: int in peers:
		var at := game.state.player(peer).position
		assert_bool(Array(map.positions(&"round_player")).has(at)).is_true()
		assert_bool(spots.has(at)).is_false()
		spots.append(at)
	# The row's order: roles, Delivery's deal, the zone's, the knives, then placement.
	var deal_events: Array[StringName] = [
		&"RoleAssigned", &"StationPlaced", &"ItemSpawned", &"TaskProgress", &"PlayersPlaced"
	]
	var order: Array[String] = []
	for emitted: EmittedEvent in game.emitted():
		var event_name := emitted.event.event_name()
		if not deal_events.has(event_name):
			continue
		var step := String(event_name)
		if emitted.event is ItemSpawnedEvent:
			var kind := (emitted.event as ItemSpawnedEvent).kind
			step += "(%s)" % ("knife" if kind == &"knife" else "routed")
		if order.is_empty() or order.back() != step:
			order.append(step)
	(
		assert_array(order)
		. is_equal(
			[
				"RoleAssigned",
				"StationPlaced",
				"ItemSpawned(routed)",
				"StationPlaced",
				"TaskProgress",
				"ItemSpawned(knife)",
				"PlayersPlaced",
			]
		)
	)


func test_a_whole_match_with_the_zone_to_the_end_and_back_to_the_lobby_twice() -> void:
	# The fixture's data, 4 players at the default settings: the crew holds the zone and
	# delivers the 6 items, each to its drop-off (#828), and wins; the host returns to the
	# lobby, shortens the round to 1 minute, and the second match runs out of time with every
	# item where it spawned and the zone empty: the dissidents win.
	var mode := FixtureBaseModeWithZones.mode()
	var peers: Array[int] = [1, 2, 3, 4]
	var game := _house_round(mode, peers)
	# The pregame's end tick: the step that entered the round.
	var start := game.ticked_through()
	assert_int(game.state.clock_ticks_left).is_equal(10 * 60 * Ticks.RATE)
	var crew := FixtureDealModes.players_of(game, &"crew")
	assert_int(crew.size()).is_equal(3)
	var zone := FixtureZoneModes.zone_of(game, 0)
	FixtureItemModes.stand(game, crew[0], zone.position)
	FixtureZoneModes.hold(game, [crew[0]], FixtureZoneModes.zone_task_of(mode).needed_ticks())
	assert_bool(zone.done).is_true()
	assert_str(game.phase_id()).is_equal("round")
	for index in 6:
		var item := FixtureMeaningModes.item_of(game, index)
		var drop_off := FixtureMeaningModes.station_of(game, index)
		FixtureDeliveryModes.carry_to(game, crew[index % crew.size()], item, drop_off.position)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	# The round's play time, in whole seconds (#548).
	var played := floori(
		(game.state.clock_ticks_total - game.state.clock_ticks_left) / float(Ticks.RATE)
	)
	for peer: int in peers:
		var view := game.view_of(peer)
		assert_dict(view.events_named(&"RoundStarted")[0].to_dict()).is_equal({"start_tick": start})
		assert_int(view.events_named(&"PackageDelivered").size()).is_equal(6)
		var progress := view.events_named(&"ZoneProgress")
		var last_progress := (progress[progress.size() - 1] as ZoneProgressEvent).to_dict()
		assert_int(last_progress["ticks"]).is_equal(10 * Ticks.RATE)
		var ended := view.events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		assert_dict(ended[0].to_dict()).is_equal(
			{"side": &"crew", "reason": &"every_task_done", "numbers": {&"time": played}}
		)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, 1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.state.winner).is_empty()
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, 1, {"settings": {"match_duration": 1}})
	assert_int(game.state.settings[&"match_duration"]).is_equal(1)
	_ready_and_load(game, peers)
	assert_int(game.state.clock_ticks_left).is_equal(60 * Ticks.RATE)
	FixtureWinModes.run_through(game, game.ticked_through() + 60 * Ticks.RATE)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("dissidents")
	for peer: int in peers:
		var ended := game.view_of(peer).events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(2)
		assert_dict(ended[1].to_dict()).is_equal(
			{"side": &"dissidents", "reason": &"time_up", "numbers": {&"time": 60}}
		)
	_end_in_silence_then_lobby(game, peers)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_lone_engineer_s_round_with_the_zone_ends_when_every_task_is_done() -> void:
	# lone_player_test's round (#719) with both task types: delivering every package leaves the
	# round on; holding the zone for its time then wins it for the crew.
	var mode := FixtureBaseModeWithZones.mode()
	var game := _lone_in_pregame(mode)
	FixtureModes.run_ticks(game, 3 * Ticks.RATE + 1)
	assert_str(game.phase_id()).is_equal("round")
	# The House's Delivery by meaning dealt its shared task: 6 items (the default `packages`) on
	# its 4 drop-offs (#828); the zone task its one zone (the default `zones`, #649); and the 2
	# knives lie on the map.
	assert_int(game.state.tasks.size()).is_equal(2)
	assert_int(game.state.stations.size()).is_equal(5)
	assert_int(FixtureMeaningModes.state_of(game).items.size()).is_equal(6)
	assert_int(FixtureDealModes.items_of(game, &"knife").size()).is_equal(2)
	# A minute of the round alone: the crew is present, no package is delivered and the clock
	# runs, so no win condition fires.
	FixtureWinModes.run_through(game, game.ticked_through() + 60 * Ticks.RATE)
	assert_str(game.phase_id()).is_equal("round")
	assert_str(game.state.winner).is_empty()
	assert_array(game.view_of(LONE).events_named(&"MatchEnded")).is_empty()
	assert_int(game.state.clock_ticks_left).is_equal(9 * 60 * Ticks.RATE)
	# The engineer delivers every item alone: one task of two is done, the round goes on.
	assert_object(_task_of_type(game, &"delivery")).is_same(FixtureMeaningModes.task_of(game))
	for index in 6:
		var item := FixtureMeaningModes.item_of(game, index)
		var drop_off := FixtureMeaningModes.station_of(game, index)
		FixtureDeliveryModes.carry_to(game, LONE, item, drop_off.position)
	assert_str(game.phase_id()).is_equal("round")
	# Then holds the zone alone for its time: the crew wins.
	var zone := FixtureZoneModes.zone_of(game, 0)
	FixtureItemModes.stand(game, LONE, zone.position)
	var needed := Ticks.from_seconds(FixtureZoneModes.zone_task_of(mode).seconds)
	FixtureZoneModes.hold(game, [LONE], needed + 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	var ended := game.view_of(LONE).events_named(&"MatchEnded")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0].to_dict()["reason"]).is_equal("every_task_done")
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_fixture_is_the_shipped_base_mode_plus_the_zone_task() -> void:
	# The fixture reads the shipped base mode when it loads: only the task types, the `tasks`,
	# `zones`, the Generator's `switches` and the photo task's `photos` settings and the Interact
	# accepts of Round (#800, #784), the Lobby and the Countdown (#1388) differ.
	var base := _base_mode()
	var mode := FixtureBaseModeWithZones.mode()
	assert_array(ModeCheck.run(mode).errors).is_empty()
	assert_int(mode.phases.size()).is_equal(base.phases.size())
	for i in base.phases.size():
		var own := mode.phases[i]
		var shipped := base.phases[i]
		if shipped.senders_of(Intents.INTERACT) == 0:
			assert_object(own).override_failure_message(str(shipped.id)).is_same(shipped)
			continue
		var accepts: Array[AcceptSpec] = []
		for accept: AcceptSpec in shipped.accepts:
			if accept.intent != Intents.INTERACT:
				accepts.append(accept)
		assert_int(accepts.size()).is_equal(shipped.accepts.size() - 1)
		assert_array(own.accepts).is_equal(accepts)
		assert_array(own.tick_systems).is_equal(shipped.tick_systems)
	assert_object(mode.find_setting(&"switches")).is_null()
	assert_object(mode.find_setting(&"photos")).is_null()
	assert_array(mode.transitions).is_equal(base.transitions)
	assert_array(mode.actions).is_equal(base.actions)
	assert_array(mode.maps).is_equal(base.maps)
	var ids: Array[StringName] = []
	for type: TaskType in mode.task_types:
		ids.append(type.id)
	# The House's Delivery by meaning and the greybox's by colours (#828), then the zone task.
	assert_array(ids).is_equal([&"delivery", &"colour_delivery", &"hold_the_zone"])
	var tasks := mode.find_setting(&"tasks")
	assert_array([tasks.default_value, tasks.min_value, tasks.max_value]).is_equal([2, 1, 2])
	var zones := mode.find_setting(&"zones")
	assert_int(zones.min_value).is_equal(1)
	assert_int(zones.max_value).is_equal(1)
	assert_object(base.find_setting(&"zones")).is_null()
	# The shipped mode deals the House's five types: Delivery, the Generator (#800), the photo
	# task (#784), Cooking (#775) and car repair (#810).
	assert_int(base.find_setting(&"tasks").max_value).is_equal(5)
	# Its .tres holds the script and nothing else: a re-save that wrote the copied parts into it
	# would freeze them, and the fixture would drift from the shipped mode unseen.
	var text := FileAccess.get_file_as_string(FixtureBaseModeWithZones.PATH)
	assert_str(text).is_not_empty()
	assert_bool(text.contains("[sub_resource")).is_false()
	var at := text.find("[resource]")
	assert_int(at).is_greater_equal(0)
	var stored: Array[String] = []
	for line: String in text.substr(at + "[resource]".length()).split("\n", false):
		if not line.strip_edges().is_empty():
			stored.append(line.strip_edges())
	assert_int(stored.size()).is_equal(1)
	assert_str(stored[0]).starts_with("script = ExtResource(")


## A match of `mode` that the lone player joins, ready and loaded: in the pregame, the deal done
## (lone_player_test's, at its seed 7 and 1 dissident set).
func _lone_in_pregame(mode: GameMode) -> Match:
	var game := _house_match(mode)
	FixtureBaseMode.join(game, LONE)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, LONE, {"settings": {"dissidents": 1}})
	assert_array(FixtureModes.rejections(game, LONE)).is_empty()
	FixtureBaseMode.ready(game, LONE)
	for i in 1000:
		if game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(game, 1)
	FixtureBaseMode.load_ack(game, LONE)
	assert_str(game.phase_id()).is_equal("pregame")
	return game


## The match's task of the task type `type_id`; null when none was dealt.
func _task_of_type(game: Match, type_id: StringName) -> MatchTask:
	for id: int in game.state.tasks:
		if game.state.tasks[id].type.id == type_id:
			return game.state.tasks[id]
	return null


## The House as the host reads it (HostWorldQuery.for_mode, as HostSession builds it): the zone
## task plays on the House alone (TaskType.maps, the Generator ADR's GD13 (b), #804), and the
## scenarios' flat fake would read its storeys as one floor (#681).
func _house_world(mode: GameMode) -> HostWorldQuery:
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	return world


func _house_layouts(mode: GameMode, world: HostWorldQuery) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


## A match of `mode` on the House in the host's world, keeping its history, started.
func _house_match(mode: GameMode) -> Match:
	var world := _house_world(mode)
	var game := Match.new(mode, 7, world, _house_layouts(mode, world))
	game.state.map = HOUSE
	game.keep_history = true
	game.start(0)
	return game


## content_modes_test's _base_round on the House: `peers` join, ready and load into the round.
func _house_round(mode: GameMode, peers: Array[int]) -> Match:
	var game := _house_match(mode)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	_ready_and_load(game, peers)
	return game
