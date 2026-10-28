extends GdUnitTestSuite
## AvatarViews with a character (#522, ARCHITECTURE §4.7.53), on the in-memory fixture rig (no LFS
## content): the rig draws the body in the capsule's place (the collision capsule stays), hidden
## while downed or watched, tinted by the body colour, its sockets the item points; the clip comes
## from the drawn move, the yaw and the crouch bit, never the claimed velocity; a placement's jump
## is no move; a two-handed hand item adds the carry layer; picking up and putting down (the cause
## put_down only, its holder the one drawn holding it) play their one-shots after the
## interpolation delay, on others' bodies only. Without a character the bodies stay capsules.

const Fixture := preload("res://tests/integration/client/player/character_fixture.gd")
const PEER := 2
const OWN := 3
const PACKAGE := 7
const TOOL := 8
const TICK_USEC := 50000
const FRAME_USEC := 16667

var _views: AvatarViews
var _model: ClientModel
var _now := 1000000
var _tick := 0


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_views = AvatarViews.new()
	_views.model = _model
	_views.buffer = SnapshotBuffer.new()
	_views.rules = FixtureModes.player_rules()
	_views.mode = FixtureItemModes.basic()
	_views.clock = func() -> int: return _now
	_views.character = CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll())
	_tick = 0
	add_child(_views)


func after_test() -> void:
	_views.free()


func test_the_character_draws_the_body_in_the_capsule_s_place() -> void:
	await _stand(Vector3.ZERO)
	var body := _views.body_of(PEER)
	var rig := body.character()
	assert_object(rig).is_not_null()
	assert_bool(rig.visible).is_true()
	assert_bool((body.get_node(^"Mesh") as MeshInstance3D).visible).is_false()
	assert_bool((body.head().get_node(^"Visor") as Node3D).visible).is_false()
	assert_bool((body.get_node(^"CollisionShape3D") as CollisionShape3D).disabled).is_false()
	assert_object(body.hand_point()).is_same(rig.socket(&"Hand"))
	assert_object(body.belt_point()).is_same(rig.socket(&"Belt"))
	assert_object(body.carry_point()).is_same(rig.socket(&"Carry"))
	assert_object(body.mouth_point()).is_not_null()


func test_watched_or_downed_hides_the_character() -> void:
	await _stand(Vector3.ZERO)
	var body := _views.body_of(PEER)
	body.set_watched(true)
	assert_bool(body.character().visible).is_false()
	body.set_watched(false)
	assert_bool(body.character().visible).is_true()
	body.set_downed(true)
	assert_bool(body.character().visible).is_false()
	assert_bool((body.get_node(^"Mesh") as MeshInstance3D).visible).is_false()


func test_the_body_colour_tints_the_character() -> void:
	_model.fold(&"PlayerJoined", {"peer": PEER, "name": "B", "spot": Vector3.ZERO, "colour": 4})
	await _stand(Vector3.ZERO)
	var rig := _views.body_of(PEER).character()
	assert_object(rig.tint()).is_equal(BodyColours.of(4))
	var mesh := rig.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var albedo := (mesh.get_active_material(0) as BaseMaterial3D).albedo_color
	assert_float(albedo.g).is_equal_approx(Fixture.ALBEDO.g * rig.tint().g, 0.001)


func test_without_a_character_the_body_stays_a_capsule() -> void:
	_views.character = null
	await _stand(Vector3.ZERO)
	var body := _views.body_of(PEER)
	assert_object(body.character()).is_null()
	assert_bool((body.get_node(^"Mesh") as MeshInstance3D).visible).is_true()
	assert_bool((body.head().get_node(^"Visor") as Node3D).visible).is_true()
	assert_str(body.hand_point().name).is_equal("HandPoint")


func test_a_claimed_velocity_never_picks_the_clip() -> void:
	# Standing still while every snapshot claims a sprint.
	await _walk(Vector3.ZERO, Vector3.FORWARD, 8, false, Vector3(7, 0, 0))
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.IDLE))


func test_the_drawn_move_picks_jog_strafe_and_sprint() -> void:
	# 0.2 m a tick is 4 m/s ahead (the facing is -Z).
	await _walk(Vector3(0, 0, -0.2), Vector3.FORWARD, 10)
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.JOG_FWD))
	await _walk(Vector3(0.2, 0, 0), Vector3.FORWARD, 10)
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.STRAFE_RIGHT))
	await _walk(Vector3(0, 0, -0.35), Vector3.FORWARD, 10)
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.SPRINT_FWD))


