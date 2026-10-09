extends GdUnitTestSuite
## The mode check over `content/` (ARCHITECTURE §9.1): every game mode in `content/modes/` loads as
## a GameMode and passes ModeCheck, and its levels, read by the marker reader (2j), pass the check
## with layouts and fit 10 players at the default settings and at every setting's maximum that the
## map can hold. Also the base mode's data that 2b settles: its numbers, and ResetMatch
## before PlacePlayers on `End -> Lobby`; the deal that 2c adds: the actions of the
## `Loading, all_loaded -> Pregame` row in order, the Crew, Dissident and Knife entries, and that
## row run by a match entering the round (roles, Delivery, knives, placement); and its voice
## rules (2i); its win conditions in order, StartClock alone on `Pregame, pregame_done -> Round`,
## EndMatch on `Round, won -> End`, and a whole match from the lobby to the end and back, twice
## (2h), the second time with no intent: the End's 3 s in silence (#212). The pregame (#213):
## silent and frozen for its 3 s, the clock and RoundStarted only at Round. One of the two tests
## that load `content/` (§9.6).

const MODES_DIR := "res://content/modes/"
const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")


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


func test_every_mode_s_levels_pass_the_check_with_layouts() -> void:
	# §9.1, second part, with the real levels read by the marker reader (2j).
	for path: String in _mode_paths(MODES_DIR):
		var mode := load(path) as GameMode
		if mode == null:
			continue
		var levels := MarkerReader.read_levels(mode, FlatWorldQuery.new())
		(
			assert_array(Array(levels.errors))
			. override_failure_message("%s: %s" % [path, "\n".join(levels.errors)])
			. is_empty()
		)
		var found := LayoutCheck.run(mode, levels.layouts)
		(
			assert_array(Array(found))
			. override_failure_message("%s: %s" % [path, "\n".join(found)])
			. is_empty()
		)


func test_the_greybox_fits_ten_players_at_the_default_settings_and_the_most_packages() -> void:
	# The fit check of all_ready (§9.4) on the real map: 10 players at the defaults, and at the
	# most packages the setting allows (each needs a package and a circle marker and a colour).
	var mode := _base_mode()
	var map := _layouts_for(mode)[mode.maps[0]]
	var settings := mode.default_settings()
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, mode.max_players)
	assert_array(Array(demands.shortfalls(map))).is_empty()
	settings[&"packages"] = mode.find_setting(&"packages").max_value
	demands = LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, mode.max_players)
	assert_array(Array(demands.shortfalls(map))).is_empty()
	assert_int(map.count(&"knife")).is_greater_equal(settings[&"knives"])
	# The Round's Respawn (M4-3) asks for one `respawn` marker; the greybox has 4 to 6.
	assert_int(demands.markers.get(&"respawn", 0)).is_equal(1)
	assert_int(map.count(&"respawn")).is_between(4, 6)


func test_the_greybox_without_its_respawn_markers_does_not_fit() -> void:
	# The respawn demand reaches the fit check on the real content: the same map with every
	# marker but the `respawn` ones is refused for that one need.
	var mode := _base_mode()
	var map := _layouts_for(mode)[mode.maps[0]]
	var stripped := LevelLayout.new(map.path)
	for tag: StringName in map.tags():
		if tag == &"respawn":
			continue
		for at: Vector3 in map.positions(tag):
			stripped.add_marker(tag, at)
	var settings := mode.default_settings()
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, mode.max_players)
	assert_array(HostText.to_dicts(demands.shortfalls(stripped))).contains_exactly(
		[
			{
				"id": &"markers",
				"ids": PackedStringArray(["respawn"]),
				"numbers": {&"need": 1, &"have": 0}
			}
		]
	)


