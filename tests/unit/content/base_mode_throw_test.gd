extends GdUnitTestSuite
## The base mode's Throw rule in `content/` (#646, 37f; the throwing ADR, TD1 (a), TD2 (a), TD6
## (a)): one mode rule for every item, HoldsItem then OverFloor then ThrowItem, no cost, with the
## provisional numbers (#302 comments 6085904317 and 6096074314): 5 m/s (the highest speed at
## which no throw rests on House's roof, 5.5 m/s, less one 0.5 m/s step;
## house_roof_throw_test.gd checks the roof at it), the project's physics gravity, a 0.15 m
## radius and a 3 s longest flight; Round takes Throw from the living. Loads `content/` on purpose
## (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_mode_has_one_throw_rule_for_every_item() -> void:
	var mode := load(BASE_MODE) as GameMode
	var rules: Array[Rule] = []
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			rules.append(rule)
	assert_array(rules).has_size(1)
	for kind: ItemKind in mode.item_kinds:
		for rule: Rule in kind.actions:
			assert_str(String(rule.trigger)).is_not_equal(String(Intents.THROW))
	var throw := rules[0]
	assert_array(throw.conditions).has_size(2)
	assert_object(throw.conditions[0]).is_instanceof(HoldsItem)
	assert_object(throw.conditions[1]).is_instanceof(OverFloor)
	assert_array(throw.effects).has_size(1)
	assert_object(throw.effects[0]).is_instanceof(ThrowItem)


func test_the_throw_s_provisional_numbers() -> void:
	var effect := _throw_item()
	assert_float(effect.speed_mps).is_equal(5.0)
	assert_float(effect.radius_m).is_equal(0.15)
	assert_float(effect.longest_flight_s).is_equal(3.0)
	assert_int(Ticks.from_seconds(effect.longest_flight_s)).is_equal(60)


func test_the_arc_s_gravity_is_the_project_s_physics_gravity() -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	assert_float(_throw_item().gravity_mps2).is_equal_approx(gravity, 0.0001)


func test_round_takes_throw_from_the_living_only() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase: PhaseSpec in mode.phases:
		var expected := AcceptSpec.From.LIVING if phase.id == &"round" else 0
		(
			assert_int(phase.senders_of(Intents.THROW))
			. override_failure_message(String(phase.id))
			. is_equal(expected)
		)


func _throw_item() -> ThrowItem:
	var mode := load(BASE_MODE) as GameMode
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			return rule.effects[0] as ThrowItem
	return null
