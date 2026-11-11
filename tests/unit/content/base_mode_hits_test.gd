extends GdUnitTestSuite
## The M8 release's hits in the base mode's Round (#1587; GDD §3 "The M8 release", "Melee: any item
## hits"): the engineer reversed the M8 slice's "no hitting" on 2026-11-04 (he meant the crystal is
## the only item, not that nobody hits), so the Round takes Use from the living again, and the
## dead's hall keeps its own (#1489). The fist hits 5 to the front and 10 to the back, the ship's
## crystal (a two-handed item) 20 and 40, a swing costs 25 stamina, at most once per 0.5 s, in a 30°
## zone 1.5 m deep. No other weapon: the Loading row still places no knife (the knife stays in the
## mode's list, as #1497 kept it). The lobby keeps its hits (#1439). The knockdown scenarios and the
## chaos run that need knives play FixtureBaseModeWithMelee, the base mode with them, pinned here
## too. Loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const PEERS: Array[int] = [1, 2, 3, 4]
## Far from the greybox's markers; player 2 stands 1 m north of player 1.
const SPOT := Vector3(0, 0, 100)
const NORTH := Vector3(0, 0, 1)
const SOUTH := Vector3(0, 0, -1)


func test_the_round_takes_use_from_the_living_and_keeps_the_quest_s_intents() -> void:
	var mode := load(BASE_MODE) as GameMode
	var living := AcceptSpec.From.LIVING
	var dead := AcceptSpec.From.DEAD
	var in_round := mode.find_phase(&"round")
	# The living hit in the Round again (#1587); the dead in their hall too (#1489).
	assert_int(in_round.senders_of(Intents.USE)).is_equal(living | dead)
	for intent: StringName in [
		Intents.PICK_UP,
		Intents.PUT_DOWN,
		Intents.THROW,
		Intents.INTERACT,
		Intents.USE_SECONDARY,
	]:
		var senders := living | (dead if intent != Intents.THROW else 0)
		assert_int(in_round.senders_of(intent)).override_failure_message(intent).is_equal(senders)
	# The lobby's hits stay (#1439).
	for phase: StringName in [&"lobby", &"countdown"]:
		var spec := mode.find_phase(phase)
		assert_int(spec.senders_of(Intents.USE)).override_failure_message(phase).is_equal(living)


## GDD §3 "Melee: any item hits": the mode's one Use rule is the fallback hit with the table's
## numbers (the knife keeps its own rule on its kind).
func test_the_mode_s_hit_has_the_gdd_s_numbers() -> void:
	var mode := load(BASE_MODE) as GameMode
	var uses := mode.actions.filter(func(rule: Rule) -> bool: return rule.trigger == Intents.USE)
	assert_array(uses).has_size(1)
	var rule := uses[0] as Rule
	var strike := rule.effects[0] as Strike
	assert_object(strike).is_not_null()
	assert_array([strike.damage, strike.back_damage]).is_equal([5, 10])
	assert_array([strike.two_handed_damage, strike.two_handed_back_damage]).is_equal([20, 40])
	assert_float(strike.angle_deg).is_equal(30.0)
	assert_float(strike.reach_m).is_equal(1.5)
	var cost := 0
	var cooldown_s := 0.0
	for condition: Condition in rule.conditions:
		if condition is StaminaCost:
			cost = (condition as StaminaCost).amount
		elif condition is Cooldown:
			cooldown_s = (condition as Cooldown).seconds
	assert_int(cost).is_equal(25)
	assert_float(cooldown_s).is_equal(0.5)
	# The ship's crystal is two-handed: it hits by the two-handed numbers.
	for kind: StringName in [&"crystal_charged", &"crystal_spent"]:
		assert_int(mode.find_item_kind(kind).hands).override_failure_message(kind).is_equal(2)


func test_the_loading_row_spawns_no_items() -> void:
	var mode := load(BASE_MODE) as GameMode
	var row := mode.find_transition(&"loading", &"all_loaded")
	assert_object(row).is_not_null()
	for action: RuleEffect in row.actions:
		assert_object(action).is_not_instanceof(SpawnItems)
	assert_object(row.actions.back()).is_instanceof(PlacePlayers)


func test_a_round_of_the_base_mode_places_no_knife() -> void:
	var game := _round_of(load(BASE_MODE) as GameMode)
	for id: int in game.state.items:
		assert_str(String(game.state.items[id].kind.id)).is_not_equal("knife")
	for peer: int in PEERS:
		for spawned: MatchEvent in game.view_of(peer).events_named(&"ItemSpawned"):
			assert_str(String((spawned as ItemSpawnedEvent).kind)).is_not_equal("knife")


