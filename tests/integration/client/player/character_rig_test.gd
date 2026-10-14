extends GdUnitTestSuite
## CharacterRig (#522) on the in-memory fixture character: the plan's base clip, its rate, the
## carry layer filtered to Torso and below, a one-shot over them and back, the sockets on their
## bones at the old points, the tint per avatar, no root motion and no physical bones.

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


## At the rest pose each socket is where the placeholder's point was, on its bone.
func test_the_sockets_sit_on_their_bones_at_the_old_points() -> void:
	var rig := _rig()
	for socket_name: StringName in CharacterRig.SOCKETS:
		var entry: Array = CharacterRig.SOCKETS[socket_name]
		var socket := rig.socket(socket_name)
		var attach := socket.get_parent() as BoneAttachment3D
		assert_str(attach.bone_name).is_equal(str(entry[0]))
		var bone := rig.skeleton.find_bone(attach.bone_name)
		var rest := rig.model.transform * rig.skeleton.get_parent_node_3d().transform
		rest = rest * rig.skeleton.transform * rig.skeleton.get_bone_global_rest(bone)
		var point: Vector3 = entry[1]
		assert_vector((rest * socket.transform).origin).is_equal_approx(point, Vector3.ONE * 0.0001)


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
