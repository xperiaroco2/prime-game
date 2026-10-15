extends GdUnitTestSuite
## TargetChoice over stations (client/world/target_choice.gd; #801, ARCHITECTURE §4.7.54), pure: a
## station StationUse offers is named only where the ray meets its device (the level's ray hit
## its scene at `blocked_at`) or its use spot, while the feet stand in its cylinder less the hint's
## margin; the nearest along the ray wins, an item on a tie. The Generator fixture: the generator's
## floor point at (0, 0, 20), radius 1 m, height 2 m.
## Against a physics fixture world: item_interactions_station_test.gd (integration/client/world).

const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")
## The feet half a metre in front of the generator's floor point, facing +Z towards its device.
const FEET := Vector3(0, 0, 19.5)
const EYE := Vector3(0, 1.6, 19.5)
## Where the device's face stands across the ray, in z.
const FACE_Z := 21.0
const NO_DEVICE := -1

var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_mode = FixtureGeneratorModes.basic()
	_model = G.dealt(FixtureGeneratorModes.SWITCHES, _mode)


func test_the_device_the_ray_hits_names_its_station() -> void:
	var look := Vector3(0, -0.3, 1).normalized()
	var face_at := (FACE_Z - EYE.z) / look.z
	var target := _choose(look, face_at, FEET, 0.0, G.GENERATOR)
	assert_bool(target.is_station()).is_true()
	assert_int(target.id).is_equal(G.GENERATOR)
	assert_float(target.t).is_equal_approx(face_at, 1e-5)
	# The same ray with the level's hit on no station's scene names nothing.
	assert_int(_choose(look, face_at, FEET, 0.0, NO_DEVICE).kind).is_equal(
		TargetChoice.Target.Kind.NONE
	)


func test_the_use_spot_names_its_station_where_no_scene_stands() -> void:
	var spot := TargetChoice.aim_point(_model.stations[G.GENERATOR])
	var look := (spot - EYE).normalized()
	var target := _choose(look, TargetChoice.RAY_M, FEET, 0.0, NO_DEVICE)
	assert_bool(target.is_station()).is_true()
	assert_int(target.id).is_equal(G.GENERATOR)
	# A wall nearer than the sphere hides it.
	var wall_at := EYE.distance_to(spot) - TargetChoice.STATION_AIM_RADIUS_M - 0.1
	assert_bool(_choose(look, wall_at, FEET, 0.0, NO_DEVICE).is_station()).is_false()


func test_an_item_inside_the_cylinder_in_front_of_the_device_wins_and_one_behind_it_never() -> void:
	# A knife 0.85 m from the floor point, inside the 1 m cylinder, in front of the device's face
	# and aside of the use spot's sphere, which the ray would meet first.
	var in_front := Vector3(0.8, 0, 20.3)
	_spawn(30, in_front)
	var look := (ItemView.centre_of(&"knife", in_front) - EYE).normalized()
	var face_at := (FACE_Z - EYE.z) / look.z
	var target := _choose(look, face_at, FEET, 5.0, G.GENERATOR)
	assert_bool(target.is_item()).override_failure_message("the nearer item").is_true()
	assert_int(target.id).is_equal(30)
	# The same item behind the device's face: the ray meets the device first, the station wins.
	_model.items.clear()
	var behind := Vector3(0, 0, 21.3)
	_spawn(31, behind)
	look = (ItemView.centre_of(&"knife", behind) - EYE).normalized()
	face_at = (FACE_Z - EYE.z) / look.z
	(
		assert_float(TargetChoice.enters_at(EYE, look, ItemView.centre_of(&"knife", behind), 0.3))
		. is_greater(face_at)
	)
	target = _choose(look, face_at, FEET, 5.0, G.GENERATOR)
	assert_bool(target.is_station()).override_failure_message("the device in front").is_true()
	assert_int(target.id).is_equal(G.GENERATOR)


func test_the_feet_must_stand_in_the_cylinder_less_the_hints_margin() -> void:
	var look := Vector3(0, -0.3, 1).normalized()
	var reach := TargetChoice.hint_reach(FixtureGeneratorModes.RADIUS_M, _mode)
	assert_float(reach).is_less(FixtureGeneratorModes.RADIUS_M)
	var inside := Vector3(0, 0, 20.0 - reach + 0.01)
	assert_bool(_choose_from(inside, look, G.GENERATOR).is_station()).is_true()
	# Inside the host's radius, but within the hint's margin of its edge: no hint.
	var margin := Vector3(0, 0, 20.0 - reach - 0.05)
	assert_bool(_choose_from(margin, look, G.GENERATOR).is_station()).is_false()
	# Above the cylinder's height, or below its floor: no hint.
	var above := Vector3(0, FixtureGeneratorModes.HEIGHT_M + 0.1, 19.8)
	assert_bool(_choose_from(above, look, G.GENERATOR).is_station()).is_false()
	var below := Vector3(0, -0.1, 19.8)
	assert_bool(_choose_from(below, look, G.GENERATOR).is_station()).is_false()


func test_a_charged_generator_and_its_switches_are_never_named() -> void:
	var look := Vector3(0, -0.3, 1).normalized()
	var face_at := (FACE_Z - EYE.z) / look.z
	G.charge(_model, FixtureGeneratorModes.NEEDED, false, 40)
	assert_bool(_choose(look, face_at, FEET, 0.0, G.GENERATOR).is_station()).is_false()
	var switch_feet := FixtureGeneratorModes.SWITCH_SPOTS[0] + Vector3(0, 0, -0.5)
	var switch_eye := switch_feet + Vector3.UP * 1.6
	var target := TargetChoice.choose_target(
		_model, _mode, switch_eye, look, 1.0, switch_feet, 0.0, G.FIRST_SWITCH
	)
	assert_bool(target.is_station()).is_false()


func _choose(
	look: Vector3, blocked_at: float, feet: Vector3, item_reach: float, device: int
) -> TargetChoice.Target:
	return TargetChoice.choose_target(
		_model, _mode, EYE, look, blocked_at, feet, item_reach, device
	)


## The device hit 1 m along the ray from the eye above `feet`.
func _choose_from(feet: Vector3, look: Vector3, device: int) -> TargetChoice.Target:
	return TargetChoice.choose_target(
		_model, _mode, feet + Vector3.UP * 1.6, look, 1.0, feet, 0.0, device
	)


func _spawn(id: int, at: Vector3) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"knife", "position": at})