func test_the_scenarios_levels_are_flat() -> void:
	# The scenarios' fake world (§9.7) is one floor at y = 0: each level a scenario plays on (the
	# lobby, the first map, a map a scenario names) is a floor collider whose top is at y = 0 and
	# covers every marker, and every marker stands on it. The mode's other maps (the House) are
	# played by people only, in the host's real world (#626).
	var mode := _base_mode()
	var levels := _layouts_for(mode)
	for path: String in ScenarioLevels.of(mode):
		var root: Node = auto_free((load(path) as PackedScene).instantiate())
		var shapes := root.find_children("*", "CollisionShape3D", true, false)
		assert_int(shapes.size()).override_failure_message(path).is_equal(1)
		if shapes.size() != 1:
			continue
		var shape := shapes[0] as CollisionShape3D
		var box := shape.shape as BoxShape3D
		assert_object(box).override_failure_message(path).is_not_null()
		var centre := (shape.get_parent() as Node3D).transform * shape.transform
		var top := centre.origin.y + box.size.y / 2.0
		assert_float(top).override_failure_message(path).is_equal_approx(0.0, 1e-6)
		var layout := levels[path]
		for tag: StringName in layout.tags():
			for at: Vector3 in layout.positions(tag):
				assert_float(at.y).is_equal_approx(0.0, 1e-6)
				var inside := (
					absf(at.x - centre.origin.x) <= box.size.x / 2.0
					and absf(at.z - centre.origin.z) <= box.size.z / 2.0
				)
				(
					assert_bool(inside)
					. override_failure_message("%s: %s at %s" % [path, tag, at])
					. is_true()
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
	assert_float(mode.find_phase(&"end").settings[&"seconds"]).is_equal(3.0)
	assert_float(mode.find_phase(&"pregame").settings[&"seconds"]).is_equal(3.0)
	assert_float(mode.find_phase(&"loading").settings[&"deadline_seconds"]).is_equal(60.0)
	var defaults := GameMode.new()
	assert_int(defaults.min_players).is_equal(0)
	assert_int(defaults.max_players).is_equal(0)


func test_end_to_lobby_resets_the_match_before_placing_players() -> void:
	# Placed first, a downed player would still be downed when PlayersPlaced goes to everyone
	# (#58).
	var mode := _base_mode()
	var row := mode.find_transition(&"end", &"back")
	assert_int(row.actions.size()).is_equal(2)
	assert_object(row.actions[0]).is_instanceof(ResetMatch)
	assert_object(row.actions[1]).is_instanceof(PlacePlayers)
	assert_str((row.actions[1] as PlacePlayers).tag).is_equal("lobby_player")


func test_the_deal_runs_roles_tasks_knives_then_placement() -> void:
	var mode := _base_mode()
	var row := mode.find_transition(&"loading", &"all_loaded")
	# The deal runs before the pregame, so its screen has the role (#213); the clock waits for it.
	assert_str(row.to).is_equal("pregame")
	assert_int(row.actions.size()).is_equal(4)
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
	assert_str(tasks.tasks_setting).is_equal("tasks")
	assert_str(tasks.banned_setting).is_equal("banned_task_types")
	assert_str(tasks.rng_purpose).is_equal("task_types")
	var knives := row.actions[2] as SpawnItems
	assert_object(knives).is_not_null()
	assert_str(knives.kind.id).is_equal("knife")
	assert_str(knives.count_setting).is_equal("knives")
	assert_str(knives.rng_purpose).is_equal("knives")
	var place := row.actions[3] as PlacePlayers
	assert_object(place).is_not_null()
	assert_str(place.tag).is_equal("round_player")


func test_the_pregame_is_silent_frozen_for_3_s_then_starts_the_clock() -> void:
	# #213, the engineer's answer of 2026-10-08: its own phase between Loading and Round, silent,
	# no input and no movement, the clock not yet running, 3 s.
	var mode := _base_mode()
	var ids: Array[StringName] = []
	for phase: PhaseSpec in mode.phases:
		ids.append(phase.id)
	assert_array(ids).is_equal([&"lobby", &"countdown", &"loading", &"pregame", &"round", &"end"])
	var pregame := mode.find_phase(&"pregame")
	assert_object(pregame.phase_class).is_equal(PregamePhase)
	assert_dict(pregame.settings).is_equal({&"seconds": 3.0})
	assert_array(pregame.accepts).is_empty()
	assert_array(pregame.tick_systems).is_empty()
	assert_object(pregame.voice_rule).is_instanceof(SilentVoice)
	assert_bool(pregame.clock_runs).is_false()
	assert_bool(pregame.checks_wins).is_false()
	assert_bool(pregame.snapshots).is_false()
	assert_int(pregame.level).is_equal(PhaseSpec.Level.MAP)
	# StartClock (2h) runs alone on the row into the round.
	var row := mode.find_transition(&"pregame", PregamePhase.PREGAME_DONE)
	assert_str(row.to).is_equal("round")
	assert_int(row.actions.size()).is_equal(1)
	var clock := row.actions[0] as StartClock
	assert_object(clock).is_not_null()
	assert_str(clock.minutes_setting).is_equal("match_duration")


func test_crew_and_dissident() -> void:
	var mode := _base_mode()
	var crew := mode.find_role(&"crew")
	# Vision revision 1: the crew are shown as Engineers; the ids stay `crew` (the wire, the data).
	assert_str(crew.display_name).is_equal("Engineer")
	assert_str(crew.side).is_equal("crew")
	assert_bool(crew.knows_teammates).is_false()
	assert_array(crew.actions).is_empty()
	var dissident := mode.find_role(&"dissident")
	assert_str(dissident.display_name).is_equal("Dissident")
	assert_str(dissident.side).is_equal("dissidents")
	assert_bool(dissident.knows_teammates).is_true()
	assert_array(dissident.actions).is_empty()
	assert_str(mode.find_side(&"crew").display_name).is_equal("Engineers")
	assert_str(mode.find_side(&"dissidents").display_name).is_equal("Dissidents")


func test_knife() -> void:
	var mode := _base_mode()
	var knife := mode.find_item_kind(&"knife")
	assert_str(knife.display_name).is_equal("Knife")
	assert_str(knife.spawn_tag).is_equal("knife")
	# One rule on Use (2g, #63; §9.5): Cooldown (hit, 0.5 s), StaminaCost (25), then Strike (30°,
	# 1.5 m, 50). No role condition: the public Swung must not reveal a role (§9.2).
	assert_int(knife.actions.size()).is_equal(1)
	var rule := knife.actions[0]
	assert_str(rule.trigger).is_equal(Intents.USE)
	assert_int(rule.conditions.size()).is_equal(2)
	var cooldown := rule.conditions[0] as Cooldown
	assert_object(cooldown).is_not_null()
	assert_str(cooldown.key).is_equal("hit")
	assert_float(cooldown.seconds).is_equal(0.5)
	var stamina := rule.conditions[1] as StaminaCost
	assert_object(stamina).is_not_null()
	assert_int(stamina.amount).is_equal(25)
	assert_int(rule.effects.size()).is_equal(1)
	var strike := rule.effects[0] as Strike
	assert_object(strike).is_not_null()
	assert_float(strike.angle_deg).is_equal(30.0)
	assert_float(strike.reach_m).is_equal(1.5)
	assert_int(strike.damage).is_equal(50)
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_the_base_mode_round_accepts_use_from_the_living_only() -> void:
	var mode := _base_mode()
	var in_round := mode.find_phase(&"round")
	assert_int(in_round.senders_of(Intents.USE)).is_equal(AcceptSpec.From.LIVING)
	assert_int(in_round.senders_of(Intents.PICK_UP)).is_equal(AcceptSpec.From.LIVING)
	assert_int(in_round.senders_of(Intents.PUT_DOWN)).is_equal(AcceptSpec.From.LIVING)
	# MoveClaim from the living and the downed (the downed crawl, M4-2).
	var moves := AcceptSpec.From.LIVING | AcceptSpec.From.DOWNED
	assert_int(in_round.senders_of(Intents.MOVE_CLAIM)).is_equal(moves)
	# The knife from the base mode's own data: a living player strikes, and the downed cannot.
	var game := _base_round(mode, [1, 2, 3, 4])
	FixtureItemModes.stand(game, 1, Vector3(0, 0, 100))
	FixtureItemModes.stand(game, 2, Vector3(0, 0, 101))
	var knife := FixtureItemModes.lay(game, &"knife", Vector3(0, 0, 100))
	FixtureItemModes.pick_up(game, 1, knife)
	assert_int(knife.holder).is_equal(1)
	FixtureCombatModes.use(game, 1, Vector3(0, 0, 1))
	assert_int(game.state.player(2).health).is_equal(50000)
	for peer: int in [1, 2, 3, 4]:
		assert_array(FixtureCombatModes.received(game, peer, &"Swung")).has_size(1)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, 1, Vector3(0, 0, 1))
	assert_int(game.state.player(2).life).is_equal(PlayerState.Life.DOWNED)
	assert_array(FixtureModes.rejections(game, 1)).is_empty()
	# The downed player, even holding a knife, is refused before any rule runs.
	var dropped := FixtureItemModes.lay(game, &"knife", game.state.player(2).position)
	game.state.player(2).held_item = dropped.id
	dropped.where = ItemState.Where.HAND
	dropped.holder = 2
	FixtureCombatModes.use(game, 2, Vector3(0, 0, -1))
	assert_array(FixtureModes.rejections(game, 2)).is_equal([&"not_accepted"])
	assert_int(game.state.player(1).health).is_equal(100000)
	assert_array(FixtureCombatModes.received(game, 1, &"Swung")).has_size(2)


