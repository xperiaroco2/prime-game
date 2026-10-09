extends GdUnitTestSuite
## ModeCheck on throwing (ARCHITECTURE §9.1, §7.1.16; the throwing ADR, TE2, TD11): a phase that
## accepts an intent whose rule throws lists FlightTicks; a ThrowItem runs only in a player's
## action, after HoldsItem and OverFloor; its numbers are within their bounds and its radius fits
## the capsule at the eye. Each found on FixtureThrowModes.basic() with one thing wrong.


func test_the_throw_fixture_passes() -> void:
	var check := ModeCheck.run(FixtureThrowModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_a_phase_that_accepts_a_throw_must_list_flight_ticks() -> void:
	var mode := FixtureThrowModes.basic()
	var round_spec := mode.find_phase(&"round")
	# FixtureThrowModes lists FlightTicks last.
	assert_bool(round_spec.tick_systems.back() is FlightTicks).is_true()
	round_spec.tick_systems.pop_back()
	_expect(mode, 'phase round accepts [&"Throw"], which throws an item')
	_expect(mode, "lists no FlightTicks")


func test_a_throw_on_an_item_kinds_use_rule_needs_flight_ticks_too() -> void:
	# The check follows the effect, not the intent's name: the package's own Use throws it.
	var mode := FixtureItemModes.basic()
	mode.find_item_kind(&"package").actions.append(
		FixtureModes.rule(
			Intents.USE, [HoldsItem.new(), OverFloor.new()], [FixtureThrowModes.effect()]
		)
	)
	_expect(mode, 'phase round accepts [&"Use"], which throws an item')
	mode.find_phase(&"round").tick_systems.append(FlightTicks.new())
	_expect_none(mode)


func test_a_throw_rule_that_throws_nothing_needs_no_flight_ticks() -> void:
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.THROW, [], [FixtureNote.of("noted")]))
	mode.find_phase(&"round").accepts.append(AcceptSpec.of(Intents.THROW, AcceptSpec.From.LIVING))
	_expect_none(mode)


func test_a_throw_needs_holds_item_and_over_floor_not_negated() -> void:
	for missing: int in 2:
		var mode := FixtureThrowModes.basic()
		var throw_rule: Rule = mode.actions[mode.actions.size() - 1]
		throw_rule.conditions.remove_at(missing)
		var name := "HoldsItem" if missing == 0 else "OverFloor"
		_expect(mode, "rule Throw throws an item, which requires the condition %s" % name)
	var negated := FixtureThrowModes.basic()
	var rule: Rule = negated.actions[negated.actions.size() - 1]
	rule.conditions[1].negate = true
	_expect(negated, "rule Throw throws an item, which requires the condition OverFloor")


func test_a_throw_outside_an_action_is_refused() -> void:
	var mode := FixtureThrowModes.basic()
	var reaction := FixtureModes.rule(Facts.ITEM_RESTED, [], [FixtureThrowModes.effect()])
	mode.reactions = [reaction]
	_expect(mode, "mode.reactions: rule item_rested throws an item")
	mode.reactions = []
	mode.transitions[1].actions.append(FixtureThrowModes.effect())
	_expect(mode, "row round, won throws an item")


func test_its_numbers_are_within_their_bounds() -> void:
	var mode := FixtureThrowModes.basic()
	var effect := _effect(mode)
	effect.speed_mps = 0.0
	effect.gravity_mps2 = 0.0
	effect.radius_m = 0.0
	effect.longest_flight_s = 0.0
	_expect(mode, "ThrowItem speed_mps is 0, outside 1 to 40")
	_expect(mode, "ThrowItem gravity_mps2 is 0, outside 1 to 40")
	_expect(mode, "ThrowItem radius_m is 0, outside 0.02 to 0.5")
	_expect(mode, "ThrowItem longest_flight_s is 0, outside 0.5 to 30")
	effect.speed_mps = 41.0
	effect.gravity_mps2 = 41.0
	effect.longest_flight_s = 31.0
	_expect(mode, "ThrowItem speed_mps is 41, outside 1 to 40")
	_expect(mode, "ThrowItem gravity_mps2 is 41, outside 1 to 40")
	_expect(mode, "ThrowItem longest_flight_s is 31, outside 0.5 to 30")
	effect.speed_mps = 10.0
	effect.gravity_mps2 = 9.8
	effect.radius_m = 0.15
	effect.longest_flight_s = 3.0
	_expect_none(mode)


func test_the_radius_fits_the_capsule_above_the_eye() -> void:
	# The fixture capsule: radius 0.4 m, height 1.8 m, eye at 1.6 m: 0.2 m above the eye is the
	# smaller room, so 0.2 - 0.01 = 0.19 m.
	var mode := FixtureThrowModes.basic()
	assert_float(ThrowItem.largest_radius(mode.player_rules)).is_equal_approx(0.19, 1e-9)
	_expect_radius(mode)


func test_the_radius_fits_the_capsule_sideways() -> void:
	# The eye at 1 m in a capsule of radius 0.3 m: its radius is the smaller room, 0.29 m.
	var mode := FixtureThrowModes.basic()
	mode.player_rules.eye_height_m = 1.0
	mode.player_rules.capsule_radius_m = 0.3
	assert_float(ThrowItem.largest_radius(mode.player_rules)).is_equal_approx(0.29, 1e-9)
	_expect_radius(mode)


func test_a_role_owned_throw_rule_warns_that_it_reveals_the_role() -> void:
	# ItemThrown goes to everyone with the rule's exact speed and gravity (§9.2).
	var mode := FixtureThrowModes.basic()
	mode.find_role(&"crew").actions = [FixtureThrowModes.throw_rule(FixtureThrowModes.effect(7.0))]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_str(" ".join(check.warnings)).contains(
		"role crew.actions: rule Throw is role-owned or role-gated and emits an event to everyone"
	)


## The mode's ThrowItem: the last action's effect.
func _effect(mode: GameMode) -> ThrowItem:
	return mode.actions[mode.actions.size() - 1].effects[0] as ThrowItem


## A radius exactly at ThrowItem.largest_radius passes; a millimetre more is refused.
func _expect_radius(mode: GameMode) -> void:
	var effect := _effect(mode)
	effect.radius_m = ThrowItem.largest_radius(mode.player_rules)
	_expect_none(mode)
	effect.radius_m += 0.001
	_expect(mode, "ThrowItem radius_m is %s, more than" % ContentPart.number(effect.radius_m))
	_expect(mode, "would stick out of the player's capsule")


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
