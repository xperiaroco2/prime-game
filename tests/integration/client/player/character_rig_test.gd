extends GdUnitTestSuite
## CharacterRig (#522) on the in-memory fixture character: the plan's base clip, its rate, the
## carry layer filtered to Torso and below, a one-shot over them and back, the sockets on their
## bones at their points (upright at their fitting poses, #1050), the tint per avatar, no root
## motion and no physical bones.

const Fixture := preload("res://tests/integration/client/player/character_fixture.gd")
const STEP := 1.0 / 60.0

var _set: CharacterSet


func before() -> void:
	_set = CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll())


func _rig() -> CharacterRig:
	var rig := CharacterRig.make(_set)
	add_child(rig)
	auto_free(rig)
	rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.set_physics_process(false)
	_run(rig, STEP)
	return rig


func _run(rig: CharacterRig, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		rig.step(STEP)
		rig.tree.advance(STEP)
		left -= STEP


func _angle(rig: CharacterRig, bone: StringName) -> float:
	var turn := rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone(bone))
	return turn.get_angle() * signf(turn.get_axis().x)


func _plan(base: StringName, rate := 1.0, carry := false) -> AvatarClips.Plan:
	var plan := AvatarClips.Plan.new()
	plan.base = base
	plan.rate = rate
	plan.carry = carry
	return plan


func test_it_stands_idle_and_plays_the_planned_base() -> void:
	var rig := _rig()
	assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(Fixture.base_angle(&"Idle"), 0.01)
	for clip: StringName in AvatarClips.base_clips():
		rig.apply(_plan(clip))
		_run(rig, 0.5)
		assert_str(String(rig.base_clip())).is_equal(String(clip))
		assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(Fixture.base_angle(clip), 0.01)


func test_the_rate_scales_the_base() -> void:
	var rig := _rig()
	rig.apply(_plan(AvatarClips.JOG_FWD, 1.7))
	assert_float(rig.tree.get("parameters/rate/scale") as float).is_equal_approx(1.7, 0.0001)


func test_the_carry_layer_moves_the_upper_body_only() -> void:
	var rig := _rig()
	rig.apply(_plan(AvatarClips.JOG_FWD, 1.0, true))
	_run(rig, 0.5)
	assert_float(rig.carry_weight()).is_equal(1.0)
	assert_float(_angle(rig, &"UpperArm.R")).is_equal_approx(Fixture.CARRY_ARM, 0.01)
	# Carry_Upper also turns the thigh, which the filter drops: the base's angle stays.
	var jog := Fixture.base_angle(&"Jog_Fwd")
	assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(jog, 0.01)
	rig.apply(_plan(AvatarClips.JOG_FWD, 1.0, false))
	_run(rig, 0.5)
	assert_float(rig.carry_weight()).is_equal(0.0)
	assert_float(_angle(rig, &"UpperArm.R")).is_equal_approx(0.0, 0.01)


func test_the_carry_filter_is_torso_and_every_bone_below() -> void:
	var rig := _rig()
	var bones := rig.carry_bones()
	for bone: String in ["Torso", "Chest", "UpperArm.R", "Wrist.R"]:
		assert_bool(bones.has(bone)).override_failure_message(bone).is_true()
	for bone: String in ["Root", "Body", "Hips", "Abdomen", "UpperLeg.L", "Foot.L"]:
		assert_bool(bones.has(bone)).override_failure_message(bone).is_false()


func test_a_one_shot_plays_over_the_base_and_returns() -> void:
	var rig := _rig()
	rig.apply(_plan(AvatarClips.JOG_FWD))
	_run(rig, 0.5)
	rig.play_one_shot(AvatarClips.PICKUP_PACKAGE)
	_run(rig, 0.25)
	assert_bool(rig.is_shot_active()).is_true()
	assert_float(_angle(rig, &"Chest")).is_greater(Fixture.SHOT_CHEST * 0.5)
	_run(rig, Fixture.SHOT_S + 0.3)
	assert_bool(rig.is_shot_active()).is_false()
	assert_float(_angle(rig, &"Chest")).is_equal_approx(0.0, 0.01)
	assert_str(String(rig.base_clip())).is_equal("Jog_Fwd")


func test_a_ragdoll_plan_or_an_unknown_clip_changes_nothing() -> void:
	var rig := _rig()
	rig.apply(_plan(AvatarClips.SPRINT_FWD))
	rig.apply(_plan(AvatarClips.RAGDOLL, 3.0, true))
	assert_str(String(rig.base_clip())).is_equal("Sprint_Fwd")
	rig.play_one_shot(&"No_Such_Clip")
	_run(rig, 0.1)
	assert_bool(rig.is_shot_active()).is_false()


func test_no_root_motion_and_no_physical_bones() -> void:
	var rig := _rig()
	rig.position = Vector3(3.0, 0.0, 1.0)
	rig.apply(_plan(AvatarClips.JOG_FWD))
	_run(rig, 0.8)
	assert_vector(rig.position).is_equal(Vector3(3.0, 0.0, 1.0))
	assert_vector(rig.model.position).is_equal(Vector3.ZERO)
	# Skeleton3D keeps an internal, empty PhysicalBoneSimulator3D of its own; no bone is a body.
	assert_array(rig.find_children("*", "PhysicalBone3D", true, false)).is_empty()