func test_the_base_mode_accepts_next_stage_in_no_phase() -> void:
	# #599, E65: NextStage is a scripted mode's control; the base mode's host cannot skip a phase.
	# The chaos oracle (ChaosOracle.NEVER_ACCEPTED) relies on this.
	for spec: PhaseSpec in _base_mode().phases:
		(
			assert_int(spec.senders_of(Intents.NEXT_STAGE))
			. override_failure_message(str(spec.id))
			. is_equal(0)
		)


func test_the_base_mode_raises_the_downed_and_lets_them_give_up() -> void:
	# M4-4, E27: the raise rule's numbers (3 s, the pick-up's 2 m, 50 health), Round's accepts
	# (Raise and StopRaise from the living, GiveUp from the downed) and ChannelTicks after LifeTicks.
	var mode := _base_mode()
	var in_round := mode.find_phase(&"round")
	assert_int(in_round.senders_of(Intents.RAISE)).is_equal(AcceptSpec.From.LIVING)
	assert_int(in_round.senders_of(Intents.STOP_RAISE)).is_equal(AcceptSpec.From.LIVING)
	assert_int(in_round.senders_of(Intents.GIVE_UP)).is_equal(AcceptSpec.From.DOWNED)
	assert_object(in_round.tick_systems[0]).is_instanceof(LifeTicks)
	assert_object(in_round.tick_systems[1]).is_instanceof(ChannelTicks)
	var raise: Rule = null
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.RAISE:
			raise = rule
	var effect := raise.effects[0] as RaiseDowned
	assert_float(effect.seconds).is_equal(3.0)
	assert_int(effect.revive_health).is_equal(50)
	assert_float((raise.conditions[2] as TargetInReach).reach_m).is_equal(2.0)
	# Played from the base mode's own data: knocked down, raised for 3 s, standing with 50.
	var game := _base_round(mode, [1, 2, 3])
	FixtureItemModes.stand(game, 1, Vector3(0, 0, 100))
	FixtureItemModes.stand(game, 2, Vector3(0, 0, 101))
	FixtureItemModes.stand(game, 3, Vector3(1.5, 0, 101))
	var knife := FixtureItemModes.lay(game, &"knife", Vector3(0, 0, 100))
	FixtureItemModes.pick_up(game, 1, knife)
	FixtureCombatModes.use(game, 1, Vector3(0, 0, 1))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, 1, Vector3(0, 0, 1))
	FixtureCombatModes.raise(game, 3, 2)
	FixtureModes.run_ticks(game, 60)
	assert_int(game.state.player(2).life).is_equal(PlayerState.Life.ALIVE)
	assert_int(game.state.player(2).health).is_equal(50000)
	# Downed again and given up: dead at once.
	FixtureModes.run_ticks(game, 60)
	FixtureCombatModes.use(game, 1, Vector3(0, 0, 1))
	assert_int(game.state.player(2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureCombatModes.give_up(game, 2)
	assert_int(game.state.player(2).life).is_equal(PlayerState.Life.DEAD)
	assert_array(FixtureModes.rejections(game, 2)).is_empty()
	assert_array(FixtureModes.rejections(game, 3)).is_empty()


func test_the_deal_demands_knife_markers_at_the_default_settings() -> void:
	var mode := _base_mode()
	var demands := Demands.new(mode)
	for action: RuleEffect in mode.find_transition(&"loading", &"all_loaded").actions:
		action.add_demands(mode.default_settings(), 10, demands)
	assert_int(demands.markers.get(&"knife", 0)).is_equal(2)
	assert_int(demands.markers.get(&"round_player", 0)).is_equal(10)


func test_entering_the_round_runs_the_whole_deal() -> void:
	# The base mode's own data from the lobby into the round, 4 players at the default settings
	# (1 dissident, 1 task, 6 packages, 2 knives).
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
	# Delivery drawn by DealTasks: one shared task, 6 circles and 6 packages; then 2 knives.
	assert_int(game.state.tasks.size()).is_equal(1)
	assert_int(game.state.stations.size()).is_equal(6)
	var kinds: Dictionary[StringName, int] = {}
	var taken: Dictionary[Vector3, int] = {}
	for id: int in game.state.items:
		var item := game.state.items[id]
		kinds[item.kind.id] = kinds.get(item.kind.id, 0) + 1
		assert_bool(Array(map.positions(item.kind.spawn_tag)).has(item.position)).is_true()
		assert_bool(taken.has(item.position)).is_false()
		taken[item.position] = id
	assert_dict(kinds).is_equal({&"package": 6, &"knife": 2})
	for peer: int in peers:
		var view := game.view_of(peer)
		assert_int(view.events_named(&"StationPlaced").size()).is_equal(6)
		assert_int(view.events_named(&"ItemSpawned").size()).is_equal(8)
		assert_dict(view.events_named(&"TaskProgress")[0].to_dict()).is_equal(
			{"done": 0, "total": 6}
		)
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
		&"RoleAssigned", &"StationPlaced", &"ItemSpawned", &"TaskProgress", &"PlayersPlaced"
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
				"TaskProgress",
				"ItemSpawned(knife)",
				"PlayersPlaced",
			]
		)
	)


