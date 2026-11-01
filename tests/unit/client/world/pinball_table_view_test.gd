extends GdUnitTestSuite
## The pinball's table as the client draws it (#1400, ARCHITECTURE §4.7.63): a mesh per collision
## shape of the host's table scene and no physics body anywhere in the drawn tree; the flippers
## turn toward the held state at the host's speed up to its swing, each its own way; the ball shows
## where it is put; the look numbers are the host's spec's.

var _table: PinballTableView


func before_test() -> void:
	_table = auto_free(PinballTableView.new())
	assert_bool(_table.build()).is_true()


func test_the_drawn_table_holds_no_physics_body() -> void:
	assert_array(_table.find_children("*", "CollisionObject3D", true, false)).is_empty()
	assert_array(_table.find_children("*", "CollisionShape3D", true, false)).is_empty()


func test_every_shape_of_the_scene_is_a_mesh_and_each_flipper_a_pivot() -> void:
	var source := (load(PinballTableView.SCENE) as PackedScene).instantiate()
	var shapes := source.find_children("*", "CollisionShape3D", true, false).size()
	source.free()
	var meshes := _table.find_children("*", "MeshInstance3D", true, false).size()
	# One per shape, the playfield and the ball.
	assert_int(meshes).is_equal(shapes + 2)
	for flipper: StringName in PinballTableView.FLIPPERS:
		var pivot := _table.get_node(NodePath(flipper)) as Node3D
		assert_object(pivot).is_not_null()
		assert_object(pivot.get_node(^"Mesh")).is_instanceof(MeshInstance3D)


func test_a_held_flipper_turns_at_the_host_s_speed_up_to_its_swing() -> void:
	_table.left = true
	_table.step(0.01)
	var turned := deg_to_rad(PinballTableView.SPEED_DEG_S * 0.01)
	assert_float(_table.flipper_angle(0)).is_equal_approx(turned, 1e-5)
	assert_float(_table.flipper_angle(1)).is_zero()
	_table.step(1.0)
	assert_float(_table.flipper_angle(0)).is_equal_approx(
		deg_to_rad(PinballTableView.SWING_DEG), 1e-5
	)
	_table.left = false
	_table.step(1.0)
	assert_float(_table.flipper_angle(0)).is_zero()


func test_the_flippers_turn_the_host_s_ways() -> void:
	var source := (load(PinballTableView.SCENE) as PackedScene).instantiate()
	var rest_left := (source.get_node(^"FlipperLeft") as Node3D).transform
	var rest_right := (source.get_node(^"FlipperRight") as Node3D).transform
	source.free()
	_table.left = true
	_table.right = true
	_table.step(1.0)
	var swing := deg_to_rad(PinballTableView.SWING_DEG)
	var left := (_table.get_node(^"FlipperLeft") as Node3D).transform
	var right := (_table.get_node(^"FlipperRight") as Node3D).transform
	var want_left := rest_left * Transform3D(Basis(Vector3.UP, swing))
	var want_right := rest_right * Transform3D(Basis(Vector3.UP, -swing))
	assert_bool(left.is_equal_approx(want_left)).is_true()
	assert_bool(right.is_equal_approx(want_right)).is_true()
	_table.rest()
	assert_bool((_table.get_node(^"FlipperLeft") as Node3D).transform.is_equal_approx(rest_left))
	assert_bool(_table.ball.visible).is_false()


func test_the_ball_shows_where_it_is_put_and_hides_for_none() -> void:
	assert_bool(_table.ball.visible).is_false()
	_table.show_ball(Vector3(0.1, 0.03, -0.2))
	assert_bool(_table.ball.visible).is_true()
	assert_vector(_table.ball.position).is_equal(Vector3(0.1, 0.03, -0.2))
	_table.show_ball(null)
	assert_bool(_table.ball.visible).is_false()


func test_the_look_numbers_are_the_host_s_spec() -> void:
	# The client may not name server/ (E18); the test may: a retune of the spec fails here.
	var spec := load("res://levels/pinball/pinball_table_spec.tres") as PinballTableSpec
	assert_float(PinballTableView.SWING_DEG).is_equal(spec.flipper_swing_deg)
	assert_float(PinballTableView.SPEED_DEG_S).is_equal(spec.flipper_speed_deg_s)
	assert_float(PinballTableView.BALL_RADIUS_M).is_equal(spec.ball_radius_m)


func test_the_table_scene_is_the_host_s() -> void:
	assert_str(PinballTableView.SCENE).is_equal(PinballTable.SCENE)
