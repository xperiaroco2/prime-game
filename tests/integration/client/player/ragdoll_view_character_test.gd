extends GdUnitTestSuite
## RagdollView with a character (#522, ARCHITECTURE §4.7.53), on character_fixture's in-memory rig
## and ragdoll (no LFS content): the anchor has no mesh, no shape and no layer; the rig's bodies are
## on the downed layer with the world mask and never sleep; started standing it falls and its
## pelvis comes to rest over the host's point, within the snap distance every step; a jump of the
## point moves it there in one step; off a ledge it comes down to the point, and a point lifted
## within the snap distance lifts it (the vertical term); a dead one is grey with
## every body on no layer; a ray's collider names its view; handed over to another parent (the
## death, BodyViews) it keeps simulating.

const Fixture := preload("res://tests/integration/client/player/character_fixture.gd")
const SETTLE_M := 0.15

var _rules: PlayerRules
var _set: CharacterSet
var _floor: StaticBody3D
var _ragdoll: RagdollView


func before() -> void:
	_set = CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll())


func before_test() -> void:
	_rules = FixtureModes.player_rules()
	_floor = _box(Vector3(60.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0))
	_ragdoll = RagdollView.new()
	_ragdoll.setup(_rules, 7, BodyColours.of(3), _set)


func after_test() -> void:
	if is_instance_valid(_ragdoll):
		_ragdoll.free()
	_floor.free()


func test_the_anchor_has_no_mesh_shape_or_layer_and_the_bones_are_downed() -> void:
	add_child(_ragdoll)
	assert_object(_ragdoll.rig()).is_not_null()
	assert_bool(_ragdoll.rig().top_level).is_true()
	assert_bool(_ragdoll.has_node(^"Mesh")).is_false()
	assert_bool(_ragdoll.has_node(^"Shape")).is_false()
	assert_int(_ragdoll.collision_layer).is_equal(0)
	assert_bool(_ragdoll.freeze).is_true()
	assert_bool(_ragdoll.visible).is_true()
	assert_int(_ragdoll.bones().size()).is_equal(4)
	assert_str(str(_ragdoll.pelvis().get(&"bone_name"))).is_equal("Body")
	for bone: PhysicalBone3D in _ragdoll.bones():
		assert_int(bone.collision_layer).is_equal(PhysicsLayers.DOWNED)
		assert_int(bone.collision_mask).is_equal(PhysicsLayers.WORLD)
		assert_bool(bone.can_sleep).is_false()
	assert_object(_ragdoll.colour()).is_equal(BodyColours.of(3))
	assert_object(_ragdoll.rig().tint()).is_equal(BodyColours.of(3))


func test_a_set_without_ragdoll_data_keeps_the_capsule() -> void:
	var plain := CharacterSet.from_scene(Fixture.scene(), {})
	var capsule := RagdollView.new()
	capsule.setup(_rules, 8, BodyColours.of(1), plain)
	assert_object(capsule.rig()).is_null()
	assert_bool(capsule.has_node(^"Mesh")).is_true()
	assert_int(capsule.collision_layer).is_equal(PhysicsLayers.DOWNED)
	capsule.free()


func test_started_standing_it_falls_and_its_pelvis_rests_over_the_point() -> void:
	var point := Vector3(2.0, 0.0, -1.0)
	_ragdoll.start(point, 0.3, Vector3.ZERO)
	add_child(_ragdoll)
	for i: int in 150:
		await get_tree().physics_frame
		_assert_within_snap(0.05)
	var sim := _ragdoll.rig().skeleton.get_node(^"Ragdoll") as PhysicalBoneSimulator3D
	assert_bool(sim.is_simulating_physics()).is_true()
	var joints := sim.find_children("*", "Joint3D", false, false)
	assert_int(joints.size()).is_equal(3)
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * SETTLE_M)
	# Lying, not sitting on its pelvis: the chest is as low as the pelvis (start() tips it over).
	var torso := _ragdoll.bones()[2].global_position
	assert_float(torso.y).is_less(_pelvis().y + 0.1)
	# The anchor follows the pelvis.
	assert_vector(_ragdoll.global_position).is_equal_approx(_pelvis(), Vector3.ONE * 0.05)


func test_a_point_farther_than_the_snap_distance_moves_the_pelvis_there_in_one_step() -> void:
	_ragdoll.lie_at_rest(Vector3.ZERO, 0.0)
	add_child(_ragdoll)
	for i: int in 30:
		await get_tree().physics_frame
	_ragdoll.hold(Vector3(6.0, 0.0, 4.0), Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * 0.1)


func test_lying_at_rest_it_starts_lying_on_the_point() -> void:
	_ragdoll.lie_at_rest(Vector3(0.0, 0.0, 3.0), PI * 0.5)
	add_child(_ragdoll)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * 0.05)
	for i: int in 60:
		await get_tree().physics_frame
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * SETTLE_M)


