extends GdUnitTestSuite
## AvatarClips (#522): the state to clip table row by row (the thresholds, the heading, the crouch,
## the carry layer, the rate and its clamp, the ragdoll), the one-shots, every clip it can return
## in the import contract with its loop flag, and no claimed velocity in its source.

const WALK := 4.5
const SPRINT := 7.0
const CONTRACT := "res://tools/assets/asset_contract.json"


## A state moving at `speed` m/s at `heading` radians from the body's forward (positive: to its
## left), the body turned by `yaw`.
func _moving(speed: float, heading := 0.0, yaw := 0.0) -> AvatarClips.State:
	var state := AvatarClips.State.new()
	state.yaw = yaw
	state.drawn_move = Basis(Vector3.UP, yaw + heading) * Vector3(0.0, 0.0, -speed)
	return state


func _plan(state: AvatarClips.State) -> AvatarClips.Plan:
	return AvatarClips.plan(state, WALK, SPRINT)


func test_standing_still_is_idle() -> void:
	var plan := _plan(_moving(0.0))
	assert_str(String(plan.base)).is_equal("Idle")
	assert_float(plan.rate).is_equal(1.0)
	assert_bool(plan.carry).is_false()
	assert_str(String(_plan(_moving(AvatarClips.MIN_SPEED_MPS - 0.01)).base)).is_equal("Idle")


func test_walk_and_run_from_the_drawn_speed() -> void:
	assert_str(String(_plan(_moving(AvatarClips.MIN_SPEED_MPS)).base)).is_equal("Jog_Fwd")
	assert_str(String(_plan(_moving(5.74)).base)).is_equal("Jog_Fwd")
	assert_str(String(_plan(_moving(5.76)).base)).is_equal("Sprint_Fwd")
	assert_str(String(_plan(_moving(SPRINT)).base)).is_equal("Sprint_Fwd")


func test_the_rate_is_the_speed_over_the_clips_ground_speed() -> void:
	assert_float(_plan(_moving(WALK)).rate).is_equal_approx(1.0, 0.0001)
	assert_float(_plan(_moving(2.25)).rate).is_equal_approx(0.5, 0.0001)
	assert_float(_plan(_moving(SPRINT)).rate).is_equal_approx(1.0, 0.0001)
	# Clamped both ways.
	assert_float(_plan(_moving(0.6)).rate).is_equal(AvatarClips.MIN_RATE)
	assert_float(_plan(_moving(40.0)).rate).is_equal(AvatarClips.MAX_RATE)


func test_the_heading_against_the_body_picks_the_clip() -> void:
	# Turned bodies: the heading counts from the body's yaw, not the world's axes.
	for yaw: float in [0.0, 1.3, -2.4]:
		assert_str(String(_plan(_moving(WALK, 0.3, yaw)).base)).is_equal("Jog_Fwd")
		assert_str(String(_plan(_moving(WALK, PI, yaw)).base)).is_equal("Jog_Bwd")
		assert_str(String(_plan(_moving(WALK, PI - 0.6, yaw)).base)).is_equal("Jog_Bwd")
		assert_str(String(_plan(_moving(WALK, PI * 0.5, yaw)).base)).is_equal("Strafe_Left")
		assert_str(String(_plan(_moving(WALK, -PI * 0.5, yaw)).base)).is_equal("Strafe_Right")
		assert_str(String(_plan(_moving(WALK, -PI * 0.6, yaw)).base)).is_equal("Strafe_Right")
	# A sprint backward or sideways plays the jog clip faster.
	var back := _plan(_moving(SPRINT, PI))
	assert_str(String(back.base)).is_equal("Jog_Bwd")
	assert_float(back.rate).is_equal_approx(SPRINT / AvatarClips.JOG_MPS, 0.0001)