func test_crouched_standing_still_is_crouch_idle() -> void:
	await _walk(Vector3.ZERO, Vector3.FORWARD, 6, true)
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.CROUCH_IDLE))


func test_a_placement_s_jump_is_no_move() -> void:
	await _walk(Vector3.ZERO, Vector3.FORWARD, 6)
	# A respawn far away: the next drawn frame jumps 50 m, faster than anyone moves.
	for tick: int in 6:
		_arrive(Vector3(50, 0, 0), Vector3.FORWARD)
	for frame: int in 30:
		await _frame()
		assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.IDLE))


func test_a_two_handed_hand_item_adds_the_carry_layer() -> void:
	await _stand(Vector3.ZERO)
	_spawn(PACKAGE, &"package")
	_pick_up(PEER, PACKAGE)
	for frame: int in 30:
		await _frame()
	assert_float(_rig().carry_weight()).is_greater(0.9)


func test_a_one_handed_hand_item_adds_none() -> void:
	await _stand(Vector3.ZERO)
	_spawn(TOOL, &"tool")
	_pick_up(PEER, TOOL)
	for frame: int in 30:
		await _frame()
	assert_float(_rig().carry_weight()).is_equal(0.0)


func test_picking_up_plays_its_one_shot_after_the_delay() -> void:
	await _stand(Vector3.ZERO)
	_spawn(PACKAGE, &"package")
	var delay_frames := ceili(_views.delay_ms() * 1000.0 / FRAME_USEC)
	assert_int(delay_frames).is_greater(1)
	_pick_up(PEER, PACKAGE)
	for frame: int in delay_frames - 1:
		await _frame()
		assert_bool(_rig().is_shot_active()).is_false()
	for frame: int in 3:
		await _frame()
	assert_bool(_rig().is_shot_active()).is_true()
	assert_str(String(_shot_clip())).is_equal(String(AvatarClips.PICKUP_PACKAGE))


func test_putting_down_plays_its_one_shot_on_the_holder() -> void:
	await _holding(TOOL, &"tool")
	_place(TOOL, Items.PUT_DOWN)
	await _past_delay()
	assert_bool(_rig().is_shot_active()).is_true()
	assert_str(String(_shot_clip())).is_equal(String(AvatarClips.PUTDOWN_ONE))


func test_other_causes_play_no_put_down() -> void:
	for cause: StringName in [Items.THROWN, Items.DEATH, Items.SWAP, Items.LEAVE]:
		await _holding(TOOL, &"tool")
		_place(TOOL, cause)
		await _past_delay()
		assert_bool(_rig().is_shot_active()).override_failure_message(String(cause)).is_false()


func test_a_put_down_of_an_item_nobody_was_drawn_holding_plays_none() -> void:
	await _stand(Vector3.ZERO)
	_spawn(TOOL, &"tool")
	_place(TOOL, Items.PUT_DOWN)
	await _past_delay()
	assert_bool(_rig().is_shot_active()).is_false()


func test_a_one_shot_whose_holder_is_down_when_it_comes_is_dropped() -> void:
	await _stand(Vector3.ZERO)
	_spawn(PACKAGE, &"package")
	_pick_up(PEER, PACKAGE)
	await _frame()
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _past_delay()
	assert_bool(_views.body_of(PEER).is_downed()).is_true()
	assert_bool(_rig().is_shot_active()).is_false()


func test_the_own_player_s_pick_up_queues_nothing() -> void:
	await _stand(Vector3.ZERO)
	_model.own_peer = OWN
	_spawn(TOOL, &"tool")
	_pick_up(OWN, TOOL)
	await _past_delay()
	assert_bool(_rig().is_shot_active()).is_false()


func test_a_knocked_down_player_s_ragdoll_is_the_character_s_skeleton() -> void:
	await _stand(Vector3.ZERO)
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _stand(Vector3.ZERO)
	var ragdoll := _views.ragdoll_of(PEER)
	assert_object(ragdoll).is_not_null()
	assert_object(ragdoll.rig()).is_not_null()
	assert_int(ragdoll.bones().size()).is_equal((Fixture.ragdoll()["bones"] as Array).size())
	assert_object(ragdoll.colour()).is_equal(BodyColours.of(_model.colour_of(PEER)))
	assert_bool(_views.body_of(PEER).character().visible).is_false()


