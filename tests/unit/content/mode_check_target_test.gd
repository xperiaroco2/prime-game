extends GdUnitTestSuite
## ModeCheck's refusal of a condition that reads the rule's target where nothing supplies one
## (ARCHITECTURE §9.1, §9.4; #379): a mode reaction has only its fact, and a win condition has no
## intent, channel or fact. The conditions that read the actor (#299) are tested in
## mode_check_actor_test.gd, which also lists every condition's classification.

const P1 := 1
const P2 := 2


func test_a_win_condition_holding_a_condition_that_reads_the_target_is_refused() -> void:
	# A win condition is checked with no intent, channel or fact: TargetDowned finds target 0 and
	# ItemOnGround no item, so neither ever passes there (and, negated, both always do).
	var conditions: Array[Condition] = [TargetDowned.new(), ItemOnGround.new()]
	for condition: Condition in conditions:
		var mode := _winning_with([condition])
		var error := (
			(
				"mode.win_conditions[1]: the win condition dissidents of the mode holds the"
				+ " condition %s, which reads the rule's target: a win condition is checked with no"
				+ " intent, channel or fact to supply one, so the condition finds no target and its"
				+ " answer never changes"
			)
			% _class_name(condition)
		)
		assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])
		# Match refuses the mode, as for every ModeCheck error.
		var game := FixtureModes.create(mode)
		assert_array(Array(game.refusals)).contains([error])
		assert_bool(game.start(0)).is_false()
		assert_array(game.emitted()).is_empty()


func test_a_reaction_holding_a_condition_whose_fact_supplies_no_target_is_refused() -> void:
	# No fact carries a target player, so TargetDowned is refused in every reaction; only
	# item_rested carries an item, so ItemOnGround is refused on clock_ended.
	var cases: Array[Array] = [
		[TargetDowned.new(), Facts.CLOCK_ENDED],
		[TargetDowned.new(), Facts.ITEM_RESTED],
		[TargetDowned.new(), Facts.PLAYER_DIED],
		[ItemOnGround.new(), Facts.CLOCK_ENDED],
		[ItemOnGround.new(), Facts.SUBTASK_DONE],
	]
	for entry: Array in cases:
		var condition: Condition = entry[0]
		var fact: StringName = entry[1]
		var error := (
			(
				"mode.reactions[1]: the reaction on %s of the mode holds the condition %s, which"
				+ " reads the rule's target: a reaction runs with no intent or channel and its fact"
				+ " %s supplies none, so the condition finds no target and its answer never changes"
			)
			% [fact, _class_name(condition), fact]
		)
		var mode := _reacting_on(fact, [condition])
		assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])


func test_a_negated_condition_that_reads_the_target_is_refused() -> void:
	# Negated, it still finds no target: it passes every time instead of never.
	var downed := TargetDowned.new()
	downed.negate = true
	var errors := Array(ModeCheck.run(_winning_with([downed])).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).contains("holds the condition TargetDowned, which reads the rule's")
	errors = Array(ModeCheck.run(_reacting_on(Facts.CLOCK_ENDED, [downed])).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).contains("holds the condition TargetDowned, which reads the rule's")


func test_a_reaction_whose_fact_supplies_the_target_is_allowed() -> void:
	# item_rested carries its item (Fact.item), which Items.target_of reads.
	var on_ground := ItemOnGround.new()
	var negated := ItemOnGround.new()
	negated.negate = true
	for condition: Condition in [on_ground, negated]:
		var conditions: Array[Condition] = [condition]
		var mode := _reacting_on(Facts.ITEM_RESTED, conditions)
		assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_an_item_rested_reaction_finds_its_item_on_the_ground() -> void:
	# The premise of ItemOnGround.target_facts: in a reaction on item_rested, Items.target_of
	# reads the fact's item, so the condition passes for the item that came to rest.
	var mode := FixtureCombatModes.basic()
	var on_ground: Array[Condition] = [ItemOnGround.new()]
	var note: Array[RuleEffect] = [FixtureNote.of("reacted")]
	mode.reactions = [FixtureModes.rule(Facts.ITEM_RESTED, on_ground, note)]
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	var game := FixtureCombatModes.in_round(mode, [P1, P2])
	FixtureItemModes.stand(game, P2, Vector3(2, 0, 2))
	FixtureItemModes.pick_up(game, P2, FixtureItemModes.lay(game, &"package", Vector3(2, 0, 2)))
	assert_array(FixtureModes.notes(game)).not_contains(["reacted"])
	# Leaving drops the held package on the floor: item_rested, with the package as its item.
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(FixtureModes.notes(game)).contains(["reacted"])


func test_a_condition_that_reads_the_actor_and_the_target_gets_one_error() -> void:
	# TargetInReach reads both: the actor's error says enough, and the target's is not added.
	var condition := TargetInReach.new()
	condition.reach_m = 2.0
	var conditions: Array[Condition] = [condition]
	for mode: GameMode in [_winning_with(conditions), _reacting_on(Facts.CLOCK_ENDED, conditions)]:
		var errors := Array(ModeCheck.run(mode).errors)
		assert_array(errors).has_size(1)
		assert_str(str(errors[0])).contains(
			"holds the condition TargetInReach, which reads the actor:"
		)


func test_the_refusal_names_the_modes_file() -> void:
	var mode := _winning_with([ClockEnded.new(), TargetDowned.new()])
	mode.resource_path = "res://tests/fixtures/match/winning_mode.tres"
	var errors := ModeCheck.run(mode).errors
	assert_array(Array(errors)).has_size(1)
	assert_str(errors[0]).starts_with(
		(
			"mode.win_conditions[1]: the win condition dissidents of mode"
			+ " res://tests/fixtures/match/winning_mode.tres holds the condition TargetDowned,"
		)
	)


## FixtureModes.basic() with two reactions: one on a fact other than `fact` that holds nothing,
## then one on `fact` (reactions[1]) that holds `conditions` and notes "reacted".
func _reacting_on(fact: StringName, conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	var note: Array[RuleEffect] = [FixtureNote.of("reacted")]
	var other := Facts.PLAYER_LEFT if fact != Facts.PLAYER_LEFT else Facts.CLOCK_ENDED
	mode.reactions = [
		FixtureModes.rule(other, [], []),
		FixtureModes.rule(fact, conditions, note),
	]
	return mode


## FixtureModes.basic() whose second win condition (win_conditions[1], the dissidents') holds
## `conditions`.
func _winning_with(conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	mode.win_conditions[1].conditions = conditions
	return mode


static func _class_name(condition: Condition) -> String:
	return String((condition.get_script() as Script).get_global_name())