func test_the_base_mode_names_its_voice_rules_with_their_numbers() -> void:
	# §6 and §9.5: proximity 8 m in the lobby and the countdown, silence while loading, in the
	# pregame (#213) and on the end screen, the round's radius 8 m (the ghost radii are gone:
	# vision revision 1). The classes' defaults stay 0 (#58), which the voice rules' own bounds
	# tests show.
	var mode := _base_mode()
	for id: StringName in [&"lobby", &"countdown"]:
		var rule := mode.find_phase(id).voice_rule
		assert_object(rule).override_failure_message("phase %s" % id).is_instanceof(ProximityVoice)
		if rule is ProximityVoice:
			assert_float((rule as ProximityVoice).radius_m).is_equal(8.0)
	for id: StringName in [&"loading", &"pregame", &"end"]:
		assert_object(mode.find_phase(id).voice_rule).is_instanceof(SilentVoice)
	var in_round := mode.find_phase(&"round").voice_rule
	assert_object(in_round).is_instanceof(RoundVoice)
	if not in_round is RoundVoice:
		return
	var round_voice := in_round as RoundVoice
	assert_float(round_voice.living_m).is_equal(8.0)


func test_the_base_mode_s_hearing_radius_per_phase() -> void:
	# E41: VoiceRule.radius_of each phase's rule, the client's cutoff and the distance the leak
	# test checks: 8 m in the Lobby, the Countdown and the Round, 0 in Loading, Pregame and End.
	var mode := _base_mode()
	var want: Dictionary[StringName, float] = {
		&"lobby": 8.0,
		&"countdown": 8.0,
		&"loading": 0.0,
		&"pregame": 0.0,
		&"round": 8.0,
		&"end": 0.0,
	}
	var got: Dictionary[StringName, float] = {}
	for phase: PhaseSpec in mode.phases:
		got[phase.id] = VoiceRule.radius_of(phase.voice_rule)
	assert_dict(got).is_equal(want)


