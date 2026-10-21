extends GdUnitTestSuite
## ModeCheck on rules that never run or change nothing (#1236): an action on MoveClaim (the
## movement rule takes it) or on an intent the class of every phase that accepts it handles
## (Match._dispatch hands it to the class first) is an error; a reaction with no
## effects a warning, an action with none no finding (it stops its actor's channel: StopRaise).
## Each found on FixtureModes.basic() with one thing wrong.

const NEVER := "is never reached"


func test_an_action_on_move_claim_is_never_reached() -> void:
	var mode := FixtureModes.basic()
	var dash: Array[RuleEffect] = [FixtureNote.of("dashed")]
	mode.actions.append(FixtureModes.rule(Intents.MOVE_CLAIM, [], dash))
	_expect(mode, "mode.actions: rule on MoveClaim is never reached: the movement rule takes it")
	mode = FixtureModes.basic()
	mode.roles[1].actions = [FixtureModes.rule(Intents.MOVE_CLAIM, [], dash)]
	_expect(mode, "role dissident.actions: rule on MoveClaim is never reached")


func test_an_action_every_accepting_phase_class_takes_is_never_reached() -> void:
	var mode := FixtureModes.basic()
	var readied: Array[RuleEffect] = [FixtureNote.of("readied")]
	mode.actions.append(FixtureModes.rule(Intents.SET_READY, [], readied))
	_expect(
		mode,
		(
			"mode.actions: rule on SetReady is never reached: the class of every phase that"
			+ " accepts it takes it"
		)
	)
	# The round's class (RoundPhase) does not handle SetReady: there the rule runs.
	mode.phases[1].accepts.append(AcceptSpec.of(Intents.SET_READY, AcceptSpec.From.PLAYER))
	_expect_none(mode)


func test_an_action_no_phase_class_takes_is_reached() -> void:
	var check := ModeCheck.run(FixtureModes.basic())
	assert_str(" ".join(check.errors)).not_contains(NEVER)


func test_a_reaction_with_no_effects_is_a_warning() -> void:
	var mode := FixtureModes.basic()
	mode.reactions = [FixtureModes.rule(Facts.ITEM_RESTED, [], [])]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_str(" ".join(check.warnings)).contains(
		"mode.reactions: rule item_rested holds no effects, so it changes nothing"
	)


func test_an_action_with_no_effects_is_no_finding() -> void:
	var mode := FixtureModes.basic()
	mode.actions[0].effects.clear()
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	(
		assert_str(" ".join(errors))
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. contains(fragment)
	)


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
