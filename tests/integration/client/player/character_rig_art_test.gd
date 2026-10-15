extends GdUnitTestSuite
## CharacterRig's sockets on the art (slice_m1, #1050): where each measured point lands on the
## character, against the art's own bones, not against CharacterRig.SOCKETS (a wrong sign or a
## swapped axis in a point fails here). In the rig's frame the character faces -Z, its right hand is
## +X. A checkout without the Git LFS content (CI) imports a stand-in with no skeleton: no set, and
## each test says skip and checks only that the GLB is a pointer.

const Check := preload("res://tools/assets/asset_check.gd")
const STEP := 1.0 / 60.0
## How far a socket may sit from the art's landmark it is measured against, in metres.
const NEAR := 0.04


## Idle, the Hand socket is in the right palm: at the middle finger's knuckle, the wrist behind it.
func test_idle_the_hand_socket_is_in_the_right_palm() -> void:
	var rig := _rig()
	if rig == null:
		return
	var hand := _socket_in_rig(rig, &"Hand").origin
	var knuckle := _bone_in_rig(rig, &"Middle2.R").origin
	var wrist := _bone_in_rig(rig, &"Wrist.R").origin
	assert_float(hand.distance_to(knuckle)).override_failure_message("Hand").is_less(NEAR)
	assert_float(hand.distance_to(wrist)).is_greater(0.08)
	assert_float(hand.x).is_greater(0.0)


## Idle, the Belt socket is on the outside of the left hip (beyond the hip joint), at the joint's
## height.
func test_idle_the_belt_socket_is_on_the_outside_of_the_left_hip() -> void:
	var rig := _rig()
	if rig == null:
		return
	var belt := _socket_in_rig(rig, &"Belt").origin
	var hip := _bone_in_rig(rig, &"UpperLeg.L").origin
	assert_float(hip.x).is_less(0.0)
	assert_float(belt.x).override_failure_message("Belt left of the left hip").is_less(hip.x - 0.05)
	assert_float(absf(belt.y - hip.y)).override_failure_message("Belt at the hip").is_less(0.1)


## Carrying, the Carry socket is in front of the chest, between both palms and below them.
func test_carrying_the_carry_socket_is_in_front_of_the_chest_between_the_palms() -> void:
	var rig := _rig()
	if rig == null:
		return
	rig.apply(_plan(true))
	_run(rig, 0.5)
	var carry := _socket_in_rig(rig, &"Carry").origin
	var chest := _bone_in_rig(rig, &"Chest").origin
	var left := _bone_in_rig(rig, &"Middle2.L").origin
	var right := _bone_in_rig(rig, &"Middle2.R").origin
	assert_float(carry.z).override_failure_message("Carry in front").is_less(chest.z - 0.15)
	assert_float(carry.x).is_between(minf(left.x, right.x), maxf(left.x, right.x))
	assert_float(carry.y).is_less(minf(left.y, right.y))


## A rig of the art, idle, its tree stepped by hand; null (after the skip check) without the art.
func _rig() -> CharacterRig:
	var character := CharacterSet.load_default()
	if character == null:
		print(
			(
				"skip: %s has no Git LFS content here: the sockets on the art are unchecked"
				% [CharacterSet.DEFAULT_GLB]
			)
		)
		assert_bool(Check.is_lfs_pointer(CharacterSet.DEFAULT_GLB)).is_true()
		return null
	var rig := CharacterRig.make(character)
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


func _plan(carry: bool) -> AvatarClips.Plan:
	var plan := AvatarClips.Plan.new()
	plan.base = AvatarClips.IDLE
	plan.carry = carry
	return plan


## `bone`'s pose now in the rig's frame.
func _bone_in_rig(rig: CharacterRig, bone: StringName) -> Transform3D:
	var to_rig := Transform3D.IDENTITY
	var at: Node = rig.skeleton
	while at != rig:
		to_rig = (at as Node3D).transform * to_rig
		at = at.get_parent()
	return to_rig * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(bone))


## The socket `socket_name` now in the rig's frame, from its bone's pose.
func _socket_in_rig(rig: CharacterRig, socket_name: StringName) -> Transform3D:
	var socket := rig.socket(socket_name)
	var attach := socket.get_parent() as BoneAttachment3D
	return _bone_in_rig(rig, StringName(attach.bone_name)) * socket.transform
