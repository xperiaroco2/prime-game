extends GdUnitTestSuite
## No throw at the base mode's numbers puts an item on an estate roof (EstateThrows.TOPS) where no
## player can reach it (#1374; the throwing ADR, TD5 (a), as House's house_roof_throw_test.gd,
## #646): the flat tops no player stands on (the outbuildings' roofs, the gazebo's, the ship's, the
## fallen trunk's) are out of reach, so the throw is kept too weak to reach them and no "no rest"
## volume guards them. Every other flat top: estate_tops_reach_test.gd. Read
## in the host's collision world of the level with the Throw rule's own ThrowItem numbers and the
## mode's PlayerRules: a later change of the speed, the gravity, the radius, the eye height or the
## level that lets a throw rest on a top turns this red. The tops, spots and fan: estate_throws.gd.

const EstateThrows := preload("res://tests/integration/levels/estate_throws.gd")
const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
## A throw this fast from beside a roof rests on it, so the check below is not blind.
const FAST_MPS := 9.0
## A block this high beside the pantry's north wall puts a thrower's eye over its roof's edge.
const PERCH_M := 1.0

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
	_world.add_level(LevelWorld.build(EstateDoc.MAP))
	_world.use_level(EstateDoc.MAP)


func after() -> void:
	_world = null
	_rules = null
	_throw = null


func test_the_level_builds_and_the_base_mode_throws_on_it() -> void:
	assert_array(Array(_world.errors)).is_empty()
	assert_object(_throw).is_not_null()
	assert_bool((load(BASE_MODE) as GameMode).maps.has(EstateDoc.MAP)).is_true()


func test_every_top_is_found_above_reach_and_has_standable_spots() -> void:
	# A moved or lowered piece would leave a top unswept.
	var tops := EstateThrows.tops(_world)
	assert_array(tops.keys()).contains_exactly_in_any_order(EstateThrows.TOPS)
	var spots := EstateThrows.spots(_world, _rules.eye_height_m)
	for top_name: String in tops:
		(
			assert_float(tops[top_name]["y"] as float)
			. override_failure_message("%s's top is at %s m" % [top_name, tops[top_name]["y"]])
			. is_greater(2.0)
		)
		(
			assert_int((spots[top_name] as Array).size())
			. override_failure_message("no spot found by %s" % top_name)
			. is_greater(0)
		)


func test_no_throw_at_the_base_mode_s_numbers_rests_on_a_top() -> void:
	var tops := EstateThrows.tops(_world)
	var spots := EstateThrows.spots(_world, _rules.eye_height_m)
	for top_name: String in spots:
		for feet: Vector3 in spots[top_name]:
			var found := _top_rests(_world, tops, feet, _throw.speed_mps)
			var first := "none"
			if not found.is_empty():
				first = "%s on %s" % [found[0], EstateThrows.on_a_top(tops, found[0])]
			(
				assert_int(found.size())
				. override_failure_message(
					(
						"by %s: %d throws at %s m/s from %s rest on a top, the first at %s"
						% [top_name, found.size(), _throw.speed_mps, feet, first]
					)
				)
				. is_equal(0)
			)


func test_a_faster_throw_from_beside_the_pantry_rests_on_its_roof() -> void:
	var tops := EstateThrows.tops(_world)
	var found := 0
	for feet: Vector3 in EstateThrows.spots(_world, _rules.eye_height_m)["Pantry"]:
		found += _top_rests(_world, tops, feet, FAST_MPS).size()
	assert_int(found).is_greater(0)


func test_a_perch_beside_the_pantry_turns_the_top_check_red() -> void:
	# A block PERCH_M high by the pantry's north wall (the pantry is 8 x 6 at 48, 27): thrown from
	# its top at the rule's own speed, the roof is reached, or the check could never fail. The block
	# is found as a spot of its column, so a perch a level change adds there is swept too.
	var base := Vector3(47.5, 0.0, 23.5)
	var perch_world := _estate_with_box(base, PERCH_M)
	var tops := EstateThrows.tops(perch_world)
	var heights: Array[float] = []
	var found := 0
	for feet: Vector3 in EstateThrows.spots(perch_world, _rules.eye_height_m)["Pantry"]:
		if is_equal_approx(feet.y, PERCH_M):
			heights.append(feet.y)
			found += _top_rests(perch_world, tops, feet, _throw.speed_mps).size()
	assert_array(heights).is_not_empty()
	assert_int(found).is_greater(0)


func test_a_rest_on_a_roof_is_on_its_top_and_one_under_it_is_not() -> void:
	var tops := EstateThrows.tops(_world)
	var pantry_y: float = tops["Pantry"]["y"]
	assert_str(EstateThrows.on_a_top(tops, Vector3(48, pantry_y, 27))).is_equal("Pantry")
	assert_str(EstateThrows.on_a_top(tops, Vector3(48, 0.0, 27))).is_equal("")
	assert_str(EstateThrows.on_a_top(tops, Vector3(65.3, 0.0, 41))).is_equal("")


# The estate's host world with a 1 m by 1 m block of `height` standing on the floor at `base`
# (centre of its bottom face).
func _estate_with_box(base: Vector3, height: float) -> HostWorldQuery:
	var root := (load(EstateDoc.MAP) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, height, 1.0)
	shape.shape = box
	body.add_child(shape)
	body.position = base + Vector3.UP * (height / 2.0)
	root.add_child(body)
	var level := LevelWorld.from_scene(root, EstateDoc.MAP)
	root.free()
	var world := HostWorldQuery.new(_rules.capsule_radius_m)
	world.add_level(level)
	world.use_level(EstateDoc.MAP)
	return world


func _top_rests(
	world: HostWorldQuery, tops: Dictionary[String, Dictionary], feet: Vector3, speed: float
) -> Array[Vector3]:
	return EstateThrows.top_rests(
		world,
		tops,
		feet,
		_rules.eye_height_m,
		speed,
		_throw.gravity_mps2,
		_throw.radius_m,
		maxi(1, Ticks.from_seconds(_throw.longest_flight_s))
	)
