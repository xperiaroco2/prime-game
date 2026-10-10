extends GdUnitTestSuite
## No throw at the base mode's numbers puts an item on House's roof (#646; the throwing ADR, TD5;
## the engineer's rule, #302 comment 6096074314): the roof is walkable but its door may be locked,
## so the throw is kept too weak to reach it, and no "no rest" volume guards it. Read in the host's
## collision world of the level (LevelWorld, HostWorldQuery), with the Throw rule's own ThrowItem
## numbers and the mode's PlayerRules: a later change of the speed, the gravity, the radius, the
## eye height or the level that lets a throw rest on the roof turns this red. The spots and the
## fan: house_throws.gd.

const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
## A throw this fast from the balcony's floor rests on the roof (#646's sweep: 200 of its 19 440
## throws), so the check below is not blind.
const FAST_MPS := 7.5

var _world: HostWorldQuery
var _rules: PlayerRules
var _throw: ThrowItem


func before() -> void:
	var mode := load(BASE_MODE) as GameMode
	_rules = mode.player_rules
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			for effect: RuleEffect in rule.effects:
				if effect is ThrowItem:
					_throw = effect as ThrowItem
	_world = HostWorldQuery.new(_rules.capsule_radius_m)
	_world.add_level(LevelWorld.build(HouseThrows.MAP))
	_world.use_level(HouseThrows.MAP)


func after() -> void:
	_world = null
	_rules = null
	_throw = null


func test_the_level_builds_and_the_base_mode_throws_on_it() -> void:
	assert_array(Array(_world.errors)).is_empty()
	assert_object(_throw).is_not_null()
	var mode := load(BASE_MODE) as GameMode
	assert_bool(mode.maps.has(HouseThrows.MAP)).is_true()


func test_every_area_has_standable_spots() -> void:
	# A moved piece would leave an area without a floor, and its throws untested.
	var spots := HouseThrows.spots(_world)
	for area: String in spots:
		(
			assert_int((spots[area] as Array).size())
			. override_failure_message("no spot found in %s" % area)
			. is_greater(0)
		)


func test_no_throw_at_the_base_mode_s_numbers_rests_on_the_roof() -> void:
	var spots := HouseThrows.spots(_world)
	for area: String in spots:
		for feet: Vector3 in spots[area]:
			var found := _roof_rests(feet, _throw.speed_mps)
			var first: Variant = found[0] if not found.is_empty() else null
			(
				assert_int(found.size())
				. override_failure_message(
					(
						"%s: %d throws at %s m/s from %s rest on the roof, the first at %s"
						% [area, found.size(), _throw.speed_mps, feet, first]
					)
				)
				. is_equal(0)
			)


func test_a_faster_throw_from_the_balcony_rests_on_the_roof() -> void:
	var found := 0
	for feet: Vector3 in HouseThrows.spots(_world)["balcony"]:
		found += _roof_rests(feet, FAST_MPS).size()
	assert_int(found).is_greater(0)


func test_a_rest_in_the_attic_is_not_on_the_roof_but_one_on_its_top_is() -> void:
	assert_bool(HouseThrows.on_roof(Vector3(30, 6.4, 33))).is_false()
	assert_bool(HouseThrows.on_roof(Vector3(30, 8.8, 33))).is_true()
	assert_bool(HouseThrows.on_roof(Vector3(18.5, 6.4, 33))).is_true()
	assert_bool(HouseThrows.on_roof(Vector3(35, 3.2, 22))).is_false()


func _roof_rests(feet: Vector3, speed: float) -> Array[Vector3]:
	return HouseThrows.roof_rests(
		_world,
		feet,
		_rules.eye_height_m,
		speed,
		_throw.gravity_mps2,
		_throw.radius_m,
		maxi(1, Ticks.from_seconds(_throw.longest_flight_s))
	)
