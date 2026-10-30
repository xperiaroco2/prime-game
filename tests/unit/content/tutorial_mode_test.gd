extends GdUnitTestSuite
## The tutorial mode's data (#600, E68; ARCHITECTURE §9.5.17): its players, PlayerRules, settings,
## the two tables of docs/design/tutorial.md §2.3 (phases with their accepts, tick systems, voice
## and snapshots; rows with their actions) and the NextStage rule; then the mode itself run by a
## match on its room: gather to lessons with the players on the `round_player` markers in level
## order, a stand-in down for good in raise_stage, the host's player dead at once and respawned in
## death_stage. Like content_modes_test.gd, it loads `content/` and `levels/` (§9.6): the mode
## check and the layout check run there, for every mode.

const TUTORIAL_MODE := "res://content/modes/tutorial_mode.tres"
const BASE_MODE := "res://content/modes/base_mode.tres"
const ROOM := "res://levels/tutorial/tutorial.tscn"

const NEWCOMER := AcceptSpec.From.NEWCOMER
const PLAYER := AcceptSpec.From.PLAYER
const LIVING := AcceptSpec.From.LIVING
const HOST := AcceptSpec.From.HOST
const DOWNED := AcceptSpec.From.DOWNED


func test_three_players_no_lobby_level_and_no_win_conditions() -> void:
	var mode := _mode()
	assert_int(mode.min_players).is_equal(3)
	assert_int(mode.max_players).is_equal(3)
	assert_str(mode.lobby_level).is_empty()
	assert_array(Array(mode.maps)).contains_exactly([ROOM])
	# The saved file writes `bench_maps = null`: it must load as the empty default, not Nil.
	assert_array(Array(mode.bench_maps)).is_empty()
	assert_array(Array(mode.player_maps())).contains_exactly([ROOM])
	assert_array(mode.win_conditions).is_empty()
	assert_str(mode.first_phase).is_equal("gather")
	var roles: Array[StringName] = []
	for role: GameRole in mode.roles:
		roles.append(role.id)
	assert_array(roles).contains_exactly([&"crew"])