## The layouts of the mode's levels, read from the real scenes by the marker reader (2j) with the
## flat world of the stage-2 levels (one floor at y = 0), which test_the_levels_are_flat checks.
func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(mode, FlatWorldQuery.new())
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


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


func test_the_win_conditions_in_the_base_modes_order() -> void:
	# §3.4 and §9.5 (2h, #64; M4-2): every task done (crew), no crew present and time up
	# (dissidents).
	var mode := _base_mode()
	var ids: Array[StringName] = []
	for condition: WinCondition in mode.win_conditions:
		ids.append(condition.id)
	assert_array(ids).is_equal([&"every_task_done", &"no_crew_present", &"time_up"])
	var every_task_done := mode.win_conditions[0]
	assert_str(every_task_done.resource_path).is_equal(
		"res://content/win_conditions/every_task_done.tres"
	)
	assert_str(every_task_done.side).is_equal("crew")
	assert_int(every_task_done.conditions.size()).is_equal(1)
	assert_object(every_task_done.conditions[0]).is_instanceof(AllSubtasksDone)
	assert_bool(every_task_done.conditions[0].negate).is_false()
	var no_crew_present := mode.win_conditions[1]
	assert_str(no_crew_present.side).is_equal("dissidents")
	assert_int(no_crew_present.conditions.size()).is_equal(1)
	var none_alive := no_crew_present.conditions[0] as NoneAlive
	assert_object(none_alive).is_not_null()
	assert_str(none_alive.side).is_equal("crew")
	assert_bool(none_alive.negate).is_false()
	var time_up := mode.win_conditions[2]
	assert_str(time_up.side).is_equal("dissidents")
	assert_int(time_up.conditions.size()).is_equal(2)
	assert_object(time_up.conditions[0]).is_instanceof(ClockEnded)
	assert_bool(time_up.conditions[0].negate).is_false()
	assert_object(time_up.conditions[1]).is_instanceof(AllSubtasksDone)
	assert_bool(time_up.conditions[1].negate).is_true()
	# `Round, won -> End` runs EndMatch alone.
	var won := mode.find_transition(&"round", Match.WON)
	assert_int(won.actions.size()).is_equal(1)
	assert_object(won.actions[0]).is_instanceof(EndMatch)


