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


func test_a_print_ends_when_the_printed_player_leaves() -> void:
	var prints := _printing(3)
	prints.on_event(&"PlayerLeft", {"peer": 3})
	assert_int(prints.count()).is_equal(0)
	remove_child(prints)


## A match ending during a print sends no Respawned (End has no LifeTicks).
func test_a_change_of_phase_ends_every_print() -> void:
	var prints := _printing(3)
	prints.on_event(&"PhaseChanged", {"phase": &"end", "end_tick": -1})
	assert_int(prints.count()).is_equal(0)
	remove_child(prints)


func test_a_print_ends_when_its_time_runs_out_with_no_respawned() -> void:
	var prints := _printing(3)
	prints._process(2.1)
	assert_int(prints.count()).is_equal(0)
	remove_child(prints)


## A print grows the looks alone: the body and its collider stay whole, so the shape queries that
## find it never meet a non-uniformly scaled shape (the 4.7.2 API's own warning).
func test_a_print_grows_the_looks_and_leaves_the_collider_whole() -> void:
	var body: RemotePlayerBody = auto_free(AvatarViews.BODY.instantiate())
	body.rules = (load("res://content/modes/base_mode.tres") as GameMode).player_rules
	add_child(body)
	var mesh := body.get_node("Mesh") as MeshInstance3D
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var whole_y := mesh.transform.origin.y
	body.set_print_height(0.5)
	assert_float(mesh.transform.basis.get_scale().y).is_equal_approx(0.5, 1e-4)
	assert_float(mesh.transform.origin.y).is_equal_approx(whole_y * 0.5, 1e-4)
	assert_vector(shape.global_basis.get_scale()).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-4)
	assert_vector(body.scale).is_equal(Vector3.ONE)
	body.set_print_height(1.0)
	assert_float(mesh.transform.basis.get_scale().y).is_equal_approx(1.0, 1e-4)


func _printing(peer: int) -> PrintViews:
	var prints: PrintViews = auto_free(PrintViews.new())
	add_child(prints)
	prints.on_event(&"PrintStarted", {"peer": peer, "position": Vector3.ZERO, "print_ms": 2000})
	assert_int(prints.count()).is_equal(1)
	return prints