func test_lying_on_a_ledge_above_the_point_it_comes_down_to_the_point() -> void:
	# A shelf 0.6 m high from x 0.7 to 1.7: the body lies on it, then the host's point moves
	# beside it on the floor, within the snap distance: the pull brings it down there.
	var shelf := _box(Vector3(1.0, 0.6, 2.0), Vector3(1.2, 0.3, 0.0))
	_ragdoll.lie_at_rest(Vector3(1.2, 0.6, 0.0), PI * 0.5)
	add_child(_ragdoll)
	for i: int in 60:
		await get_tree().physics_frame
	assert_float(_pelvis().y).is_greater(0.6)
	_ragdoll.hold(Vector3(0.4, 0.0, 0.0), Vector3.ZERO)
	for i: int in 150:
		await get_tree().physics_frame
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * SETTLE_M)
	shelf.free()


func test_a_point_lifted_within_the_snap_distance_lifts_the_pelvis_to_it() -> void:
	# The spring's vertical term (critique of the plan, KE7): the host's body lies 0.6 m higher
	# (on something this client does not have, or in flight): this screen follows it there.
	_ragdoll.lie_at_rest(Vector3.ZERO, 0.0)
	add_child(_ragdoll)
	for i: int in 30:
		await get_tree().physics_frame
	_ragdoll.hold(Vector3(0.0, 0.6, 0.0), Vector3.ZERO)
	for i: int in 90:
		await get_tree().physics_frame
	# Hanging in the air the spring sags by g / SPRING_K (0.16 m).
	assert_float(_pelvis().y).is_equal_approx(_ragdoll.lying_centre().y, 0.25)


func test_knocked_down_on_a_step_whose_point_steps_down_it_does_not_snap_into_the_floor() -> void:
	# Knocked down standing on a 0.2 m step whose edge is at x 0; within the first frames the
	# host's point steps down beside it. The standing pelvis is about 0.9 m over the lying centre,
	# so measured against the lying centre alone this is past the snap distance, and the snap
	# would shift the standing pose down into the floor.
	# With a foot: a body that stands on the floor, as the art's shins and feet do.
	_ragdoll.free()
	_ragdoll = RagdollView.new()
	_ragdoll.setup(
		_rules,
		7,
		BodyColours.of(3),
		CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll(true))
	)
	var step := _box(Vector3(2.0, 0.2, 2.0), Vector3(-1.0, 0.1, 0.0))
	_ragdoll.start(Vector3(-0.15, 0.2, 0.0), 0.0, Vector3.ZERO)
	add_child(_ragdoll)
	var lowest := INF
	for i: int in 160:
		if i == 3:
			_ragdoll.hold(Vector3(0.3, 0.0, 0.0), Vector3.ZERO)
		await get_tree().physics_frame
		for bone: PhysicalBone3D in _ragdoll.bones():
			lowest = minf(lowest, bone.global_position.y)
	assert_float(lowest).is_greater(-0.05)
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * SETTLE_M)
	step.free()


func test_a_dead_one_is_grey_with_every_body_on_no_layer() -> void:
	_ragdoll.start(Vector3.ZERO, 0.0, Vector3(2.0, 0.0, 0.0))
	add_child(_ragdoll)
	await get_tree().physics_frame
	_ragdoll.make_dead(Vector3(0.5, 0.0, 0.0))
	assert_bool(_ragdoll.is_dead()).is_true()
	assert_int(_ragdoll.collision_layer).is_equal(0)
	for bone: PhysicalBone3D in _ragdoll.bones():
		assert_int(bone.collision_layer).is_equal(0)
	assert_object(_ragdoll.colour()).is_equal(LifeLooks.BODY_COLOUR)
	_ragdoll.set_colour(BodyColours.of(5))
	assert_object(_ragdoll.colour()).is_equal(LifeLooks.BODY_COLOUR)
	for i: int in 120:
		await get_tree().physics_frame
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * SETTLE_M)


func test_a_rays_collider_names_its_view() -> void:
	add_child(_ragdoll)
	var shape := _ragdoll.bones()[1].get_node(^"Shape")
	assert_object(RagdollView.of_collider(shape)).is_same(_ragdoll)
	assert_object(RagdollView.of_collider(_ragdoll.bones()[0])).is_same(_ragdoll)
	assert_object(RagdollView.of_collider(_ragdoll)).is_same(_ragdoll)
	assert_object(RagdollView.of_collider(_floor)).is_null()
	assert_object(RagdollView.of_collider(null)).is_null()


func test_handed_over_to_another_parent_it_keeps_simulating() -> void:
	var holder := Node3D.new()
	add_child(holder)
	_ragdoll.start(Vector3.ZERO, 0.0, Vector3.ZERO)
	add_child(_ragdoll)
	for i: int in 30:
		await get_tree().physics_frame
	remove_child(_ragdoll)
	holder.add_child(_ragdoll)
	_ragdoll.make_dead(Vector3.ZERO)
	for i: int in 90:
		await get_tree().physics_frame
	var sim := _ragdoll.rig().skeleton.get_node(^"Ragdoll") as PhysicalBoneSimulator3D
	assert_bool(sim.is_simulating_physics()).is_true()
	assert_vector(_pelvis()).is_equal_approx(_ragdoll.lying_centre(), Vector3.ONE * SETTLE_M)
	holder.remove_child(_ragdoll)
	_ragdoll.free()
	holder.free()


func _pelvis() -> Vector3:
	return _ragdoll.pelvis().global_position


func _assert_within_snap(slack: float) -> void:
	var off := _pelvis().distance_to(_ragdoll.lying_centre())
	assert_float(off).is_less_equal(RagdollView.SNAP_M + slack)


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	add_child(body)
	return body