func test_a_whole_base_mode_match_to_the_end_and_back_to_the_lobby_twice() -> void:
	# The base mode's own data, 4 players at the default settings: the crew delivers the 6
	# packages and wins; the host returns to the lobby, shortens the round to 1 minute, and the
	# second match runs out of time with every package where it spawned: the dissidents win.
	var mode := _base_mode()
	var peers: Array[int] = [1, 2, 3, 4]
	var game := _base_round(mode, peers)
	# The pregame's end tick: the step that entered the round.
	var start := game.ticked_through()
	assert_int(game.state.clock_ticks_left).is_equal(10 * 60 * Ticks.RATE)
	var crew := FixtureDealModes.players_of(game, &"crew")
	assert_int(crew.size()).is_equal(3)
	var task := FixtureDeliveryModes.task_of(game)
	for index in 6:
		var package := FixtureDeliveryModes.package_of(game, task, index)
		var circle := FixtureDeliveryModes.circle_of(game, task, index)
		FixtureDeliveryModes.carry_to(game, crew[index % crew.size()], package, circle.position)
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


func test_the_base_lobby_takes_no_dissidents_and_time_up_is_still_their_win() -> void:
	# The engineer's decision (MVP rules), through the real lobby: the host sets 0 dissidents and
	# a 1-minute round; nobody is a dissident, nothing is delivered, and time up is their win.
	var mode := _base_mode()
	var peers: Array[int] = [1, 2, 3, 4]
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	var settings := {"dissidents": 0, "match_duration": 1}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, 1, {"settings": settings})
	assert_array(FixtureModes.rejections(game, 1)).is_empty()
	assert_int(game.state.settings[&"dissidents"]).is_equal(0)
	_ready_and_load(game, peers)
	assert_array(FixtureDealModes.players_of(game, &"dissident")).is_empty()
	FixtureWinModes.run_through(game, game.ticked_through() + 60 * Ticks.RATE)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("dissidents")
	for peer: int in peers:
		var ended := game.view_of(peer).events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		assert_dict(ended[0].to_dict()).is_equal(
			{"side": &"dissidents", "reason": &"time_up", "numbers": {&"time": 60}}
		)
	assert_array(Array(game.diagnostics)).is_empty()