func test_crouched_idle_and_walk() -> void:
	var still := _moving(0.0)
	still.crouched = true
	assert_str(String(_plan(still).base)).is_equal("Crouch_Idle")
	for heading: float in [0.0, PI, PI * 0.5]:
		var walk := _moving(1.5, heading)
		walk.crouched = true
		var plan := _plan(walk)
		assert_str(String(plan.base)).is_equal("Crouch_Fwd")
		assert_float(plan.rate).is_equal_approx(1.5 / AvatarClips.CROUCH_MPS, 0.0001)


func test_carrying_adds_the_upper_layer_over_every_base() -> void:
	var cases: Array[AvatarClips.State] = [
		_moving(0.0), _moving(WALK), _moving(SPRINT), _moving(WALK, PI)
	]
	var crouched := _moving(1.0)
	crouched.crouched = true
	cases.append(crouched)
	for state: AvatarClips.State in cases:
		var before := _plan(state)
		state.carrying = true
		var plan := _plan(state)
		assert_bool(plan.carry).is_true()
		assert_str(String(plan.base)).is_equal(String(before.base))
		assert_float(plan.rate).is_equal(before.rate)


func test_knocked_down_or_dead_is_the_ragdoll_whatever_else() -> void:
	for speed: float in [0.0, WALK, SPRINT]:
		var downed := _moving(speed)
		downed.downed = true
		downed.crouched = true
		downed.carrying = true
		var plan := _plan(downed)
		assert_str(String(plan.base)).is_equal(String(AvatarClips.RAGDOLL))
		assert_bool(plan.carry).is_false()
		var body := _moving(speed)
		body.dead_body = true
		assert_str(String(_plan(body).base)).is_equal(String(AvatarClips.RAGDOLL))
	assert_bool(AvatarClips.all_clips().has(AvatarClips.RAGDOLL)).is_false()


func test_posed_is_the_seated_clip_still_whatever_the_drawn_move() -> void:
	# #1296: no seated clip exists yet, so SEATED is Idle (blocked on art); a posed body is still,
	# even while the interpolation still draws its last step, and keeps its carry layer.
	assert_str(String(AvatarClips.SEATED)).is_equal("Idle")
	for speed: float in [0.0, WALK, SPRINT]:
		var posed := _moving(speed, PI)
		posed.posed = true
		posed.carrying = true
		var plan := _plan(posed)
		assert_str(String(plan.base)).is_equal(String(AvatarClips.SEATED))
		assert_str(String(plan.slot)).is_equal(String(AvatarClips.SEATED))
		assert_float(plan.rate).is_equal(1.0)
		assert_bool(plan.carry).is_true()
		posed.crouched = true
		assert_str(String(_plan(posed).base)).is_equal("Crouch_Idle")
		posed.downed = true
		assert_str(String(_plan(posed).base)).is_equal(String(AvatarClips.RAGDOLL))


func test_a_vertical_move_or_a_broken_number_is_idle() -> void:
	var falling := AvatarClips.State.new()
	falling.drawn_move = Vector3(0.0, -9.0, 0.0)
	assert_str(String(_plan(falling).base)).is_equal("Idle")
	var nan := _moving(WALK)
	nan.drawn_move = Vector3(NAN, 0.0, 1.0)
	assert_str(String(_plan(nan).base)).is_equal("Idle")
	var inf := _moving(WALK)
	inf.drawn_move = Vector3(INF, 0.0, 0.0)
	assert_str(String(_plan(inf).base)).is_equal("Idle")
	var bad_yaw := _moving(WALK)
	bad_yaw.yaw = NAN
	assert_str(String(_plan(bad_yaw).base)).is_equal("Idle")


func test_the_one_shots() -> void:
	var pick := AvatarClips.Shot.PICKUP
	var put := AvatarClips.Shot.PUTDOWN
	assert_str(String(AvatarClips.one_shot(pick, true))).is_equal("Pickup_Package")
	assert_str(String(AvatarClips.one_shot(pick, false))).is_equal("Pickup_One")
	assert_str(String(AvatarClips.one_shot(put, true))).is_equal("Putdown_Package")
	assert_str(String(AvatarClips.one_shot(put, false))).is_equal("Putdown_One")