## Each socket is a child of its bone's attachment, at its point in the bone's own frame.
func test_each_socket_sits_at_its_point_in_its_bones_frame() -> void:
	var rig := _rig()
	for socket_name: StringName in CharacterRig.SOCKETS:
		var entry: Array = CharacterRig.SOCKETS[socket_name]
		var socket := rig.socket(socket_name)
		var attach := socket.get_parent() as BoneAttachment3D
		assert_str(attach.bone_name).is_equal(str(entry[0]))
		var point: Vector3 = entry[1]
		(
			assert_vector(socket.position)
			. override_failure_message(String(socket_name))
			. is_equal_approx(point, Vector3.ONE * 1e-6)
		)


## At the idle pose each socket is on its bone at its point; the hand and belt stand upright
## (their items level), the carry socket is turned back by the carry layer's chest lean (seen in
## the rig's frame, which faces the model's way), which the carry pose undoes (next test).
func test_at_the_idle_pose_the_sockets_are_on_their_bones() -> void:
	var rig := _rig()
	_run(rig, 0.3)
	for socket_name: StringName in CharacterRig.SOCKETS:
		var entry: Array = CharacterRig.SOCKETS[socket_name]
		var bone := _bone_in_rig(rig, entry[0] as StringName)
		var at := _socket_in_rig(rig, socket_name)
		var message := String(socket_name)
		var point: Vector3 = entry[1]
		assert_vector(at.origin).override_failure_message(message).is_equal_approx(
			bone * point, Vector3.ONE * 0.001
		)
		var upright := Basis.IDENTITY
		if entry[2]:
			var lean_back := Basis(Vector3.RIGHT, -Fixture.CARRY_CHEST)
			upright = rig.model.basis * lean_back * rig.model.basis.inverse()
		_assert_basis(at.basis, upright, message)


## Carrying (Carry_Upper on the carry layer), the carry socket stands upright on the leaning chest,
## so a two-handed item is carried level.
func test_carrying_the_carry_socket_stands_upright() -> void:
	var rig := _rig()
	rig.apply(_plan(AvatarClips.IDLE, 1.0, true))
	_run(rig, 0.5)
	var chest := rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone(&"Chest"))
	assert_float(chest.get_angle()).is_equal_approx(Fixture.CARRY_CHEST, 0.01)
	var entry: Array = CharacterRig.SOCKETS[&"Carry"]
	var point: Vector3 = entry[1]
	var at := _socket_in_rig(rig, &"Carry")
	assert_vector(at.origin).is_equal_approx(
		_bone_in_rig(rig, &"Chest") * point, Vector3.ONE * 0.001
	)
	_assert_basis(at.basis, Basis.IDENTITY, "Carry")


## Fitted at the pose the clips play (the idle clip's first frame), never the rest pose: on an
## arms-out bind pose the hand socket still stands upright while Idle plays, not turned with the
## rest pose's arm.
func test_on_an_arms_out_rest_the_hand_socket_stands_upright_while_idle_plays() -> void:
	var scene := Fixture.scene(AvatarClips.all_clips(), Fixture.BONES, true)
	var rig := CharacterRig.make(CharacterSet.from_scene(scene, Fixture.ragdoll()))
	add_child(rig)
	auto_free(rig)
	rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.set_physics_process(false)
	_run(rig, 0.3)
	var wrist := rig.skeleton.find_bone(&"Wrist.R")
	var rest := rig.skeleton.get_bone_global_rest(wrist).origin
	var pose := rig.skeleton.get_bone_global_pose(wrist).origin
	assert_float(rest.distance_to(pose)).is_greater(0.3)
	var point: Vector3 = CharacterRig.SOCKETS[&"Hand"][1]
	var at := _socket_in_rig(rig, &"Hand")
	assert_vector(at.origin).is_equal_approx(
		_bone_in_rig(rig, &"Wrist.R") * point, Vector3.ONE * 0.001
	)
	_assert_basis(at.basis, Basis.IDENTITY, "Hand")


func test_the_tint_is_per_avatar_and_multiplies_the_albedo() -> void:
	var a := _rig()
	var b := _rig()
	a.set_tint(Color(1.0, 0.5, 0.0))
	var mesh_a := a.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh_b := b.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var tinted := (mesh_a.get_active_material(0) as BaseMaterial3D).albedo_color
	assert_float(tinted.r).is_equal_approx(Fixture.ALBEDO.r, 0.001)
	assert_float(tinted.g).is_equal_approx(Fixture.ALBEDO.g * 0.5, 0.001)
	assert_float(tinted.b).is_equal_approx(0.0, 0.001)
	var other := (mesh_b.get_active_material(0) as BaseMaterial3D).albedo_color
	assert_float(other.g).is_equal_approx(Fixture.ALBEDO.g, 0.001)
	a.set_tint(Color.WHITE)
	tinted = (mesh_a.get_active_material(0) as BaseMaterial3D).albedo_color
	assert_float(tinted.g).is_equal_approx(Fixture.ALBEDO.g, 0.001)


## `bone`'s pose now in the rig's frame.
func _bone_in_rig(rig: CharacterRig, bone: StringName) -> Transform3D:
	var to_rig := rig.model.transform * rig.skeleton.get_parent_node_3d().transform
	to_rig = to_rig * rig.skeleton.transform
	return to_rig * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(bone))


## The socket `socket_name` now in the rig's frame, from its bone's pose.
func _socket_in_rig(rig: CharacterRig, socket_name: StringName) -> Transform3D:
	var socket := rig.socket(socket_name)
	var attach := socket.get_parent() as BoneAttachment3D
	return _bone_in_rig(rig, StringName(attach.bone_name)) * socket.transform


func _assert_basis(basis: Basis, expected: Basis, message: String) -> void:
	for axis: int in 3:
		assert_vector(basis[axis]).override_failure_message(message).is_equal_approx(
			expected[axis], Vector3.ONE * 0.001
		)
