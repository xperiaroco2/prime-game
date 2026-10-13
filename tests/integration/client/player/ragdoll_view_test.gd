extends GdUnitTestSuite
## RagdollView (the knockdown ADR's KE7, ARCHITECTURE §4.7.9) over a floor on the world layer: on
## the downed layer with the world mask only; started standing with no velocity it tips over and
## comes to rest lying over the host's point; its centre stays within the snap distance of the
## lying centre every step while the point moves, and moves there in one step when the point jumps
## farther; the sight point is the host's, never the pose; a dead one is grey, on no layer, held.

const FRAME_S := 1.0 / 60.0

var _rules: PlayerRules
var _floor: StaticBody3D
var _ragdoll: RagdollView


func before_test() -> void:
	_rules = FixtureModes.player_rules()
	_floor = StaticBody3D.new()
	_floor.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_floor.add_child(shape)
	add_child(_floor)
	_ragdoll = RagdollView.new()
	_ragdoll.setup(_rules, 7, BodyColours.of(3))


func after_test() -> void:
	_ragdoll.free()
	_floor.free()


func test_it_is_on_the_downed_layer_with_the_world_mask_only_and_never_sleeps() -> void:
	add_child(_ragdoll)
	assert_int(_ragdoll.collision_layer).is_equal(PhysicsLayers.DOWNED)
	assert_int(_ragdoll.collision_mask).is_equal(PhysicsLayers.WORLD)
	assert_bool(_ragdoll.can_sleep).is_false()
	assert_bool(_ragdoll.top_level).is_true()
	assert_int(_ragdoll.peer).is_equal(7)
	assert_object(_ragdoll.colour()).is_equal(BodyColours.of(3))
	# The render checklist's item 5: every material is depth-tested.
	var mesh := _ragdoll.get_node(^"Mesh") as MeshInstance3D
	var material := (mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	assert_bool(material.no_depth_test).is_false()


func test_started_standing_with_no_velocity_it_tips_over_and_rests_lying_on_the_point() -> void:
	var point := Vector3(2.0, 0.0, -1.0)
	_ragdoll.start(point, 0.3, Vector3.ZERO)
	add_child(_ragdoll)
	assert_float(_ragdoll.global_position.y).is_equal_approx(_rules.capsule_height_m * 0.5, 1e-4)
	for i: int in 120:
		await get_tree().physics_frame
		_assert_within_snap(0.0)
	# Lying: the capsule's axis is within 10 degrees of the floor, its centre over the point.
	var axis := _ragdoll.global_basis.y.normalized()
	assert_float(absf(axis.dot(Vector3.UP))).is_less(sin(deg_to_rad(10.0)))
	assert_vector(_ragdoll.global_position).is_equal_approx(
		_ragdoll.lying_centre(), Vector3.ONE * 0.1
	)
	assert_float(_ragdoll.linear_velocity.length()).is_less(0.2)


func test_it_follows_a_moving_point_within_the_snap_distance_every_step() -> void:
	var point := Vector3.ZERO
	var velocity := Vector3(3.0, 2.0, -1.0)
	_ragdoll.start(point, 0.0, velocity)
	add_child(_ragdoll)
	for i: int in 90:
		point += velocity * FRAME_S
		_ragdoll.hold(point, velocity)
		await get_tree().physics_frame
		# The point moved once more before the step that followed this check.
		_assert_within_snap(velocity.length() * FRAME_S)
	assert_float(_ragdoll.global_position.distance_to(_ragdoll.lying_centre())).is_less(0.5)


func test_a_point_farther_than_the_snap_distance_moves_the_centre_there_in_one_step() -> void:
	_ragdoll.lie_at_rest(Vector3.ZERO, 0.0)
	add_child(_ragdoll)
	for i: int in 10:
		await get_tree().physics_frame
	var basis := _ragdoll.global_basis
	_ragdoll.hold(Vector3(6.0, 0.0, 4.0), Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_vector(_ragdoll.global_position).is_equal_approx(
		Vector3(6.0, _rules.capsule_radius_m, 4.0), Vector3.ONE * 0.05
	)
	# The snap keeps the turn.
	assert_float(_ragdoll.global_basis.y.dot(basis.y)).is_greater(0.99)


func test_its_sight_point_is_the_hosts_point_never_its_pose() -> void:
	_ragdoll.start(Vector3(1.0, 0.0, 1.0), 0.0, Vector3.ZERO)
	add_child(_ragdoll)
	await get_tree().physics_frame
	var lifted := Vector3(1.0, _rules.capsule_radius_m, 1.0)
	assert_vector(_ragdoll.sight_point()).is_equal_approx(lifted, Vector3.ONE * 1e-5)
	assert_vector(_ragdoll.held_point()).is_equal(Vector3(1.0, 0.0, 1.0))


func test_lying_at_rest_lies_along_the_yaws_forward_axis() -> void:
	_ragdoll.lie_at_rest(Vector3(0.0, 0.0, 3.0), PI * 0.5)
	add_child(_ragdoll)
	var axis := _ragdoll.global_basis.y
	# Yaw a quarter turn: forward is -X.
	assert_float(absf(axis.dot(Vector3.RIGHT))).is_equal_approx(1.0, 1e-4)
	assert_vector(_ragdoll.global_position).is_equal_approx(
		Vector3(0.0, _rules.capsule_radius_m, 3.0), Vector3.ONE * 1e-4
	)
	for i: int in 30:
		await get_tree().physics_frame
	assert_vector(_ragdoll.global_position).is_equal_approx(
		Vector3(0.0, _rules.capsule_radius_m, 3.0), Vector3.ONE * 0.02
	)


func test_a_dead_one_is_grey_on_no_layer_and_held_still_at_the_body() -> void:
	_ragdoll.start(Vector3.ZERO, 0.0, Vector3(2.0, 0.0, 0.0))
	add_child(_ragdoll)
	await get_tree().physics_frame
	_ragdoll.make_dead(Vector3(0.5, 0.0, 0.0))
	assert_bool(_ragdoll.is_dead()).is_true()
	assert_int(_ragdoll.collision_layer).is_equal(0)
	assert_int(_ragdoll.collision_mask).is_equal(PhysicsLayers.WORLD)
	assert_object(_ragdoll.colour()).is_equal(LifeLooks.BODY_COLOUR)
	_ragdoll.set_colour(BodyColours.of(5))
	assert_object(_ragdoll.colour()).is_equal(LifeLooks.BODY_COLOUR)
	for i: int in 120:
		await get_tree().physics_frame
	assert_vector(_ragdoll.held_point()).is_equal(Vector3(0.5, 0.0, 0.0))
	assert_vector(_ragdoll.global_position).is_equal_approx(
		_ragdoll.lying_centre(), Vector3.ONE * 0.1
	)


## The centre is within the snap distance (plus `slack`) of the lying centre over the point.
func _assert_within_snap(slack: float) -> void:
	var off := _ragdoll.global_position.distance_to(_ragdoll.lying_centre())
	assert_float(off).is_less_equal(RagdollView.SNAP_M + slack + 1e-3)
