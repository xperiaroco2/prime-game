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
	var spots := HouseThrows.spots(_world, _rules.eye_height_m)
	for area: String in spots:
		(
			assert_int((spots[area] as Array).size())
			. override_failure_message("no spot found in %s" % area)
			. is_greater(0)
		)


func test_no_throw_at_the_base_mode_s_numbers_rests_on_the_roof() -> void:
	var spots := HouseThrows.spots(_world, _rules.eye_height_m)
	for area: String in spots:
		for feet: Vector3 in spots[area]:
			var found := _roof_rests(feet, _throw.speed_mps)
			var first := "none"
			if not found.is_empty():
				first = str(found[0])
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
	for feet: Vector3 in HouseThrows.spots(_world, _rules.eye_height_m)["balcony"]:
		found += _roof_rests(feet, FAST_MPS).size()
	assert_int(found).is_greater(0)


func test_each_column_gives_every_floor_in_it_and_the_railing_tops() -> void:
	# The railing tops decide the speed: they are found by the column, not coded by hand, so a
	# railing raised later is swept at its new height (#646 review).
	var spots := HouseThrows.spots(_world, _rules.eye_height_m)
	var railing_top := -INF
	for feet: Vector3 in spots["balcony_railing"]:
		railing_top = maxf(railing_top, feet.y)
	assert_float(railing_top).is_equal_approx(4.2, 0.05)
	var heights: Array[float] = []
	for feet: Vector3 in spots["balcony"]:
		if is_equal_approx(feet.x, 35.5) and is_equal_approx(feet.z, 22.5):
			heights.append(snappedf(feet.y, 0.1))
	assert_array(heights).contains_exactly([3.2, 0.0])


func test_a_crate_on_the_balcony_is_thrown_from_its_top() -> void:
	# The regression the roof test guards: a perch added beside the roof is swept from its own
	# height (a ray from the old nominal height started inside it and skipped it, #646 review).
	var crate_world := _house_with_box(Vector3(35.5, 3.2, 22.5), 1.0)
	var heights: Array[float] = []
	for feet: Vector3 in HouseThrows.spots(crate_world, _rules.eye_height_m)["balcony"]:
		if is_equal_approx(feet.x, 35.5) and is_equal_approx(feet.z, 22.5):
			heights.append(snappedf(feet.y, 0.1))
	assert_array(heights).contains_exactly([4.2, 0.0])


func test_a_perch_high_beside_the_roof_turns_the_roof_check_red() -> void:
	# A 2.5 m block on the balcony, by the roof's eave, puts a thrower's eye above the roof: the
	# sweep at the rule's own speed must find throws resting on it, or the roof test could never
	# fail.
	var perch_world := _house_with_box(Vector3(35.5, 3.2, 22.5), 2.5)
	var found := 0
	for feet: Vector3 in HouseThrows.spots(perch_world, _rules.eye_height_m)["balcony"]:
		found += (
			HouseThrows
			. roof_rests(
				perch_world,
				feet,
				_rules.eye_height_m,
				_throw.speed_mps,
				_throw.gravity_mps2,
				_throw.radius_m,
				maxi(1, Ticks.from_seconds(_throw.longest_flight_s))
			)
			. size()
		)
	assert_int(found).is_greater(0)


func test_a_rest_in_the_attic_is_not_on_the_roof_but_one_on_its_top_is() -> void:
	assert_bool(HouseThrows.on_roof(Vector3(30, 6.4, 33))).is_false()
	assert_bool(HouseThrows.on_roof(Vector3(30, 8.8, 33))).is_true()
	assert_bool(HouseThrows.on_roof(Vector3(18.5, 6.4, 33))).is_true()
	assert_bool(HouseThrows.on_roof(Vector3(35, 3.2, 22))).is_false()


# House's host world with a 1 m by 1 m block of `height` standing on the floor at `base` (centre
# of its bottom face).
func _house_with_box(base: Vector3, height: float) -> HostWorldQuery:
	var root := (load(HouseThrows.MAP) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, height, 1.0)
	shape.shape = box
	body.add_child(shape)
	body.position = base + Vector3.UP * (height / 2.0)
	root.add_child(body)
	var level := LevelWorld.from_scene(root, HouseThrows.MAP)
	root.free()
	var world := HostWorldQuery.new(_rules.capsule_radius_m)
	world.add_level(level)
	world.use_level(HouseThrows.MAP)
	return world


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
