extends GdUnitTestSuite
## The mode check on the pinball's parts (ARCHITECTURE §9.4, §9.5; #1398): UsePinball's balls and
## targets, the conditions its Interact rule must hold, SetFlippers only on Flippers behind a
## PinballSeated, PinballTicks.problems (a phase that places the machine or accepts Flippers lists
## PinballTicks, a row out of it runs EndPinball); and LayoutCheck's exact one `pinball` marker.

const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_fixture_mode_and_layouts_pass() -> void:
	assert_array(Array(ModeCheck.run(FixturePinball.mode()).errors)).is_empty()
	var found := LayoutCheck.run(FixturePinball.mode(), FixturePinball.layouts())
	assert_array(Array(found)).is_empty()


## The check walks every rule of a mode for the pinball's parts (Pinball.rules_holding). It must
## print no engine error doing so: `bots` and the host fail on any (#1398's review).
func test_the_mode_check_prints_no_engine_error() -> void:
	var errors := EngineErrors.new()
	errors.start()
	var fixture := ModeCheck.run(FixturePinball.mode())
	var base := ModeCheck.run(load(BASE_MODE) as GameMode)
	errors.stop()
	assert_array(Array(fixture.errors)).is_empty()
	assert_array(Array(base.errors)).is_empty()
	(
		assert_int(errors.count())
		. override_failure_message("\n".join(errors.snapshot().slice(0, 4)))
		. is_equal(0)
	)


func test_an_interact_rule_without_pinball_usable_is_refused() -> void:
	var made := FixturePinball.mode()
	var rule := _machine_rule(made)
	rule.conditions.assign(
		rule.conditions.filter(func(c: Condition) -> bool: return c is not PinballUsable)
	)
	_expect(made, "requires the condition PinballUsable")


func test_balls_out_of_one_to_nine_are_refused() -> void:
	for balls: int in [0, 10]:
		var made := FixturePinball.mode()
		_use(made).balls = balls
		_expect(made, "balls is %d, outside 1 to 9" % balls)


func test_no_target_a_doubled_id_and_zero_points_are_refused() -> void:
	var none := FixturePinball.mode()
	_use(none).targets = []
	_expect(none, "UsePinball needs at least one target")
	var doubled := FixturePinball.mode()
	_use(doubled).targets.append(FixturePinball.target(&"bumper", 10))
	_expect(doubled, "UsePinball has two targets of id bumper")
	var zero := FixturePinball.mode()
	_use(zero).targets[0].points = 0
	_expect(zero, "points is 0, outside 1 to 100000")


func test_use_pinball_outside_a_station_kinds_interact_rule_is_refused() -> void:
	var made := FixturePinball.mode()
	var use := UsePinball.new()
	use.targets = [FixturePinball.target(&"bumper", 1)]
	made.actions.append(FixtureModes.rule(Intents.INTERACT, [] as Array[Condition], [use]))
	_expect(made, "UsePinball is only for a station kind's rule on Interact")


func test_set_flippers_on_another_trigger_or_without_pinball_seated_is_refused() -> void:
	var other := FixturePinball.mode()
	other.actions.append(
		FixtureModes.rule(
			Intents.INTERACT, [PinballSeated.new()] as Array[Condition], [SetFlippers.new()]
		)
	)
	_expect(other, "SetFlippers is only for a rule on Flippers, not Interact")
	var unseated := FixturePinball.mode()
	_flippers_rule(unseated).conditions = []
	_expect(unseated, "the rule on Flippers sets the flippers but holds no PinballSeated")
	var negated := FixturePinball.mode()
	_flippers_rule(negated).conditions[0].negate = true
	_expect(negated, "the rule on Flippers sets the flippers but holds no PinballSeated")


func test_a_phase_placing_the_machine_without_pinball_ticks_is_refused() -> void:
	var made := FixturePinball.mode()
	var lobby := made.find_phase(&"lobby")
	lobby.tick_systems.assign(
		lobby.tick_systems.filter(func(s: TickSystem) -> bool: return s is not PinballTicks)
	)
	_expect(made, "phase lobby places the pinball but lists no PinballTicks")


func test_a_phase_accepting_flippers_without_pinball_ticks_is_refused() -> void:
	var made := FixturePinball.mode()
	var countdown := made.find_phase(&"countdown")
	countdown.tick_systems.assign(
		countdown.tick_systems.filter(
			func(s: TickSystem) -> bool: return s is not PinballTicks and s is not StationTicks
		)
	)
	_expect(made, "phase countdown accepts Flippers but lists no PinballTicks")
	_expect(made, "row lobby -> countdown runs no EndPinball")


func test_a_row_out_of_the_machine_without_end_pinball_is_refused() -> void:
	var made := FixturePinball.mode()
	for row: Transition in made.transitions:
		row.actions.assign(
			row.actions.filter(func(a: RuleEffect) -> bool: return a is not EndPinball)
		)
	_expect(made, "runs no EndPinball: a pinball seat would outlast it")


func test_a_lobby_without_or_with_two_pinball_markers_names_pinball() -> void:
	var missing := FixturePinball.layouts()
	missing[FixtureBaseMode.LOBBY] = FixtureBaseMode.layouts()[FixtureBaseMode.LOBBY]
	_expect_layout(missing, "has 0 pinball marker(s)")
	var doubled := FixturePinball.layouts()
	doubled[FixtureBaseMode.LOBBY].add_marker(&"pinball", Vector3(5, 0, 5))
	_expect_layout(doubled, "has 2 pinball marker(s)")


func _machine_rule(made: GameMode) -> Rule:
	for kind: StationKind in Stations.kinds_in(made):
		if kind.id == &"pinball":
			return kind.actions[0]
	return null


func _use(made: GameMode) -> UsePinball:
	return _machine_rule(made).effects[0] as UsePinball


func _flippers_rule(made: GameMode) -> Rule:
	for rule: Rule in made.actions:
		if rule.trigger == Intents.FLIPPERS:
			return rule
	return null


func _expect(mode: GameMode, fragment: String) -> void:
	_expect_in(Array(ModeCheck.run(mode).errors), fragment)


func _expect_layout(layouts: Dictionary[String, LevelLayout], fragment: String) -> void:
	_expect_in(Array(LayoutCheck.run(FixturePinball.mode(), layouts)), fragment)


func _expect_in(errors: Array, fragment: String) -> void:
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)
