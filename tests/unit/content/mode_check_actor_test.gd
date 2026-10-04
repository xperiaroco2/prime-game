extends GdUnitTestSuite
## ModeCheck's refusal of a condition that reads the actor where no player acts (ARCHITECTURE
## §9.1, §9.2; #299): a mode reaction runs, and a win condition is checked, for actor 0. The costs
## in a reaction (#283) are tested in mode_check_test.gd.


func test_a_reaction_holding_a_condition_that_reads_the_actor_is_refused() -> void:
	# HoldsItem never passes for actor 0, HandNotTwoHanded always does: either way the condition
	# tests no player, so the reaction runs always or never whatever the players do.
	var conditions: Array[Condition] = [HoldsItem.new(), HandNotTwoHanded.new(), _in_reach()]
	for condition: Condition in conditions:
		var mode := _reacting_on_the_clock([condition])
		var error := (
			(
				"mode.reactions[1]: the reaction on clock_ended of the mode holds the condition %s,"
				+ " which reads the actor: a reaction runs for no player (actor 0), so the"
				+ " condition tests no player and its answer never changes"
			)
			% _class_name(condition)
		)
		assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])
		# Match refuses the mode, as for every ModeCheck error.
		var game := FixtureModes.create(mode)
		assert_array(Array(game.refusals)).contains([error])
		assert_bool(game.start(0)).is_false()
		assert_array(game.emitted()).is_empty()


func test_a_negated_condition_that_reads_the_actor_is_refused_in_a_reaction() -> void:
	# Negated, it still tests no player: a negated HoldsItem passes for actor 0 every time.
	var holds := HoldsItem.new()
	holds.negate = true
	var errors := Array(ModeCheck.run(_reacting_on_the_clock([holds])).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).starts_with(
		"mode.reactions[1]: the reaction on clock_ended of the mode holds the condition HoldsItem,"
	)


func test_a_win_condition_holding_a_cost_that_reads_the_actor_is_refused() -> void:
	var costs: Array[Cost] = [
		FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S),
		FixtureCombatModes.stamina_cost(FixtureCombatModes.STAMINA_COST),
	]
	for cost: Cost in costs:
		var mode := _winning_with([FixtureCounterAtLeast.of(&"dissidents_win"), cost])
		var error := (
			(
				"mode.win_conditions[1]: the win condition dissidents of the mode holds the cost %s,"
				+ " which reads the actor's player state: a win condition is checked for no player"
				+ " (actor 0), so the cost always refuses and the win condition never holds"
			)
			% _class_name(cost)
		)
		assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])
		var game := FixtureModes.create(mode)
		assert_array(Array(game.refusals)).contains([error])
		assert_bool(game.start(0)).is_false()


func test_a_win_condition_holding_a_condition_that_reads_the_actor_is_refused() -> void:
	# A negated cost passes for actor 0, so it gets the condition's words, not "always refuses".
	var negated := FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S)
	negated.negate = true
	var conditions: Array[Condition] = [HoldsItem.new(), _target_in_reach(), negated]
	for condition: Condition in conditions:
		var mode := _winning_with([condition])
		var error := (
			(
				"mode.win_conditions[1]: the win condition dissidents of the mode holds the"
				+ " condition %s, which reads the actor: a win condition is checked for no player"
				+ " (actor 0), so the condition tests no player and its answer never changes"
			)
			% _class_name(condition)
		)
		assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])


func test_the_refused_win_condition_names_the_modes_file_and_each_condition() -> void:
	var mode := _winning_with([HoldsItem.new(), FixtureCounterAtLeast.of(&"x"), Channeling.new()])
	mode.resource_path = "res://tests/fixtures/match/winning_mode.tres"
	var errors := ModeCheck.run(mode).errors
	assert_array(Array(errors)).has_size(2)
	var where := "the win condition dissidents of mode res://tests/fixtures/match/winning_mode.tres"
	assert_str(errors[0]).contains(where + " holds the condition HoldsItem,")
	assert_str(errors[1]).contains(where + " holds the condition Channeling,")


func test_a_condition_that_does_not_say_is_refused_and_named_by_its_base() -> void:
	# Condition.reads_actor_state defaults to true, so a condition that forgets to say is refused
	# where no player acts; one without a class_name is named by the class it extends.
	var errors := Array(ModeCheck.run(_winning_with([ConditionWithNoName.new()])).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).starts_with(
		(
			"mode.win_conditions[1]: the win condition dissidents of the mode holds the condition"
			+ " a Condition with no class_name,"
		)
	)
	errors = Array(ModeCheck.run(_reacting_on_the_clock([ConditionWithNoName.new()])).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).contains("holds the condition a Condition with no class_name,")