func test_a_head_shake_inside_the_dead_zone_turns_the_head_not_the_body() -> void:
	await _stand(Vector3.ZERO)
	var body := _views.body_of(PEER)
	var look := _rig().head_look()
	assert_object(look).is_not_null()
	for yaw_deg: float in [30.0, -30.0, 40.0]:
		var yaw := deg_to_rad(yaw_deg)
		await _look(yaw, 0.0)
		# The root keeps the aim: spectate and the sight point read it.
		assert_float(body.rotation.y).is_equal_approx(yaw, 0.001)
		assert_float(body.body_yaw).is_equal_approx(0.0, 0.001)
		assert_float(_rig().rotation.y).is_equal_approx(-yaw, 0.001)
		assert_float(look.aim_yaw).is_equal_approx(yaw, 0.001)


func test_past_the_dead_zone_the_body_follows_the_aim() -> void:
	await _stand(Vector3.ZERO)
	var body := _views.body_of(PEER)
	await _look(deg_to_rad(100.0), 0.0)
	assert_float(body.rotation.y).is_equal_approx(deg_to_rad(100.0), 0.001)
	assert_float(body.body_yaw).is_equal_approx(deg_to_rad(55.0), 0.001)
	assert_float(_rig().rotation.y).is_equal_approx(deg_to_rad(-45.0), 0.001)
	assert_float(_rig().head_look().aim_yaw).is_equal_approx(deg_to_rad(45.0), 0.001)


func test_a_nod_turns_the_head_by_the_pitch() -> void:
	await _stand(Vector3.ZERO)
	for pitch_deg: float in [30.0, -30.0]:
		await _look(0.0, deg_to_rad(pitch_deg))
		assert_float(_rig().head_look().aim_pitch).is_equal_approx(deg_to_rad(pitch_deg), 0.001)
		assert_float(_views.body_of(PEER).head().rotation.x).is_equal_approx(
			deg_to_rad(pitch_deg), 0.001
		)


func test_a_placement_draws_the_body_on_the_aim() -> void:
	await _stand(Vector3.ZERO)
	await _look(deg_to_rad(30.0), 0.0)
	assert_float(_views.body_of(PEER).body_yaw).is_equal_approx(0.0, 0.001)
	# A respawn far away facing the same way: no turn carried over from where it stood.
	var facing := _facing(deg_to_rad(30.0), 0.0)
	for tick: int in 8:
		_arrive(Vector3(50, 0, 0), facing)
		await _frame()
		await _frame()
		await _frame()
	assert_float(_views.body_of(PEER).body_yaw).is_equal_approx(deg_to_rad(30.0), 0.001)
	assert_float(_rig().rotation.y).is_equal_approx(0.0, 0.001)


func test_the_body_s_yaw_picks_the_family_and_plan_of_keeps_it() -> void:
	assert_object(_views.plan_of(PEER)).is_null()
	await _stand(Vector3.ZERO)
	# Aim 40 degrees left of a body still facing -Z: a move straight ahead is the body's Jog_Fwd.
	await _look(deg_to_rad(40.0), 0.0)
	await _walk(Vector3(0, 0, -0.2), _facing(deg_to_rad(40.0), 0.0), 10)
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.JOG_FWD))
	assert_bool(_views.plan_of(PEER).back).is_false()
	# Backing away: the back family, kept by plan_of.
	await _walk(Vector3(0, 0, 0.1), _facing(deg_to_rad(40.0), 0.0), 10)
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.JOG_BWD))
	assert_bool(_views.plan_of(PEER).back).is_true()


