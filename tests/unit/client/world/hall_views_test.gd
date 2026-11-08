extends GdUnitTestSuite
## HallVisibility and PrintViews (#1489): a client draws one side of a map holding the dead's hall,
## and a print is a drone over the marker for its time.

var _level: Node3D
var _hall: Node3D
var _rest: Node3D
var _camera: Camera3D


func before_test() -> void:
	_level = Node3D.new()
	_hall = Node3D.new()
	_hall.add_to_group(HallVisibility.GROUP)
	_rest = Node3D.new()
	_camera = Camera3D.new()
	_level.add_child(_hall)
	_level.add_child(_rest)
	_level.add_child(_camera)
	add_child(_level)


func after_test() -> void:
	remove_child(_level)
	_level.free()


func test_the_living_see_the_map_and_never_the_hall() -> void:
	HallVisibility.new().sync(_level, false, _camera)
	assert_bool(_hall.visible).is_false()
	assert_bool(_rest.visible).is_true()
	assert_object(_camera.environment).is_null()


func test_the_dead_see_the_hall_lit_by_its_own_environment_and_not_the_map() -> void:
	HallVisibility.new().sync(_level, true, _camera)
	assert_bool(_hall.visible).is_true()
	assert_bool(_rest.visible).is_false()
	assert_object(_camera.environment).is_same(HallVisibility.HALL_ENVIRONMENT)


func test_the_return_brings_back_the_map_and_what_was_hidden_before_stays_hidden() -> void:
	var toggled := Node3D.new()
	toggled.visible = false
	_level.add_child(toggled)
	var sides := HallVisibility.new()
	sides.sync(_level, true, _camera)
	sides.sync(_level, false, _camera)
	assert_bool(_rest.visible).is_true()
	assert_bool(toggled.visible).is_false()
	assert_bool(_hall.visible).is_false()
	assert_object(_camera.environment).is_null()


func test_a_print_stands_a_drone_over_the_marker_until_respawned() -> void:
	var prints: PrintViews = auto_free(PrintViews.new())
	add_child(prints)
	var at := Vector3(2, 0, 4)
	prints.on_event(&"PrintStarted", {"peer": 3, "position": at, "print_ms": 2000})
	assert_int(prints.count()).is_equal(1)
	var drone := prints.get_child(0) as MeshInstance3D
	assert_vector(drone.position).is_equal(at + Vector3.UP * PrintViews.DRONE_HEIGHT_M)
	prints.on_event(&"Respawned", {"peer": 3, "position": at})
	assert_int(prints.count()).is_equal(0)
	await get_tree().process_frame
	remove_child(prints)