func test_conditions_that_read_no_actor_pass_in_reactions_and_win_conditions() -> void:
	# Not TargetDowned, nor ItemOnGround in a win condition: they read no actor, so this check
	# allows them, but with no intent, channel or fact they find no target there (§9.4 "Where").
	var all_done := AllSubtasksDone.new()
	all_done.negate = true
	var conditions: Array[Condition] = [ClockEnded.new(), all_done, NoneAlive.of(&"crew")]
	_expect_none(_winning_with(conditions))
	conditions.append(ItemOnGround.new())
	_expect_none(_reacting_on_the_clock(conditions))
	# The conditions refused there are fine in an action: the raise holds four of them.
	_expect_none(FixtureCombatModes.raising())


func test_empty_entries_are_reported_not_a_crash() -> void:
	var mode := _winning_with([null])
	mode.win_conditions.append(null)
	mode.reactions = [null, FixtureModes.rule(Facts.CLOCK_ENDED, [null], [])]
	(
		assert_array(Array(ModeCheck.run(mode).errors))
		. contains_exactly_in_any_order(
			[
				"mode.reactions has an empty entry",
				"mode.reactions[1].conditions has an empty entry",
				"mode.win_conditions has an empty entry",
				"mode.win_conditions[1].conditions has an empty entry",
			]
		)
	)


func test_an_unnamed_condition_is_named_by_its_nearest_named_base() -> void:
	var errors := Array(ModeCheck.run(_winning_with([UnnamedSubclass.new()])).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).contains("holds the condition a Condition with no class_name,")
	var cost := Array(ModeCheck.run(_winning_with([CostWithNoName.new()])).errors)
	assert_array(cost).has_size(1)
	assert_str(str(cost[0])).contains("holds the cost a Cost with no class_name,")


func test_every_condition_in_core_says_whether_it_reads_the_actor() -> void:
	# The conditions of core/ and whether they read the actor (Condition.reads_actor_state), so a
	# mode reaction or a win condition may not hold them (true) or may (false). A new condition in
	# core/ fails this test until it is listed here and in ARCHITECTURE §9.4. It finds conditions
	# by class_name, as every core/ part has one (§9.4); one without keeps the default and is
	# refused (test_a_condition_that_does_not_say_is_refused_and_named_by_its_base).
	var expected: Dictionary[StringName, bool] = {
		&"AllSubtasksDone": false,
		&"CarriesItem": true,
		&"ChannelFree": true,
		&"Channeling": true,
		&"ClockEnded": false,
		&"Cooldown": true,
		&"Cost": true,
		&"HandNotTwoHanded": true,
		&"HoldsItem": true,
		&"InReach": true,
		&"InSight": true,
		&"ItemOnGround": false,
		&"NoneAlive": false,
		&"StaminaCost": true,
		&"TargetDowned": false,
		&"TargetInReach": true,
		&"TargetInSight": true,
	}
	var found: Dictionary[StringName, bool] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = entry["path"]
		var class_id: StringName = entry["class"]
		if (
			path.begins_with("res://core/")
			and class_id != &"Condition"
			and _extends(class_id, &"Condition")
		):
			var condition := (load(path) as GDScript).new() as Condition
			found[class_id] = condition.reads_actor_state()
	assert_dict(found).is_equal(expected)
	# The base class's default: a condition that does not say reads the actor.
	assert_bool(Condition.new().reads_actor_state()).is_true()


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


## FixtureModes.basic() with two reactions: one on item_rested that holds nothing, then one on
## clock_ended (reactions[1]) that holds `conditions` and notes "reacted".
func _reacting_on_the_clock(conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	var note: Array[RuleEffect] = [FixtureNote.of("reacted")]
	mode.reactions = [
		FixtureModes.rule(Facts.ITEM_RESTED, [], []),
		FixtureModes.rule(Facts.CLOCK_ENDED, conditions, note),
	]
	return mode


## FixtureModes.basic() whose second win condition (win_conditions[1], the dissidents') holds
## `conditions`.
func _winning_with(conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	mode.win_conditions[1].conditions = conditions
	return mode


static func _in_reach() -> InReach:
	var condition := InReach.new()
	condition.reach_m = 2.0
	return condition


static func _target_in_reach() -> TargetInReach:
	var condition := TargetInReach.new()
	condition.reach_m = 2.0
	return condition


static func _class_name(condition: Condition) -> String:
	return String((condition.get_script() as Script).get_global_name())


## Whether the global class `class_id` is `base` or extends it.
static func _extends(class_id: StringName, base: StringName) -> bool:
	var current := class_id
	while not current.is_empty():
		if current == base:
			return true
		current = _global_base(current)
	return false


static func _global_base(class_id: StringName) -> StringName:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == class_id:
			return entry["base"]
	return &""


## A condition with no class_name and no say on reads_actor_state, so it keeps the default (true).
class ConditionWithNoName:
	extends Condition


## An unnamed condition that extends another unnamed one.
class UnnamedSubclass:
	extends ConditionWithNoName


## A cost with no class_name and no say on reads_actor_state, so it keeps the default (true).
class CostWithNoName:
	extends Cost