## The import check holds every clip the avatar plays, looping as it is played: the bases and the
## carry layer loop, the one-shots play once.
func test_every_clip_is_in_the_import_contract_with_its_loop() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	var loops: Dictionary[String, bool] = {}
	for clip: Dictionary in (contract["character"] as Dictionary)["clips"]:
		loops[clip["name"] as String] = clip["loop"] as bool
	for clip: StringName in AvatarClips.all_clips():
		var name := String(clip)
		(
			assert_bool(loops.has(name))
			. override_failure_message("%s not in the contract" % name)
			. is_true()
		)
		var once := AvatarClips.shot_clips().has(clip)
		assert_bool(loops.get(name, once) as bool).is_equal(not once)


## Remote avatars are drawn from their interpolated poses only (invariant 7): no clip comes from a
## claimed velocity (`SnapshotBuffer.Pose.velocity` or the model's).
func test_no_velocity_in_the_clip_code() -> void:
	for path: String in ["res://client/player/avatar_clips.gd"]:
		var source := FileAccess.get_file_as_string(path)
		assert_bool(source.is_empty()).is_false()
		assert_bool(source.contains(".velocity")).override_failure_message(path).is_false()


## The same for AvatarViews' clip code (_animate): its ragdoll may launch with the host's velocity
## of a downed snapshot (KE14), its clips never.
func test_no_velocity_in_avatar_views_clip_code() -> void:
	var source := FileAccess.get_file_as_string("res://client/world/avatar_views.gd")
	var start := source.find("\nfunc _animate(")
	assert_int(start).is_greater(0)
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start if end > 0 else -1)
	assert_bool(body.contains("drawn_move")).is_true()
	assert_bool(body.contains("velocity")).is_false()


func test_the_family_switch_keeps_its_dead_zone() -> void:
	# From the front, 108 degrees off forward is still a strafe; 112 is the back family.
	var near := _plan(_moving(WALK, deg_to_rad(108.0)))
	assert_str(String(near.base)).is_equal("Strafe_Left")
	assert_str(String(near.slot)).is_equal("Front")
	assert_bool(near.back).is_false()
	var past := _plan(_moving(WALK, deg_to_rad(-112.0)))
	assert_str(String(past.base)).is_equal("Jog_Bwd")
	assert_str(String(past.slot)).is_equal("Back")
	assert_bool(past.back).is_true()
	# From the back, 95 degrees stays back; 85 is the front again.
	var state := _moving(WALK, deg_to_rad(95.0))
	state.was_back = true
	assert_str(String(_plan(state).slot)).is_equal("Back")
	state = _moving(WALK, deg_to_rad(85.0))
	state.was_back = true
	assert_str(String(_plan(state).slot)).is_equal("Front")
	# Standing keeps the family the last move had.
	state = _moving(0.0)
	state.was_back = true
	assert_bool(_plan(state).back).is_true()


func test_the_plan_carries_the_direction_and_the_slot() -> void:
	var left := _plan(_moving(WALK, PI * 0.5, 1.1))
	assert_float(left.blend.distance_to(Vector2(-1.0, 0.0))).is_less(0.0001)
	var ahead := _plan(_moving(WALK, 0.0, -0.4))
	assert_float(ahead.blend.distance_to(Vector2(0.0, 1.0))).is_less(0.0001)
	assert_str(String(ahead.slot)).is_equal("Front")
	assert_str(String(_plan(_moving(SPRINT)).slot)).is_equal("Sprint_Fwd")
	assert_str(String(_plan(_moving(0.0)).slot)).is_equal("Idle")
	var crouched := _moving(1.0, PI)
	crouched.crouched = true
	assert_str(String(_plan(crouched).slot)).is_equal("Crouch_Fwd")
	assert_that(_plan(crouched).blend).is_equal(Vector2.ZERO)
