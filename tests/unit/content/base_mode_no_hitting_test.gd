extends GdUnitTestSuite
## The M8 slice's "no hitting" in the base mode's Round (#1497; the engineer's word on #507,
## comment 6549409184; GDD §3 "The M8 slice", item 2): the Round takes no Use, so neither the fist,
## the crystal nor any held item hits there, and the Loading row places no knife. The lobby keeps
## its hits (#1439) and the Round keeps what the ship's quest needs: PickUp, PutDown, Throw,
## Interact, UseSecondary. The knockdown scenarios and the chaos run play FixtureBaseModeWithMelee,
## the base mode with both put back, pinned here too. Loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const PEERS: Array[int] = [1, 2, 3, 4]
## Far from the greybox's markers; player 2 stands 1 m north of player 1.
const SPOT := Vector3(0, 0, 100)
const NORTH := Vector3(0, 0, 1)


func test_the_round_takes_no_use_and_keeps_the_quest_s_intents() -> void:
	var mode := load(BASE_MODE) as GameMode
	var living := AcceptSpec.From.LIVING
	var in_round := mode.find_phase(&"round")
	assert_int(in_round.senders_of(Intents.USE)).is_equal(0)
	for intent: StringName in [
		Intents.PICK_UP,
		Intents.PUT_DOWN,
		Intents.THROW,
		Intents.INTERACT,
		Intents.USE_SECONDARY,
	]:
		assert_int(in_round.senders_of(intent)).override_failure_message(intent).is_equal(living)
	# The lobby's hits stay (#1439): the hall and the countdown under it take Use, and the mode's
	# one Use rule, the fallback Strike, is still there for them.
	for phase: StringName in [&"lobby", &"countdown"]:
		var spec := mode.find_phase(phase)
		assert_int(spec.senders_of(Intents.USE)).override_failure_message(phase).is_equal(living)
	var uses := mode.actions.filter(func(rule: Rule) -> bool: return rule.trigger == Intents.USE)
	assert_array(uses).has_size(1)
	assert_object((uses[0] as Rule).effects[0]).is_instanceof(Strike)


func test_the_loading_row_spawns_no_items() -> void:
	var mode := load(BASE_MODE) as GameMode
	var row := mode.find_transition(&"loading", &"all_loaded")
	assert_object(row).is_not_null()
	for action: RuleEffect in row.actions:
		assert_object(action).is_not_instanceof(SpawnItems)
	assert_object(row.actions.back()).is_instanceof(PlacePlayers)


func test_a_round_of_the_base_mode_has_no_knife_and_refuses_every_use() -> void:
	var mode := load(BASE_MODE) as GameMode
	var game := _round_of(mode)
	for id: int in game.state.items:
		assert_str(String(game.state.items[id].kind.id)).is_not_equal("knife")
	for peer: int in PEERS:
		for spawned: MatchEvent in game.view_of(peer).events_named(&"ItemSpawned"):
			assert_str(String((spawned as ItemSpawnedEvent).kind)).is_not_equal("knife")
	FixtureItemModes.stand(game, 1, SPOT)
	FixtureItemModes.stand(game, 2, SPOT + NORTH)
	# The empty hand (the fist) is refused before any rule runs.
	FixtureCombatModes.use(game, 1, NORTH)
	assert_array(FixtureModes.rejections(game, 1)).is_equal([&"not_accepted"])
	# So is a knife in the hand (the kind stays in the mode's list, #1497 keeps it as content),
	# and the crystal, the slice's one thing to hold.
	var expected: Array[StringName] = [&"not_accepted"]
	for kind: StringName in [&"knife", &"crystal_charged"]:
		var item := FixtureItemModes.lay(game, kind, SPOT)
		FixtureItemModes.pick_up(game, 1, item)
		assert_int(item.holder).override_failure_message(kind).is_equal(1)
		FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
		FixtureCombatModes.use(game, 1, NORTH)
		expected.append(&"not_accepted")
		assert_array(FixtureModes.rejections(game, 1)).is_equal(expected)
		FixtureItemModes.put_down(game, 1, NORTH)
	assert_int(game.state.player(2).health).is_equal(mode.player_rules.health * 1000)
	for peer: int in PEERS:
		assert_array(FixtureCombatModes.received(game, peer, &"Swung")).is_empty()


func test_the_melee_fixture_is_the_base_mode_with_the_round_s_use_and_the_knives() -> void:
	var base := load(BASE_MODE) as GameMode
	var fixture := FixtureBaseModeWithMelee.mode()
	assert_str(fixture.resource_path).is_equal(FixtureBaseModeWithMelee.PATH)
	var living := AcceptSpec.From.LIVING
	assert_int(fixture.find_phase(&"round").senders_of(Intents.USE)).is_equal(living)
	# The shipped mode's own parts are left alone.
	assert_int(base.find_phase(&"round").senders_of(Intents.USE)).is_equal(0)
	var base_row := base.find_transition(&"loading", &"all_loaded")
	var row := fixture.find_transition(&"loading", &"all_loaded")
	assert_int(row.actions.size()).is_equal(base_row.actions.size() + 1)
	var spawn := row.actions[row.actions.size() - 2] as SpawnItems
	assert_object(spawn).is_not_null()
	assert_str(String(spawn.kind.id)).is_equal("knife")
	assert_str(String(spawn.count_setting)).is_equal("knives")
	assert_object(row.actions.back()).is_instanceof(PlacePlayers)
	var check := ModeCheck.run(fixture)
	assert_array(Array(check.errors)).is_empty()
	# Everything else is the shipped mode's.
	assert_array(fixture.actions).is_equal(base.actions)
	assert_array(fixture.settings).is_equal(base.settings)
	assert_array(Array(fixture.maps)).is_equal(Array(base.maps))
	assert_int(fixture.phases.size()).is_equal(base.phases.size())
	# A round of it places the knives, and a living player's knife strikes there.
	var game := _round_of(fixture)
	var knives := 0
	for id: int in game.state.items:
		if game.state.items[id].kind.id == &"knife":
			knives += 1
	assert_int(knives).is_equal(fixture.find_setting(&"knives").default_value)
	FixtureItemModes.stand(game, 1, SPOT)
	FixtureItemModes.stand(game, 2, SPOT + NORTH)
	var knife := FixtureItemModes.lay(game, &"knife", SPOT)
	FixtureItemModes.pick_up(game, 1, knife)
	FixtureCombatModes.use(game, 1, NORTH)
	assert_array(FixtureModes.rejections(game, 1)).is_empty()
	assert_array(FixtureCombatModes.received(game, 2, &"Swung")).has_size(1)
	assert_int(game.state.player(2).health).is_less(fixture.player_rules.health * 1000)


## `mode` from the lobby into the round on the greybox (the scenarios' test bench, #767), 4 players
## at the default settings.
func _round_of(mode: GameMode) -> Match:
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	assert_array(Array(levels.errors)).is_empty()
	var game := Match.new(mode, 7, FlatWorldQuery.new(), levels.layouts)
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in PEERS:
		FixtureBaseMode.join(game, peer)
	for peer: int in PEERS:
		FixtureBaseMode.ready(game, peer)
	for i in 1000:
		if game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(game, 1)
	for peer: int in PEERS:
		FixtureBaseMode.load_ack(game, peer)
	for i in 1000:
		if game.phase_id() == &"round":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_array(Array(game.diagnostics)).is_empty()
	return game
