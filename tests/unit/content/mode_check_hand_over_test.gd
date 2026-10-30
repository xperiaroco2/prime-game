extends GdUnitTestSuite
## ModeCheck on the hand-over offer (#1389, #1434; ARCHITECTURE §9.4): only an action on its own
## intent may hold a HandOver, a TakeOffer or a CancelOffer, with every condition its
## required_conditions lists, never a reaction or a row's action; a phase that accepts one lists an
## OfferTicks (its reach at least the HandOver rule's), and a row out of such a phase into one
## without runs an EndOffers. Offers' own guards (a rule error, nothing moves) are the last test.

const P1 := 1
const P2 := 2


func test_the_fixture_mode_passes() -> void:
	assert_array(Array(ModeCheck.run(FixtureHandOverModes.basic()).errors)).is_empty()


func test_a_hand_over_rule_lacking_any_required_condition_is_refused() -> void:
	# The negated Offering (one offer per giver) is the base mode's choice, not a requirement.
	for i in FixtureHandOverModes.conditions().size():
		var held := FixtureHandOverModes.conditions()
		var missing := held[i].get_script() as Script
		held.remove_at(i)
		var mode := FixtureHandOverModes.basic()
		mode.actions[_index_of(mode, Intents.HAND_OVER)] = FixtureHandOverModes.hand_over_rule(held)
		if missing == Offering:
			_expect_none(mode)
		else:
			_expect(mode, "requires the condition %s, which it lacks" % missing.get_global_name())


func test_a_take_or_cancel_rule_lacking_any_required_condition_is_refused() -> void:
	for intent: StringName in [Intents.TAKE_OFFER, Intents.CANCEL_OFFER]:
		var base := FixtureHandOverModes.basic()
		var full: Rule = base.actions[_index_of(base, intent)]
		for i in full.conditions.size():
			var mode := FixtureHandOverModes.basic()
			var rule: Rule = mode.actions[_index_of(mode, intent)]
			var missing := rule.conditions[i].get_script() as Script
			var held := rule.conditions.duplicate()
			held.remove_at(i)
			rule.conditions = held
			_expect(
				mode,
				(
					"rule %s hands over an item, which requires the condition %s, which it lacks"
					% [intent, missing.get_global_name()]
				)
			)


func test_a_negated_required_condition_does_not_count() -> void:
	var held := FixtureHandOverModes.conditions()
	held[2].negate = true
	var mode := FixtureHandOverModes.basic()
	mode.actions[_index_of(mode, Intents.HAND_OVER)] = FixtureHandOverModes.hand_over_rule(held)
	_expect(mode, "requires the condition TargetLiving, which it lacks")
	var cancel := FixtureHandOverModes.basic()
	(cancel.actions[_index_of(cancel, Intents.CANCEL_OFFER)] as Rule).conditions[0].negate = true
	_expect(cancel, "rule CancelOffer hands over an item, which requires the condition Offering")


func test_an_offer_effect_on_another_intent_in_a_reaction_or_in_a_row_is_refused() -> void:
	var effects: Dictionary[StringName, Script] = {
		Intents.HAND_OVER: HandOver, Intents.TAKE_OFFER: TakeOffer, Intents.CANCEL_OFFER: CancelOffer
	}
	for intent: StringName in effects:
		var on_use := FixtureHandOverModes.basic()
		var rule: Rule = (on_use.actions[_index_of(on_use, intent)] as Rule).duplicate()
		rule.trigger = Intents.USE
		on_use.actions.append(rule)
		_expect(on_use, "rule Use hands over an item, which only the intent %s can" % intent)
		var reacting := FixtureHandOverModes.basic()
		var effect := (effects[intent] as GDScript).new() as RuleEffect
		reacting.reactions.append(FixtureModes.rule(Facts.ITEM_RESTED, [], [effect]))
		_expect(
			reacting, "rule item_rested hands over an item, which only the intent %s can" % intent
		)
		var rowed := FixtureHandOverModes.basic()
		rowed.transitions[0].actions.append((effects[intent] as GDScript).new() as RuleEffect)
		_expect(rowed, "hands over an item, which only a player's intent can")


func test_a_phase_that_offers_lists_offer_ticks_with_the_hand_over_s_reach() -> void:
	var missing := FixtureHandOverModes.basic()
	var round_spec := missing.find_phase(&"round")
	round_spec.tick_systems = round_spec.tick_systems.filter(
		func(s: TickSystem) -> bool: return not s is OfferTicks
	)
	_expect(missing, "phase round accepts [&\"HandOver\", &\"TakeOffer\", &\"CancelOffer\"]")
	_expect(missing, "lists no OfferTicks")
	var short := FixtureHandOverModes.basic()
	_ticks_of(short).reach_m = 1.5
	_expect(short, "phase round: OfferTicks reach_m 1.5 is less than the HandOver reach 2.0")
	var timeless := FixtureHandOverModes.basic()
	_ticks_of(timeless).timeout_s = 0.0
	_expect(timeless, "timeout_s")


func test_a_row_out_of_an_offering_phase_without_end_offers_is_refused() -> void:
	# The limp's pattern (#1393): an offer lives in part state, which only ResetMatch clears.
	var mode := FixtureHandOverModes.basic()
	var leaving := 0
	for row: Transition in mode.transitions:
		if row.from == &"round" and row.to != &"round":
			leaving += 1
			row.actions = row.actions.filter(func(a: RuleEffect) -> bool: return not a is EndOffers)
			_expect(mode, "row round -> %s runs no EndOffers" % row.to)
	assert_int(leaving).is_greater(0)


func test_offers_guards_refuse_an_item_not_in_the_givers_hand_and_a_missing_offer() -> void:
	var mode := FixtureHandOverModes.basic()
	var world := FlatWorldQuery.new()
	var game := FixtureItemModes.in_round(mode, [P1, P2], world)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	var lying := FixtureItemModes.lay(game, &"gift", Vector3(0, 0, 0.5))
	FixtureHandOverModes.hold(game, P1, &"cup")
	var before := FixtureHandOverModes.signature(game)
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = world
	Offers.open(ctx, P1, P2, lying)
	Offers.open(ctx, P2, P1, null)
	Offers.take(ctx, P1, P2)
	Offers.take(ctx, P2, P1)
	assert_int(game.diagnostics.size()).is_equal(4)
	assert_array(Offers.all(game.state)).is_empty()
	assert_str(FixtureHandOverModes.signature(game)).is_equal(before)


func _index_of(mode: GameMode, intent: StringName) -> int:
	for i in mode.actions.size():
		if mode.actions[i].trigger == intent:
			return i
	return -1


func _ticks_of(mode: GameMode) -> OfferTicks:
	for system: TickSystem in mode.find_phase(&"round").tick_systems:
		if system is OfferTicks:
			return system as OfferTicks
	return null


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