## The fist (the empty hand) in a round of the shipped mode: 5 to a front, 10 to a back, a swing
## everyone sees, the damage only the victim learns.
func test_the_fist_hits_5_to_the_front_and_10_to_the_back_in_the_round() -> void:
	assert_int(_lost_to(SOUTH, &"")).is_equal(5)
	assert_int(_lost_to(NORTH, &"")).is_equal(10)


## The ship's crystal in the hand: 20 to a front, 40 to a back.
func test_the_crystal_hits_20_to_the_front_and_40_to_the_back_in_the_round() -> void:
	assert_int(_lost_to(SOUTH, &"crystal_charged")).is_equal(20)
	assert_int(_lost_to(NORTH, &"crystal_charged")).is_equal(40)


## A swing everyone sees; only the victim learns what it cost; the hand keeps the crystal.
func test_a_swing_is_public_and_its_damage_the_victim_s_alone() -> void:
	var game := _round_of(load(BASE_MODE) as GameMode)
	var crystal := _ready_to_hit(game, SOUTH, &"crystal_charged")
	FixtureCombatModes.use(game, 1, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 1)).is_empty()
	for peer: int in PEERS:
		assert_array(FixtureCombatModes.received(game, peer, &"Swung")).has_size(1)
	assert_int(crystal.holder).is_equal(1)
	assert_array(FixtureCombatModes.received(game, 2, &"Damaged")).has_size(1)
	for peer: int in [1, 3, 4]:
		assert_array(FixtureCombatModes.received(game, peer, &"Damaged")).is_empty()


func test_the_melee_fixture_is_the_base_mode_with_the_knives() -> void:
	var base := load(BASE_MODE) as GameMode
	var fixture := FixtureBaseModeWithMelee.mode()
	assert_str(fixture.resource_path).is_equal(FixtureBaseModeWithMelee.PATH)
	var living := AcceptSpec.From.LIVING
	var dead := AcceptSpec.From.DEAD
	assert_int(fixture.find_phase(&"round").senders_of(Intents.USE)).is_equal(living | dead)
	assert_int(base.find_phase(&"round").senders_of(Intents.USE)).is_equal(living | dead)
	var base_row := base.find_transition(&"loading", &"all_loaded")
	var row := fixture.find_transition(&"loading", &"all_loaded")
	assert_int(row.actions.size()).is_equal(base_row.actions.size() + 1)
	var spawn := row.actions[row.actions.size() - 2] as SpawnItems
	assert_object(spawn).is_not_null()
	assert_str(String(spawn.kind.id)).is_equal("knife")
	assert_str(String(spawn.count_setting)).is_equal("knives")
	assert_object(row.actions.back()).is_instanceof(PlacePlayers)
	# The shipped mode keeps the knives setting, but nothing reads it there: the lobby hides it
	# (#1525); the fixture's knife spawn reads it again.
	assert_object(base.find_setting(&"knives")).is_not_null()
	assert_array(base.read_settings()).not_contains([&"knives"])
	assert_array(fixture.read_settings()).contains([&"knives"])
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


## The whole points player 2 loses to one swing of player 1 (empty-handed, or holding `kind`) in a
## round of the shipped mode, player 2 facing `facing` (SOUTH: towards player 1, NORTH: away).
func _lost_to(facing: Vector3, kind: StringName) -> int:
	var game := _round_of(load(BASE_MODE) as GameMode)
	_ready_to_hit(game, facing, kind)
	var before := game.state.player(2).health
	FixtureCombatModes.use(game, 1, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, 1)).is_empty()
	return roundi((before - game.state.player(2).health) / float(Ticks.THOUSANDTHS))


## Player 1 at SPOT (holding an item of `kind` laid at its feet, unless empty), player 2 1 m north
## facing `facing`, both past the round's first invulnerability; the item, or null.
func _ready_to_hit(game: Match, facing: Vector3, kind: StringName) -> ItemState:
	FixtureItemModes.stand(game, 1, SPOT)
	FixtureItemModes.stand(game, 2, SPOT + NORTH)
	var item: ItemState = null
	if not kind.is_empty():
		item = FixtureItemModes.lay(game, kind, SPOT)
		FixtureItemModes.pick_up(game, 1, item)
		assert_int(item.holder).override_failure_message(kind).is_equal(1)
	FixtureMoves.claim(game, 2, game.state.player(2).position, {"facing": facing})
	var invulnerable := ceili(game.mode.player_rules.invulnerable_s * Ticks.RATE) + 1
	FixtureModes.run_ticks(game, maxi(invulnerable, FixtureCombatModes.COOLDOWN_TICKS))
	FixtureItemModes.stand(game, 1, SPOT)
	FixtureItemModes.stand(game, 2, SPOT + NORTH)
	return item


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
