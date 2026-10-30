extends GdUnitTestSuite
## The base mode's melee in `content/` (#1437, the mechanic #1436, approved on #1095; the
## engineer's placeholders until a playtest): one mode rule on Use, the fallback of every hand
## without a Use rule of its own: Cooldown (`hit`, 0.5 s), StaminaCost (25), Strike (30°, 1.5 m, 5
## front, 10 back, a two-handed hand 20 and 40; the knife's launch, 4 m/s away and 2 m/s up, "not a
## decision"); the knife keeps its own, 50 front and 75 back. A hit from behind: the attacker in the
## target's rear half (the engineer's answer on #1437). Played in the hall, which takes Use from the
## living (#1388). Loads `content/` and the levels on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const P1 := 1
const P2 := 2
const NORTH := Vector3(0, 0, 1)
const SOUTH := Vector3(0, 0, -1)
## Far from the hall's markers; P2 stands 1 m north of P1.
const SPOT := Vector3(0, 0, 100)
const HEALTH := 100000


func test_the_mode_has_one_use_rule_the_fallback_hit() -> void:
	var mode := load(BASE_MODE) as GameMode
	var rules := mode.actions.filter(func(rule: Rule) -> bool: return rule.trigger == Intents.USE)
	assert_array(rules).has_size(1)
	var rule: Rule = rules[0]
	assert_int(rule.conditions.size()).is_equal(2)
	var cooldown := rule.conditions[0] as Cooldown
	assert_object(cooldown).is_not_null()
	assert_str(String(cooldown.key)).is_equal("hit")
	assert_float(cooldown.seconds).is_equal(0.5)
	var stamina := rule.conditions[1] as StaminaCost
	assert_object(stamina).is_not_null()
	assert_int(stamina.amount).is_equal(25)
	assert_int(rule.effects.size()).is_equal(1)
	var strike := rule.effects[0] as Strike
	assert_object(strike).is_not_null()
	assert_float(strike.angle_deg).is_equal(30.0)
	assert_float(strike.reach_m).is_equal(1.5)
	assert_int(strike.damage).is_equal(5)
	assert_int(strike.back_damage).is_equal(10)
	assert_int(strike.two_handed_damage).is_equal(20)
	assert_int(strike.two_handed_back_damage).is_equal(40)
	assert_float(strike.launch_mps).is_equal(4.0)
	assert_float(strike.launch_up_mps).is_equal(2.0)
	# No role condition: the public Swung must not reveal a role (§9.2); no HoldsItem: the empty
	# hand hits.
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_the_knife_hits_50_from_the_front_and_75_from_behind() -> void:
	var mode := load(BASE_MODE) as GameMode
	var strike := mode.find_item_kind(&"knife").actions[0].effects[0] as Strike
	assert_int(strike.damage).is_equal(50)
	assert_int(strike.back_damage).is_equal(75)
	assert_int(strike.two_handed_damage).is_equal(0)
	assert_int(_taken(SOUTH, &"knife")).is_equal(50)
	assert_int(_taken(NORTH, &"knife")).is_equal(75)


func test_no_two_handed_kind_has_a_use_rule_of_its_own() -> void:
	# So every two-handed item hits by the fallback's two-handed pair.
	var mode := load(BASE_MODE) as GameMode
	var two_handed := 0
	for kind: ItemKind in mode.item_kinds:
		if not kind.is_two_handed():
			continue
		two_handed += 1
		for rule: Rule in kind.actions:
			(
				assert_str(String(rule.trigger))
				. override_failure_message(String(kind.id))
				. is_not_equal(String(Intents.USE))
			)
	assert_int(two_handed).is_greater(0)


func test_the_empty_hand_and_a_package_hit_by_the_fallback() -> void:
	assert_int(_taken(SOUTH)).is_equal(5)
	assert_int(_taken(NORTH)).is_equal(10)
	assert_int(_taken(SOUTH, &"package")).is_equal(20)
	assert_int(_taken(NORTH, &"package")).is_equal(40)


## The whole points P2 loses to one Use of P1 in the hall: P1 at SPOT facing north, holding an
## item of `kind` (none when empty), P2 1 m north of it, facing `facing` by a MoveClaim.
func _taken(facing: Vector3, kind: StringName = &"") -> int:
	var mode := load(BASE_MODE) as GameMode
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureItemModes.stand(game, P1, SPOT)
	if not kind.is_empty():
		var item := game.state.add_item(mode.find_item_kind(kind), SPOT)
		FixtureItemModes.pick_up(game, P1, item)
		assert_int(game.state.player(P1).held_item).is_equal(item.id)
	FixtureItemModes.stand(game, P2, SPOT + NORTH)
	FixtureMoves.claim(game, P2, SPOT + NORTH, {"facing": facing})
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	return roundi((HEALTH - game.state.player(P2).health) / 1000.0)


func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts
