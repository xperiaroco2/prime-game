extends GdUnitTestSuite
## The pinball's table as the client draws it (#1400, ARCHITECTURE §4.7.63): a mesh per collision
## shape of the host's table scene and no physics body anywhere in the drawn tree; the flippers
## turn toward the held state at the host's speed up to its swing, each its own way; the ball shows
## where it is put; the look numbers are the host's spec's; the art's meshes in place of the
## greybox's, the flippers' under their pivots (#1702).

var _table: PinballTableView


func before_test() -> void:
	_table = auto_free(PinballTableView.new())
	# The greybox contract, whether the LFS art is here or not; the art: its own test.
	_table.dress = false
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


## #1702: the art's table (one mesh per body it names, the Playfield) is drawn in place of the
## greybox's: each art mesh at its place in the table's frame, a flipper's under its pivot (so it
## turns with it), the greybox meshes of each named body freed, the others kept.
func test_the_art_s_meshes_replace_the_greybox_s() -> void:
	var table: PinballTableView = auto_free(PinballTableView.new())
	table.art = _art(
		{
			&"WallLeft": Vector3(-0.3, 0.02, 0.1),
			&"FlipperLeft": Vector3(-0.1, 0.01, 0.5),
			&"Playfield": Vector3(0, -0.005, 0),
		}
	)
	assert_bool(table.build()).is_true()
	assert_int(table.find_children("WallLeft*", "MeshInstance3D", false, false).size()).is_equal(1)
	var wall := table.get_node(^"WallLeft") as MeshInstance3D
	assert_object(wall.mesh as SphereMesh).is_not_null()
	assert_vector(wall.position).is_equal_approx(Vector3(-0.3, 0.02, 0.1), Vector3.ONE * 1e-5)
	var pivot := table.get_node(NodePath(&"FlipperLeft")) as Node3D
	var flipper := pivot.get_node(^"FlipperLeft") as MeshInstance3D
	assert_object(flipper).is_not_null()
	assert_object(pivot.get_node_or_null(^"Mesh")).is_null()
	assert_vector((pivot.transform * flipper.transform).origin).is_equal_approx(
		Vector3(-0.1, 0.01, 0.5), Vector3.ONE * 1e-5
	)
	assert_object((table.get_node(^"Playfield") as MeshInstance3D).mesh as SphereMesh).is_not_null()
	# A body the art does not name keeps its greybox mesh.
	assert_object(table.get_node_or_null(^"WallRight")).is_not_null()
	# A collider under an art mesh (an import suffix) never comes into the drawn tree.
	assert_array(table.find_children("*", "CollisionObject3D", true, false)).is_empty()
	# The art flipper turns with its pivot.
	var before := (pivot.transform * flipper.transform).basis
	table.left = true
	table.step(1.0)
	assert_bool((pivot.transform * flipper.transform).basis.is_equal_approx(before)).is_false()


## An art scene of a SphereMesh per name at its place (WallLeft's with a StaticBody3D under it, as
## an import suffix would make).
func _art(places: Dictionary[StringName, Vector3]) -> PackedScene:
	var root := Node3D.new()
	for part: StringName in places:
		var mesh := MeshInstance3D.new()
		mesh.name = part
		mesh.mesh = SphereMesh.new()
		mesh.position = places[part]
		root.add_child(mesh)
		mesh.owner = root
		if part == &"WallLeft":
			var body := StaticBody3D.new()
			body.name = "WallLeftCol"
			mesh.add_child(body)
			body.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene
