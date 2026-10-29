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
	return Fixture.plan(base, rate, carry)


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
	for bone: String in ["Torso", "Chest", "UpperArm.R", "Wrist.R", "Neck", "Head"]:
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


## The measured points face the way the art's bone frames do (the art faces +Z, its bones run
## along +Y), so CI, which has no art (character_rig_art_test skips there), still sees a flipped
## sign: the hand point runs down Wrist.R toward the fingers, the belt point is on the left (+X in
## Hips' frame), the carry point is in front of the chest (+Z in Chest's frame) and below it.
func test_the_measured_points_face_the_arts_bone_frames() -> void:
	var hand: Vector3 = CharacterRig.SOCKETS[&"Hand"][1]
	var belt: Vector3 = CharacterRig.SOCKETS[&"Belt"][1]
	var carry: Vector3 = CharacterRig.SOCKETS[&"Carry"][1]
	assert_float(hand.y).override_failure_message("Hand toward the fingers").is_greater(0.05)
	assert_float(Vector2(hand.x, hand.z).length()).is_less(0.03)
	assert_float(belt.x).override_failure_message("Belt on the left hip").is_greater(0.1)
	assert_float(carry.z).override_failure_message("Carry in front").is_greater(0.2)
	assert_float(carry.y).override_failure_message("Carry below the chest").is_less(0.0)


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


## A rig drawn before any physics step (a picture's puppet, #787) stands in its plan at once:
## pose_now evaluates the tree and moves the sockets with the bones, never the arms-out rest.
func test_pose_now_poses_the_rig_and_its_sockets_without_a_physics_step() -> void:
	var scene := Fixture.scene(AvatarClips.all_clips(), Fixture.BONES, true)
	var rig := CharacterRig.make(CharacterSet.from_scene(scene, Fixture.ragdoll()))
	add_child(rig)
	auto_free(rig)
	rig.apply(_plan(AvatarClips.IDLE, 1.0, true))
	rig.pose_now()
	assert_float(rig.carry_weight()).is_equal(1.0)
	var wrist := rig.skeleton.find_bone(&"Wrist.R")
	var rest := rig.skeleton.get_bone_global_rest(wrist).origin
	assert_float(rest.distance_to(rig.skeleton.get_bone_global_pose(wrist).origin)).is_greater(0.3)
	var attach := rig.socket(&"Hand").get_parent() as BoneAttachment3D
	var bone := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(wrist)
	assert_vector(attach.global_position).is_equal_approx(bone.origin, Vector3.ONE * 0.001)


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


func _rig_of(clips: Array[StringName], with_look := false) -> CharacterRig:
	var character := CharacterSet.from_scene(Fixture.scene(clips), Fixture.ragdoll())
	var rig := CharacterRig.make(character, with_look)
	add_child(rig)
	auto_free(rig)
	rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.set_physics_process(false)
	_run(rig, STEP)
	return rig


func _moving(rig: CharacterRig, heading_deg: float) -> AvatarClips.Plan:
	var plan := AvatarClips.Plan.new()
	plan.blend = Locomotion.blend_position(deg_to_rad(heading_deg))
	plan.back = absf(heading_deg) > Locomotion.SWITCH_DEG
	plan.slot = Locomotion.BACK if plan.back else Locomotion.FRONT
	plan.base = AvatarClips.JOG_BWD if plan.back else AvatarClips.JOG_FWD
	rig.apply(plan)
	_run(rig, 0.5)
	return plan


func test_the_front_family_blends_its_points_and_a_lone_back_clip_plays_alone() -> void:
	var rig := _rig()
	assert_bool(rig.is_blended(Locomotion.FRONT)).is_true()
	assert_bool(rig.is_blended(Locomotion.BACK)).is_false()
	# On a point: its clip alone.
	_moving(rig, -90.0)
	assert_str(String(rig.base_slot())).is_equal("Front")
	var right := Fixture.base_angle(AvatarClips.STRAFE_RIGHT)
	assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(right, 0.01)
	# Between two points: a mix of the two, never another clip.
	_moving(rig, -45.0)
	var jog := Fixture.base_angle(AvatarClips.JOG_FWD)
	var mixed := _angle(rig, &"UpperLeg.L")
	assert_float(mixed).is_greater(jog + 0.01)
	assert_float(mixed).is_less(right - 0.01)
	# The back family's one clip, exactly, whatever the direction.
	_moving(rig, 150.0)
	assert_str(String(rig.base_slot())).is_equal("Back")
	var back := Fixture.base_angle(AvatarClips.JOG_BWD)
	assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(back, 0.01)


func test_a_diagonal_clip_the_character_has_becomes_a_point() -> void:
	var rig := _rig_of(Fixture.eight_way_clips())
	assert_bool(rig.is_blended(Locomotion.BACK)).is_true()
	for clip: StringName in Locomotion.optional_clips():
		for point: Dictionary in Locomotion.POINTS:
			if point["clip"] == clip:
				_moving(rig, point["heading_deg"] as float)
		var want := Fixture.base_angle(clip)
		var got := _angle(rig, &"UpperLeg.L")
		assert_float(got).override_failure_message(String(clip)).is_equal_approx(want, 0.01)


