extends GdUnitTestSuite
## CharacterProfile (#1693): the bones a character hangs on, its clips' speeds as drawn and the rate
## its moves play at. The alien's speeds are the package's measured ones at 0.94; a move's speed is
## its family's points' by the blend's heading, so the rate never jumps where the plan's base clip
## changes; slice_m1 moves as AvatarClips assumes.


func test_the_alien_s_bones_and_speeds_are_drawn_at_its_scale() -> void:
	var alien := CharacterProfile.alien()
	assert_array(alien.needed_bones()).contains_exactly_in_any_order(
		[&"Chest", &"RightHand", &"Hips", &"UpperChest"]
	)
	assert_float(alien.mps_of(&"Jog_Fwd", 4.5)).is_equal_approx(4.74 * 0.94, 1e-5)
	assert_float(alien.mps_of(&"Jog_Bwd_Left", 4.5)).is_equal_approx(2.0 * 0.94, 1e-5)
	assert_float(alien.mps_of(&"Idle", 0.0)).is_equal(0.0)
	var hand: Vector3 = alien.sockets[&"Hand"][1]
	assert_vector(hand).is_equal_approx(Vector3(-0.0262, 0.1645, 0.0123) * 0.94, Vector3.ONE * 1e-6)


func test_slice_m1_moves_as_avatar_clips_assumes() -> void:
	var slice := CharacterProfile.slice_m1()
	for heading_deg: float in [0.0, 30.0, 45.0, 89.0, -60.0]:
		var blend := Locomotion.blend_position(deg_to_rad(heading_deg))
		var factor := slice.rate_factor(AvatarClips.JOG_FWD, Locomotion.FRONT, blend)
		assert_float(factor).is_equal_approx(1.0, 1e-6)
	assert_float(slice.rate_factor(AvatarClips.IDLE, AvatarClips.IDLE, Vector2.ZERO)).is_equal(1.0)


func test_a_move_s_speed_lies_between_its_family_points_and_never_jumps() -> void:
	var alien := CharacterProfile.alien()
	var front := Locomotion.FRONT
	# On a point: that point's own speed.
	var ahead := alien.move_mps(AvatarClips.JOG_FWD, front, Locomotion.blend_position(0.0))
	assert_float(ahead).is_equal_approx(4.74 * 0.94, 1e-4)
	var left := Locomotion.blend_position(deg_to_rad(90.0))
	assert_float(alien.move_mps(AvatarClips.STRAFE_LEFT, front, left)).is_equal_approx(
		3.17 * 0.94, 1e-4
	)
	# Across 45 degrees, where the plan's base turns from Jog_Fwd to a strafe, the speed (so the
	# rate) moves on smoothly: the two sides of the switch play at nearly the same speed.
	var before := alien.move_mps(
		AvatarClips.JOG_FWD, front, Locomotion.blend_position(deg_to_rad(44.9))
	)
	var after := alien.move_mps(
		AvatarClips.STRAFE_LEFT, front, Locomotion.blend_position(deg_to_rad(45.1))
	)
	assert_float(absf(before - after)).is_less(0.02)
	assert_float(before).is_equal_approx(3.8 * 0.94, 0.02)
	# Between two points, between their speeds.
	var between := alien.move_mps(
		AvatarClips.JOG_FWD, front, Locomotion.blend_position(deg_to_rad(20.0))
	)
	assert_float(between).is_between(3.8 * 0.94, 4.74 * 0.94)
	# The back family: every point 2.0, so 2.0 everywhere in it, as drawn.
	var back := Locomotion.blend_position(deg_to_rad(160.0))
	assert_float(alien.move_mps(AvatarClips.JOG_BWD, Locomotion.BACK, back)).is_equal_approx(
		2.0 * 0.94, 1e-4
	)
	# Out of a family: the clip's own; and the factor is the assumed speed over it.
	var crouch := alien.rate_factor(AvatarClips.CROUCH_FWD, AvatarClips.CROUCH_FWD, Vector2.ZERO)
	assert_float(crouch).is_equal_approx(0.75 / (2.07 * 0.94), 1e-5)