## With no intent the End's 3 s pass, nobody heard on any of its ticks (#213 relies on it), and on
## its announced end tick everyone is back in the lobby (#212).
func _end_in_silence_then_lobby(game: Match, peers: Array[int]) -> void:
	assert_str(game.phase_id()).is_equal("end")
	var ends_on := game.current_phase().entered_tick + 3 * Ticks.RATE
	for peer: int in peers:
		var changed := game.view_of(peer).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
		assert_dict(changed.to_dict()).is_equal({"phase": &"end", "end_tick": ends_on})
	while game.phase_id() == &"end":
		FixtureModes.run_ticks(game, 1)
		if game.phase_id() != &"end":
			break
		for peer: int in peers:
			var heard := Array(game.view_of(peer).speakers[game.ticked_through()])
			(
				assert_array(heard)
				. override_failure_message("tick %d" % game.ticked_through())
				. is_empty()
			)
	assert_int(game.ticked_through()).is_equal(ends_on)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.state.winner).is_empty()


## A match of `mode` (the base mode's data) with `peers` from the lobby into the round.
func _base_round(mode: GameMode, peers: Array[int]) -> Match:
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	_ready_and_load(game, peers)
	return game


## `peers` in the lobby get ready, the countdown runs out, they load and the pregame runs out:
## the round.
func _ready_and_load(game: Match, peers: Array[int]) -> void:
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	for i in 1000:
		if game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	_pregame_in_silence_then_round(game, peers)


## The pregame of #213 from its entry: everyone placed and dealt a role; for its 3 s nobody is
## heard on any tick (on the round's spots; voice_by_phase_test puts everyone within the radius)
## and the clock does not run (no RoundStarted); on its announced end tick the round begins, its
## clock started by StartClock.
func _pregame_in_silence_then_round(game: Match, peers: Array[int]) -> void:
	assert_str(game.phase_id()).is_equal("pregame")
	var ends_on := game.current_phase().entered_tick + 3 * Ticks.RATE
	var started := game.view_of(peers[0]).events_named(&"RoundStarted").size()
	for peer: int in peers:
		var changed := game.view_of(peer).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
		assert_dict(changed.to_dict()).is_equal({"phase": &"pregame", "end_tick": ends_on})
		assert_str(game.state.player(peer).role).is_not_empty()
	var clock := game.state.clock_ticks_left
	while game.phase_id() == &"pregame":
		FixtureModes.run_ticks(game, 1)
		if game.phase_id() != &"pregame":
			break
		assert_int(game.state.clock_ticks_left).is_equal(clock)
		for peer: int in peers:
			var heard := Array(game.view_of(peer).speakers[game.ticked_through()])
			(
				assert_array(heard)
				. override_failure_message("tick %d" % game.ticked_through())
				. is_empty()
			)
		assert_int(game.view_of(peers[0]).events_named(&"RoundStarted").size()).is_equal(started)
	assert_int(game.ticked_through()).is_equal(ends_on)
	assert_str(game.phase_id()).is_equal("round")
	for peer: int in peers:
		var round_started := game.view_of(peer).events_named(&"RoundStarted")
		assert_int(round_started.size()).is_equal(started + 1)
		assert_dict(round_started[-1].to_dict()).is_equal({"start_tick": ends_on})


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