func test_the_base_mode_s_player_rules_but_a_10_s_respawn() -> void:
	# §2.3: respawn_s 10 is a placeholder ("not a decision"); every other number is the base mode's.
	var rules := _mode().player_rules
	var base := (load(BASE_MODE) as GameMode).player_rules
	for property: Dictionary in base.get_property_list():
		var number: String = property["name"]
		var kind: int = property["type"]
		# Only the numbers: a list of maps (motion_maps) is no number.
		if (property["usage"] as int & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if kind not in [TYPE_FLOAT, TYPE_INT]:
			continue
		var want: float = 10.0 if number == "respawn_s" else base.get(number)
		(
			assert_float(rules.get(number) as float)
			. override_failure_message("PlayerRules_tutorial.%s" % number)
			. is_equal_approx(want, 1e-6)
		)


func test_the_deal_s_settings_are_fixed() -> void:
	# No settings the player changes (§2.3): no phase accepts ChangeSettings, and each setting
	# the deal reads has one value: `packages` 1 (lesson 2's package, LD1 (a)) and `knives` 1.
	var mode := _mode()
	for spec: PhaseSpec in mode.phases:
		assert_int(spec.senders_of(Intents.CHANGE_SETTINGS)).is_equal(0)
	var defaults := mode.default_settings()
	var ids: Array[StringName] = []
	for setting: SettingSpec in mode.settings:
		ids.append(setting.id)
	assert_array(ids).contains_exactly([&"packages", &"knives"])
	for id: StringName in ids:
		var setting := mode.find_setting(id)
		assert_int(setting.min_value).override_failure_message(id).is_equal(setting.max_value)
		assert_int(defaults[id]).override_failure_message(id).is_equal(1)


func test_no_task_is_dealt() -> void:
	# The tutorial without tasks (#900, LE1 (a)): no task type, no DealTasks in any row and no
	# TaskTicks in any phase, so the loading screen finds no task card to show.
	var mode := _mode()
	assert_array(mode.task_types).is_empty()
	for row: Transition in mode.transitions:
		for action: RuleEffect in row.actions:
			assert_bool(action is DealTasks).override_failure_message(row.from).is_false()
	for spec: PhaseSpec in mode.phases:
		for system: TickSystem in spec.tick_systems:
			assert_bool(system is TaskTicks).override_failure_message(spec.id).is_false()


func test_the_phases_as_the_design_s_table() -> void:
	var mode := _mode()
	var ids: Array[StringName] = []
	for spec: PhaseSpec in mode.phases:
		ids.append(spec.id)
		assert_bool(spec.checks_wins).override_failure_message(spec.id).is_false()
		assert_bool(spec.clock_runs).override_failure_message(spec.id).is_false()
	assert_array(ids).contains_exactly(
		[&"gather", &"loading", &"lessons", &"raise_stage", &"death_stage"]
	)
	var gather := mode.find_phase(&"gather")
	assert_object(gather.phase_class).is_same(LobbyPhase)
	assert_int(gather.level).is_equal(PhaseSpec.Level.NONE)
	assert_bool(gather.snapshots).is_false()
	assert_object(gather.voice_rule).is_instanceof(SilentVoice)
	var loading := mode.find_phase(&"loading")
	assert_object(loading.phase_class).is_same(LoadingPhase)
	assert_float(loading.settings[&"deadline_seconds"]).is_equal(60.0)
	assert_int(loading.level).is_equal(PhaseSpec.Level.MAP)
	assert_bool(loading.snapshots).is_false()
	assert_object(loading.voice_rule).is_instanceof(SilentVoice)
	for id: StringName in [&"lessons", &"raise_stage", &"death_stage"]:
		var spec := mode.find_phase(id)
		assert_object(spec.phase_class).override_failure_message(id).is_same(RoundPhase)
		assert_int(spec.level).override_failure_message(id).is_equal(PhaseSpec.Level.MAP)
		assert_bool(spec.snapshots).override_failure_message(id).is_true()
		var voice := spec.voice_rule as RoundVoice
		assert_object(voice).override_failure_message(id).is_not_null()
		assert_float(voice.living_m).override_failure_message(id).is_equal(8.0)


func test_the_accepts_as_the_design_s_table() -> void:
	var mode := _mode()
	var items := {
		Intents.MOVE_CLAIM: LIVING,
		Intents.PICK_UP: LIVING,
		Intents.PUT_DOWN: LIVING,
		Intents.SWAP: LIVING,
		Intents.THROW: LIVING,
		Intents.NEXT_STAGE: HOST,
		# Drawing from the belt (GDD §6, #1218): wherever X is taught.
		Intents.DRAW: LIVING,
	}
	var raising := items.duplicate()
	# The throw is taught in lessons only (#901, LD3 (a)); a flight outlives NextStage (FlightTicks).
	raising.erase(Intents.THROW)
	raising[Intents.MOVE_CLAIM] = LIVING | DOWNED
	raising[Intents.RAISE] = LIVING
	raising[Intents.STOP_RAISE] = LIVING
	var dying := raising.duplicate()
	dying.erase(Intents.NEXT_STAGE)
	var want := {
		&"gather": {Intents.HELLO: NEWCOMER, Intents.SET_READY: PLAYER},
		&"loading": {Intents.LOAD_ACK: PLAYER},
		&"lessons": items,
		&"raise_stage": raising,
		&"death_stage": dying,
	}
	for id: StringName in want:
		var got := {}
		for accept: AcceptSpec in mode.find_phase(id).accepts:
			got[accept.intent] = accept.from
		assert_dict(got).override_failure_message(id).is_equal(want[id])


func test_no_phase_accepts_either_use_or_give_up() -> void:
	# §2.3: the knife swings at nobody; D28 (a): the host's player dies at once, so no GiveUp.
	for spec: PhaseSpec in _mode().phases:
		assert_int(spec.senders_of(Intents.USE)).override_failure_message(spec.id).is_equal(0)
		var secondary := spec.senders_of(Intents.USE_SECONDARY)
		assert_int(secondary).override_failure_message(spec.id).is_equal(0)
		assert_int(spec.senders_of(Intents.GIVE_UP)).override_failure_message(spec.id).is_equal(0)


func test_flight_ticks_in_every_stage_and_life_ticks_only_in_the_death_stage() -> void:
	# FlightTicks in the three stages (#901, LD3 (a)): a phase without it pauses every flight, so an
	# item thrown just before NextStage would hang FLYING through the later lessons.
	var mode := _mode()
	assert_array(mode.find_phase(&"gather").tick_systems).is_empty()
	assert_array(mode.find_phase(&"loading").tick_systems).is_empty()
	assert_array(_classes(mode.find_phase(&"lessons").tick_systems)).contains_exactly([FlightTicks])
	assert_array(_classes(mode.find_phase(&"raise_stage").tick_systems)).contains_exactly(
		[ChannelTicks, FlightTicks]
	)
	var death := mode.find_phase(&"death_stage").tick_systems
	assert_array(_classes(death)).contains_exactly([LifeTicks, ChannelTicks, FlightTicks])
	var respawn := (death[0] as LifeTicks).respawn
	assert_str(respawn.tag).is_equal("respawn")


func test_the_rows_and_their_actions() -> void:
	var mode := _mode()
	var rows: Array[String] = []
	for row: Transition in mode.transitions:
		rows.append("%s, %s -> %s" % [row.from, row.outcome, row.to])
	(
		assert_array(rows)
		. contains_exactly(
			[
				"gather, all_ready -> loading",
				"loading, all_loaded -> lessons",
				"lessons, next -> raise_stage",
				"raise_stage, next -> death_stage",
			]
		)
	)
	var deal := mode.transitions[1].actions
	assert_array(_classes(deal)).contains_exactly([DealRoles, SpawnItems, SpawnItems, PlacePlayers])
	var roles := deal[0] as DealRoles
	assert_array(roles.quotas).is_empty()
	assert_str(roles.default_role.id).is_equal("crew")
	# The package first (LE2 (a)), so its item id comes before the knife's as under Delivery's deal.
	var package := deal[1] as SpawnItems
	assert_str(package.kind.id).is_equal("package")
	assert_str(package.count_setting).is_equal("packages")
	assert_str(package.rng_purpose).is_equal("packages")
	var knife := deal[2] as SpawnItems
	assert_str(knife.kind.id).is_equal("knife")
	assert_str(knife.count_setting).is_equal("knives")
	var place := deal[3] as PlacePlayers
	assert_str(place.tag).is_equal("round_player")
	assert_bool(place.ordered).is_true()
	assert_array(_classes(mode.transitions[0].actions)).is_empty()
	var first := mode.transitions[2].actions
	assert_int(first.size()).is_equal(1)
	assert_int((first[0] as KnockDown).pick).is_equal(1)
	assert_bool((first[0] as KnockDown).then_die).is_false()
	var second := mode.transitions[3].actions
	assert_int(second.size()).is_equal(1)
	assert_int((second[0] as KnockDown).pick).is_equal(0)
	assert_bool((second[0] as KnockDown).then_die).is_true()


func test_next_stage_reports_next_and_nothing_else() -> void:
	var rules: Array[Rule] = []
	for rule: Rule in _mode().actions:
		if rule.trigger == Intents.NEXT_STAGE:
			rules.append(rule)
	assert_int(rules.size()).is_equal(1)
	assert_array(rules[0].conditions).is_empty()
	assert_int(rules[0].effects.size()).is_equal(1)
	var report := rules[0].effects[0] as ReportOutcome
	assert_object(report).is_not_null()
	assert_str(report.outcome).is_equal("next")
	assert_str(report.argument).is_empty()


func test_the_throw_is_the_base_mode_s_rule() -> void:
	# #901 (LD3 (a)): the lesson teaches the throw a match plays, so its parts and numbers are the
	# base mode's.
	var ours := _throw_rule(_mode())
	var base := _throw_rule(load(BASE_MODE) as GameMode)
	assert_object(ours).is_not_null()
	assert_object(base).is_not_null()
	assert_array(_classes(ours.conditions)).is_equal(_classes(base.conditions))
	assert_array(_classes(ours.effects)).is_equal([ThrowItem])
	assert_array(_classes(base.effects)).is_equal([ThrowItem])
	var our_throw := ours.effects[0] as ThrowItem
	var base_throw := base.effects[0] as ThrowItem
	for property: String in ["speed_mps", "gravity_mps2", "radius_m", "longest_flight_s"]:
		assert_float(our_throw.get(property) as float).override_failure_message(property).is_equal(
			base_throw.get(property) as float
		)


func test_a_throw_just_before_next_stage_rests_in_the_raise_stage() -> void:
	# FlightTicks runs in every stage (#901): a flight launched in lessons outlives NextStage.
	var mode := _mode()
	var levels := MarkerReader.read_levels(mode, FlatWorldQuery.new())
	var game := Match.new(mode, 7, FlatWorldQuery.new(), levels.layouts)
	game.start(0)
	var peers: Array[int] = [1, 2, 3]
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("lessons")
	var package: ItemState = null
	for id: int in game.state.items:
		if game.state.items[id].kind.id == &"package":
			package = game.state.items[id]
	FixtureItemModes.stand(game, 1, package.position)
	FixtureItemModes.pick_up(game, 1, package)
	FixtureModes.run_ticks(game, 1)
	assert_int(package.holder).is_equal(1)
	FixtureModes.send(game, Intents.THROW, 1, {"facing": Vector3(0.0, 1.0, 0.0)})
	FixtureModes.run_ticks(game, 1)
	assert_object(FixtureFlightModes.flying(game)).is_same(package)
	FixtureStageModes.next_stage(game, 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("raise_stage")
	assert_bool(package.is_in_flight()).is_true()
	FixtureModes.run_ticks(game, Ticks.from_seconds(3.0))
	assert_bool(package.is_in_flight()).is_false()
	assert_int(package.holder).is_equal(0)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_match_from_gather_to_the_respawn_in_the_death_stage() -> void:
	var mode := _mode()
	var levels := MarkerReader.read_levels(mode, FlatWorldQuery.new())
	assert_array(Array(levels.errors)).is_empty()
	var room := levels.layouts[ROOM]
	var game := Match.new(mode, 7, FlatWorldQuery.new(), levels.layouts)
	game.start(0)
	var peers: Array[int] = [1, 2, 3]
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("gather")
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	for peer: int in peers:
		FixtureBaseMode.load_ack(game, peer)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("lessons")
	# Ordered placement (§2.5): peer 1 on the start, stand-in 1 on the raise spot, stand-in 2 in
	# the corner; everyone crew and no task; the package on the shelf, the knife on the table,
	# and no station.
	var spots := room.positions(&"round_player")
	for i in peers.size():
		var player := game.state.player(peers[i])
		assert_vector(player.position).is_equal(spots[i])
		assert_str(player.role).is_equal("crew")
	assert_int(game.state.tasks.size()).is_equal(0)
	var kinds: Array[StringName] = []
	var ids: Array = game.state.items.keys()
	ids.sort()
	# The package's SpawnItems comes first (LE2 (a)): its item id is the lower one.
	for id: int in ids:
		var item := game.state.items[id]
		kinds.append(item.kind.id)
		assert_vector(item.position).is_equal(room.positions(item.kind.spawn_tag)[0])
	assert_array(kinds).contains_exactly([&"package", &"knife"])
	assert_int(game.state.stations.size()).is_equal(0)
	# A stand-in's NextStage is refused; the host's moves on and downs stand-in 1 for good.
	FixtureStageModes.next_stage(game, 2)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("lessons")
	assert_array(FixtureModes.rejections(game, 2)).contains_exactly([&"not_accepted"])
	FixtureStageModes.next_stage(game, 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("raise_stage")
	assert_int(game.state.player(2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureModes.run_ticks(game, Ticks.from_seconds(mode.player_rules.knockdown_s + 1.0))
	assert_int(game.state.player(2).life).is_equal(PlayerState.Life.DOWNED)
	# The host's player dies at once and respawns after respawn_s at the room's respawn marker.
	FixtureStageModes.next_stage(game, 1, 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("death_stage")
	assert_int(game.state.player(1).life).is_equal(PlayerState.Life.DEAD)
	FixtureModes.run_ticks(game, Ticks.from_seconds(mode.player_rules.respawn_s) + 1)
	assert_int(game.state.player(1).life).is_equal(PlayerState.Life.ALIVE)
	assert_vector(game.state.player(1).position).is_equal(room.positions(&"respawn")[0])
	assert_array(Array(game.diagnostics)).is_empty()
	assert_int(game.row_error_count()).is_equal(0)


func _classes(parts: Array) -> Array:
	var found := []
	for part: Object in parts:
		found.append(part.get_script())
	return found


func _throw_rule(mode: GameMode) -> Rule:
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			return rule
	return null


func _mode() -> GameMode:
	return load(TUTORIAL_MODE) as GameMode