func test_the_families_cross_fade_never_blend() -> void:
	var rig := _rig()
	_moving(rig, 0.0)
	var plan := AvatarClips.Plan.new()
	plan.slot = Locomotion.BACK
	plan.base = AvatarClips.JOG_BWD
	plan.blend = Vector2(0.0, -1.0)
	rig.apply(plan)
	_run(rig, CharacterRig.XFADE_S * 0.5)
	var mid := _angle(rig, &"UpperLeg.L")
	assert_float(mid).is_greater(Fixture.base_angle(AvatarClips.JOG_FWD) + 0.01)
	assert_float(mid).is_less(Fixture.base_angle(AvatarClips.JOG_BWD) - 0.01)
	_run(rig, CharacterRig.XFADE_S)
	var back := Fixture.base_angle(AvatarClips.JOG_BWD)
	assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(back, 0.01)


## The head's forward in the rig's frame after the look turned it: the art faces +Z, the rig -Z.
func _look_of(rig: CharacterRig, yaw: float, pitch: float) -> Vector3:
	return (await _head_basis_of(rig, yaw, pitch)) * Vector3.BACK


## The head bone's basis in the rig's frame after the look turned it.
func _head_basis_of(rig: CharacterRig, yaw: float, pitch: float) -> Basis:
	rig.set_look(yaw, pitch)
	var head := rig.skeleton.find_bone(&"Head")
	# Read inside the pass: the skeleton restores the clip's pose before the next one.
	var seen: Array[Transform3D] = []
	var read := func() -> void: seen.append(rig.skeleton.get_bone_global_pose(head))
	rig.head_look().modification_processed.connect(read)
	# The skeleton runs its modifiers in its deferred update, each process frame.
	await get_tree().process_frame
	await get_tree().process_frame
	rig.head_look().modification_processed.disconnect(read)
	assert_bool(seen.is_empty()).is_false()
	if seen.is_empty():
		return Basis.IDENTITY
	return (rig.model.transform * seen[-1]).basis


func test_a_shake_while_looking_down_turns_the_head_by_the_whole_aim_unrolled() -> void:
	# Neck and Head each take a share, but the Head inherits the Neck's: together they make
	# exactly the aim's turn (yaw, then pitch), not two half turns with a roll between them.
	var rig := _rig_of(AvatarClips.all_clips(), true)
	var rest: Basis = await _head_basis_of(rig, 0.0, 0.0)
	var yaw := deg_to_rad(60.0)
	var pitch := deg_to_rad(-35.0)
	var turned: Basis = await _head_basis_of(rig, yaw, pitch)
	var expected := HeadLook.turn_of(yaw, pitch) * rest
	for axis: Vector3 in [Vector3.BACK, Vector3.UP, Vector3.RIGHT]:
		assert_float((turned * axis).angle_to(expected * axis)).is_less(0.01)


func test_the_head_look_turns_the_neck_and_head_within_the_clamps() -> void:
	var rig := _rig_of(AvatarClips.all_clips(), true)
	assert_object(rig.head_look()).is_not_null()
	var ahead: Vector3 = await _look_of(rig, 0.0, 0.0)
	assert_float(ahead.angle_to(Vector3.FORWARD)).is_less(0.01)
	# To the left (toward -X) by the yaw, up by the pitch.
	var left: Vector3 = await _look_of(rig, deg_to_rad(50.0), 0.0)
	assert_float(left.angle_to(Vector3.FORWARD)).is_equal_approx(deg_to_rad(50.0), 0.01)
	assert_float(left.x).is_less(0.0)
	var up: Vector3 = await _look_of(rig, 0.0, deg_to_rad(30.0))
	assert_float(up.y).is_equal_approx(0.5, 0.01)
	# Clamped: yaw 70, pitch up 40 and down 35.
	var far: Vector3 = await _look_of(rig, 2.5, 0.0)
	assert_float(far.angle_to(Vector3.FORWARD)).is_equal_approx(deg_to_rad(70.0), 0.01)
	var high: Vector3 = await _look_of(rig, 0.0, 1.5)
	assert_float(high.y).is_equal_approx(sin(deg_to_rad(40.0)), 0.01)
	var low: Vector3 = await _look_of(rig, 0.0, -1.5)
	assert_float(low.y).is_equal_approx(-sin(deg_to_rad(35.0)), 0.01)
	# The legs keep the clip.
	assert_float(_angle(rig, &"UpperLeg.L")).is_equal_approx(Fixture.base_angle(&"Idle"), 0.01)


func test_no_head_look_without_the_bones_or_for_a_ragdolls_rig() -> void:
	assert_object(_rig().head_look()).is_null()
	var bones: Array[StringName] = []
	for bone: StringName in Fixture.BONES:
		if bone != &"Neck" and bone != &"Head":
			bones.append(bone)
	var character := CharacterSet.from_scene(
		Fixture.scene(AvatarClips.all_clips(), bones), Fixture.ragdoll()
	)
	var rig := CharacterRig.make(character, true)
	auto_free(rig)
	assert_object(rig.head_look()).is_null()
	rig.set_look(1.0, 1.0)
