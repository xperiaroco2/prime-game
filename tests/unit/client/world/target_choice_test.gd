extends GdUnitTestSuite
## TargetChoice's pure parts (client/world/target_choice.gd; ARCHITECTURE §4.7, Interactions): the
## reach is the client's own mode's InReach of PickUp; the ray picks the nearest item on the ground
## it passes close to, short of the level; the reach is measured from the feet, as the host does.
## Against a physics fixture world: tests/integration/client/world/item_interactions_test.gd.

const MODE := "res://content/modes/base_mode.tres"
const EYE := Vector3(0, 1.6, 0)

var _model: ClientModel


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())


func test_the_reach_is_the_modes_in_reach_of_pick_up() -> void:
	assert_float(TargetChoice.reach_of(load(MODE) as GameMode)).is_equal(2.0)
	# A mode with no PickUp offers nothing.
	assert_float(TargetChoice.reach_of(FixtureBaseMode.mode())).is_equal(0.0)


func test_the_ray_enters_a_sphere_ahead_and_misses_one_behind_or_aside() -> void:
	var ahead := TargetChoice.enters_at(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -3), 0.5)
	assert_float(ahead).is_equal_approx(2.5, 1e-5)
	(
		assert_float(TargetChoice.enters_at(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 3), 0.5))
		. is_equal(-1.0)
	)
	(
		assert_float(TargetChoice.enters_at(Vector3.ZERO, Vector3.FORWARD, Vector3(1, 0, -3), 0.5))
		. is_equal(-1.0)
	)
	(
		assert_float(TargetChoice.enters_at(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 0.2), 0.5))
		. is_equal(0.0)
	)


func test_the_nearest_item_on_the_ground_wins_and_held_or_delivered_ones_never() -> void:
	_spawn(1, Vector3(0, 0, -3))
	_spawn(2, Vector3(0, 0, -2))
	var look := (ItemView.centre_of(&"knife", Vector3(0, 0, -2)) - EYE).normalized()
	assert_int(TargetChoice.along_ray(_model, EYE, look, TargetChoice.RAY_M)).is_equal(2)
	# Short of the level: a wall at 1 m hides it.
	assert_int(TargetChoice.along_ray(_model, EYE, look, 1.0)).is_equal(-1)
	_model.fold(&"ItemPickedUp", {"peer": 3, "item": 2})
	assert_int(TargetChoice.along_ray(_model, EYE, look, TargetChoice.RAY_M)).is_equal(-1)
	var package := {"item": 4, "kind": &"package", "position": Vector3(0, 0, -2)}
	package["station"] = 1
	package["colour"] = Color.RED
	_model.fold(&"ItemSpawned", package)
	_model.fold(&"PackageDelivered", {"item": 4, "station": 1})
	assert_int(TargetChoice.along_ray(_model, EYE, look, TargetChoice.RAY_M)).is_equal(-1)


func test_the_reach_counts_from_the_feet_not_along_the_ray() -> void:
	# A floor item 1.9 m away: 2.5 m from the eye, 1.9 m from the feet. The host accepts it.
	_spawn(1, Vector3(0, 0, -1.9))
	var look := (ItemView.centre_of(&"knife", Vector3(0, 0, -1.9)) - EYE).normalized()
	var feet := Vector3.ZERO
	assert_int(TargetChoice.choose(_model, EYE, look, TargetChoice.RAY_M, feet, 2.0)).is_equal(1)
	# The same item 2.1 m away is refused, however short the ray.
	_model.fold(&"ItemPlaced", {"item": 1, "position": Vector3(0, 0, -2.1), "cause": &"put_down"})
	look = (ItemView.centre_of(&"knife", Vector3(0, 0, -2.1)) - EYE).normalized()
	assert_int(TargetChoice.choose(_model, EYE, look, TargetChoice.RAY_M, feet, 2.0)).is_equal(-1)


func _spawn(id: int, at: Vector3) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"knife", "position": at})