func test_a_heading_inside_the_switch_s_dead_zone_keeps_the_last_family() -> void:
	# Art #196: the families switch at 100 degrees off the body, +-10 of dead zone. At 105 a
	# remote body stays in the family its last plan had (AvatarViews hands it back to
	# Locomotion), so a heading wobbling about the switch never flickers.
	# One unbroken path (_walk starts from the drawn place, which lags the last arrival).
	await _stand(Vector3.ZERO)
	var at := Vector3.ZERO
	at = await _walk_on(at, _facing(deg_to_rad(150.0), 0.0) * 0.2, 10)
	assert_bool(_views.plan_of(PEER).back).is_true()
	at = await _walk_on(at, _facing(deg_to_rad(105.0), 0.0) * 0.2, 10)
	assert_bool(_views.plan_of(PEER).back).is_true()
	assert_str(String(_rig().base_clip())).is_equal(String(AvatarClips.JOG_BWD))
	at = await _walk_on(at, Vector3(0, 0, -0.2), 10)
	assert_bool(_views.plan_of(PEER).back).is_false()
	at = await _walk_on(at, _facing(deg_to_rad(105.0), 0.0) * 0.2, 10)
	assert_bool(_views.plan_of(PEER).back).is_false()


## PEER moving on from its last arrival `at` by `step` a tick for `ticks` ticks, aiming along -Z;
## returns where it arrived last.
func _walk_on(at: Vector3, step: Vector3, ticks: int) -> Vector3:
	for tick: int in ticks:
		at += step
		_arrive(at, Vector3.FORWARD)
		await _frame()
		await _frame()
		await _frame()
	return at


## PEER standing at `at`, drawn for a few frames.
func _stand(at: Vector3) -> void:
	for tick: int in 4:
		_arrive(at, Vector3.FORWARD)
		await _frame()
		await _frame()
		await _frame()


## PEER moving `step` metres a tick for `ticks` ticks, three physics frames a tick, the clock
## advancing with them.
func _walk(
	step: Vector3, facing: Vector3, ticks: int, crouched := false, velocity := Vector3.ZERO
) -> void:
	var body := _views.body_of(PEER)
	var at := body.global_position if body != null else Vector3.ZERO
	for tick: int in ticks:
		at += step
		_arrive(at, facing, crouched, velocity)
		await _frame()
		await _frame()
		await _frame()


## PEER standing where it is, its aim turned to `yaw` (positive left) and `pitch` (up), drawn
## until the interpolation reached it.
func _look(yaw: float, pitch: float) -> void:
	var at := _views.body_of(PEER).global_position
	for tick: int in 8:
		_arrive(at, _facing(yaw, pitch))
		await _frame()
		await _frame()
		await _frame()


## The facing of an aim at `yaw` (positive left of -Z) and `pitch` (positive up).
func _facing(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## PEER holding `item` (of `kind`), drawn so for some frames, then every shot played out.
func _holding(item: int, kind: StringName) -> void:
	await _stand(Vector3.ZERO)
	_spawn(item, kind)
	_pick_up(PEER, item)
	for frame: int in 60:
		await _frame()


## The next snapshot arrives now with PEER at `at`.
func _arrive(at: Vector3, facing: Vector3, crouched := false, velocity := Vector3.ZERO) -> void:
	_tick += 1
	var avatar := {
		"position": at,
		"velocity": velocity,
		"facing": facing,
		"crouched": crouched,
	}
	var fields := {"tick": _tick, "avatars": {PEER: avatar}}
	_model.fold_snapshot(fields)
	_views.buffer.add(_tick, fields["avatars"] as Dictionary, _now)


## One physics frame, the clock a frame on.
func _frame() -> void:
	_now += FRAME_USEC
	await get_tree().physics_frame


func _past_delay() -> void:
	for frame: int in ceili(_views.delay_ms() * 1000.0 / FRAME_USEC) + 3:
		await _frame()


## The session's order: the model folds the event, then AvatarViews hears it.
func _event(event_name: StringName, fields: Dictionary) -> void:
	_model.fold(event_name, fields)
	_views.on_event(event_name, fields)


func _spawn(item: int, kind: StringName) -> void:
	_event(&"ItemSpawned", {"item": item, "kind": kind, "position": Vector3(1, 0, 0)})


func _pick_up(peer: int, item: int) -> void:
	_event(&"ItemPickedUp", {"peer": peer, "item": item})


func _place(item: int, cause: StringName) -> void:
	_event(&"ItemPlaced", {"item": item, "position": Vector3(1, 0, 0), "cause": cause})


func _rig() -> CharacterRig:
	return _views.body_of(PEER).character()


func _shot_clip() -> StringName:
	var root := _rig().tree.tree_root as AnimationNodeBlendTree
	return (root.get_node(&"shot_clip") as AnimationNodeAnimation).animation
