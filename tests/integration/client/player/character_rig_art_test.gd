extends GdUnitTestSuite
## CharacterRig on the shipped character's art (the base alien, #1693; the sockets of its profile,
## measured by the art lane on art#398): where each socket lands on the character, against the art's
## own bones, not against the profile's numbers (a wrong sign or a swapped axis in a point fails
## here); its size against the game's eye; its look in a player's colour. In the rig's frame the
## character faces -Z, its right hand is +X. A checkout without the Git LFS content (CI) imports a
## stand-in with no skeleton: no set, and each test says skip and checks only that the GLB is a
## pointer.

const Check := preload("res://tools/assets/asset_check.gd")
const STEP := 1.0 / 60.0
## How far a socket may sit from the art's landmark it is measured against, in metres.
const NEAR := 0.06


## Idle, the Hand socket is in the right hand's curled fingers (the alien has no grip pose): at the
## middle finger's base, below the wrist.
func test_idle_the_hand_socket_is_in_the_right_fingers() -> void:
	var rig := await _rig()
	if rig == null:
		return
	var hand := _socket_in_rig(rig, &"Hand").origin
	var knuckle := _bone_in_rig(rig, &"RightMiddleProximal").origin
	var wrist := _bone_in_rig(rig, &"RightHand").origin
	assert_float(hand.distance_to(knuckle)).override_failure_message("Hand").is_less(NEAR)
	assert_float(hand.y).is_less(wrist.y)
	assert_float(hand.x).is_greater(0.0)


## Idle, the Belt socket is on the outside of the left hip (beyond the hip joint), at its height.
func test_idle_the_belt_socket_is_on_the_outside_of_the_left_hip() -> void:
	var rig := await _rig()
	if rig == null:
		return
	var belt := _socket_in_rig(rig, &"Belt").origin
	var hip := _bone_in_rig(rig, &"LeftUpperLeg").origin
	assert_float(hip.x).is_less(0.0)
	assert_float(belt.x).override_failure_message("Belt left of the left hip").is_less(hip.x - 0.05)
	assert_float(absf(belt.y - hip.y)).override_failure_message("Belt at the hip").is_less(0.1)


## The Carry socket (fitted on the idle clip: the alien has no carry clip) is in front of the chest,
## below it, between the hands.
func test_the_carry_socket_is_in_front_of_the_chest_between_the_hands() -> void:
	var rig := await _rig()
	if rig == null:
		return
	var carry := _socket_in_rig(rig, &"Carry").origin
	var chest := _bone_in_rig(rig, &"Chest").origin
	var left := _bone_in_rig(rig, &"LeftHand").origin
	var right := _bone_in_rig(rig, &"RightHand").origin
	assert_float(carry.z).override_failure_message("Carry in front").is_less(chest.z - 0.15)
	assert_float(carry.x).is_between(minf(left.x, right.x), maxf(left.x, right.x))
	assert_float(carry.y).is_less(chest.y)


## Drawn at the profile's scale, the alien stands under the game's capsule with its head where the
## game's eye is (PlayerRules: the eye 1.6 m, the capsule 1.8 m).
func test_the_alien_stands_at_the_game_s_size() -> void:
	var rig := await _rig()
	if rig == null:
		return
	var top := 0.0
	for node: Node in rig.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		top = maxf(top, mesh.get_aabb().end.y)
	assert_float(top).is_between(1.75, 1.86)
	assert_float(_bone_in_rig(rig, &"Head").origin.y).is_between(1.3, 1.6)


## The look's skin takes a player's colour (CharacterRig.set_tint through the look); white keeps
## the look's own.
func test_the_look_takes_the_player_s_colour() -> void:
	var rig := await _rig()
	if rig == null:
		return
	var skins: Array[ShaderMaterial] = []
	for node: Node in rig.model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i: int in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(i) as ShaderMaterial
			if material != null:
				skins.append(material)
	assert_array(skins).is_not_empty()
	var colour := Color("e98a8c")
	rig.set_tint(colour)
	for material: ShaderMaterial in skins:
		assert_that(material.get_shader_parameter(&"skin_color")).is_equal(colour)


## A rig of the art, idle, its tree stepped by hand and its skeleton updated a frame later; null
## (after the skip check) without the art.
func _rig() -> CharacterRig:
	var character := CharacterSet.load_default()
	if character == null:
		var glb := CharacterSet.default_profile().glb
		print("skip: %s has no Git LFS content here: the character on the art is unchecked" % glb)
		assert_bool(Check.is_lfs_pointer(glb)).is_true()
		return null
	var rig := CharacterRig.make(character)
	add_child(rig)
	auto_free(rig)
	rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.set_physics_process(false)
	_run(rig, 0.2)
	await get_tree().process_frame
	await get_tree().process_frame
	return rig


func _run(rig: CharacterRig, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		rig.step(STEP)
		rig.tree.advance(STEP)
		left -= STEP


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
