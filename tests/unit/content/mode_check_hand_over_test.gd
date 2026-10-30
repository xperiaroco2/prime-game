extends GdUnitTestSuite
## ModeCheck on a HandOver (#1389; ARCHITECTURE §9.4): only an action on the HandOver intent may
## hold it, with every condition HandOver.required_conditions lists, never a reaction or a row's
## action; only a one-handed ItemKind may be handable. Items.hand_over's own guard (a rule error,
## nothing moves) is the last test.

const P1 := 1
const P2 := 2


func test_the_fixture_mode_passes() -> void:
	assert_array(Array(ModeCheck.run(FixtureHandOverModes.basic()).errors)).is_empty()


func test_only_a_one_handed_item_kind_may_be_handable() -> void:
	# #1389: a two-handed item is never handed over; the default is not handable.
	assert_bool(ItemKind.new().handable).is_false()
	assert_bool(ItemKind.new().is_handable()).is_false()
	var two := FixtureItemModes.basic()
	two.find_item_kind(&"package").handable = true
	_expect(two, "item kind package is handable but takes 2 hands, not 1")
	var none := FixtureItemModes.basic()
	none.find_item_kind(&"tool").hands = 0
	none.find_item_kind(&"tool").handable = true
	_expect(none, "item kind tool is handable but takes 0 hands, not 1")
	var one := FixtureHandOverModes.basic()
	one.find_item_kind(&"tool").handable = true
	_expect_none(one)
	assert_bool(one.find_item_kind(&"tool").is_handable()).is_true()


func test_a_handable_kind_where_no_phase_accepts_hand_over_is_refused() -> void:
	# #1389: the flag would mean nothing where nobody may send HandOver; one phase is enough.
	var mode := FixtureHandOverModes.basic()
	var round_spec := mode.find_phase(&"round")
	var accepts: Array[AcceptSpec] = []
	for accept: AcceptSpec in round_spec.accepts:
		if accept.intent != Intents.HAND_OVER:
			accepts.append(accept)
	round_spec.accepts = accepts
	_expect(mode, "item kind gift is handable, but no phase accepts HandOver")
	mode.find_phase(&"lobby").accepts.append(
		AcceptSpec.of(Intents.HAND_OVER, AcceptSpec.From.LIVING)
	)
	_expect_none(mode)


func test_a_hand_over_rule_lacking_any_required_condition_is_refused() -> void:
	for i in FixtureHandOverModes.conditions().size():
		var held := FixtureHandOverModes.conditions()
		var missing := held[i].get_script() as Script
		held.remove_at(i)
		var mode := FixtureHandOverModes.basic()
		mode.actions[mode.actions.size() - 1] = FixtureHandOverModes.hand_over_rule(held)
		_expect(mode, "requires the condition %s, which it lacks" % missing.get_global_name())


func test_a_negated_required_condition_does_not_count() -> void:
	var held := FixtureHandOverModes.conditions()
	held[3].negate = true
	var mode := FixtureHandOverModes.basic()
	mode.actions[mode.actions.size() - 1] = FixtureHandOverModes.hand_over_rule(held)
	_expect(mode, "requires the condition TargetLiving, which it lacks")


func test_a_hand_over_on_another_intent_in_a_reaction_or_in_a_row_is_refused() -> void:
	var on_use := FixtureHandOverModes.basic()
	var rule := FixtureHandOverModes.hand_over_rule(FixtureHandOverModes.conditions())
	rule.trigger = Intents.USE
	on_use.actions.append(rule)
	_expect(on_use, "rule Use hands over an item, which only the intent HandOver can")
	var reacting := FixtureHandOverModes.basic()
	var reaction := FixtureModes.rule(Facts.ITEM_RESTED, [], [HandOver.new()])
	reacting.reactions.append(reaction)
	_expect(reacting, "rule item_rested hands over an item, which only the intent HandOver can")
	var rowed := FixtureHandOverModes.basic()
	rowed.transitions[0].actions.append(HandOver.new())
	_expect(rowed, "hands over an item, which only a player's intent can")


func test_items_hand_over_refuses_an_item_not_in_the_givers_hand() -> void:
	var mode := FixtureHandOverModes.basic()
	var world := FlatWorldQuery.new()
	var game := FixtureItemModes.in_round(mode, [P1, P2], world)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	var lying := FixtureItemModes.lay(game, &"gift", Vector3(0, 0, 0.5))
	var held := FixtureHandOverModes.hold(game, P1, &"cup")
	var before := FixtureHandOverModes.signature(game)
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = world
	Items.hand_over(ctx, P1, P2, lying)
	Items.hand_over(ctx, P2, P1, held)
	Items.hand_over(ctx, P1, P1, held)
	Items.hand_over(ctx, P1, 999, held)
	assert_int(game.diagnostics.size()).is_equal(4)
	assert_str(FixtureHandOverModes.signature(game)).is_equal(before)


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
