extends GdUnitTestSuite
## PuppetBodies (#1397, ARCHITECTURE §4.7.62): a record row's still body, coloured as the caller
## says (a booth frame: the row's colour at the flash), laid flat when downed or limp, sneaking as
## recorded, out of the live physics, in its parent's world.

var _rules: PlayerRules


func before_test() -> void:
	_rules = FixtureBaseMode.mode().player_rules


func _row(extra: Dictionary = {}) -> Dictionary:
	var row := {
		"peer": 7,
		"colour": 3,
		"position": Vector3(1, 0, 2),
		"facing": Vector3.FORWARD,
		"crouched": false,
		"sneaking": false,
		"posed": false,
		"limp": false,
	}
	row.merge(extra, true)
	return row


func _parent() -> Node3D:
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	return parent


func test_the_puppet_takes_the_colour_it_is_given_and_no_collision() -> void:
	var body := PuppetBodies.make(_row(), _parent(), _rules, null, Color.ORANGE)
	assert_that(body.color).is_equal(Color.ORANGE)
	assert_int(body.collision_layer).is_zero()
	assert_int(body.collision_mask).is_zero()
	assert_str(String(body.name)).is_equal("Puppet7")


func test_a_standing_row_stands_at_its_position() -> void:
	var body := PuppetBodies.make(_row(), _parent(), _rules, null, Color.WHITE)
	assert_vector(body.global_position).is_equal_approx(Vector3(1, 0, 2), Vector3.ONE * 0.001)
	assert_float(body.global_transform.basis.y.dot(Vector3.UP)).is_greater(0.99)


func test_a_limp_row_lies_flat() -> void:
	var body := PuppetBodies.make(_row({"limp": true}), _parent(), _rules, null, Color.WHITE)
	assert_float(absf(body.global_transform.basis.y.dot(Vector3.UP))).is_less(0.01)
	assert_bool(PuppetBodies.lies(_row({"limp": true}))).is_true()
	assert_bool(PuppetBodies.lies(_row({"downed": true}))).is_true()
	assert_bool(PuppetBodies.lies(_row())).is_false()


func test_the_sneak_flag_is_kept() -> void:
	var body := PuppetBodies.make(_row({"sneaking": true}), _parent(), _rules, null, Color.WHITE)
	assert_bool(body.is_sneaking()).is_true()


func test_the_puppet_is_drawn_in_its_parents_world() -> void:
	var viewport: SubViewport = auto_free(SubViewport.new())
	viewport.own_world_3d = true
	add_child(viewport)
	var body := PuppetBodies.make(_row(), viewport, _rules, null, Color.WHITE)
	assert_object(body.get_world_3d()).is_same(viewport.find_world_3d())
	assert_object(body.get_world_3d()).is_not_same(get_viewport().find_world_3d())
