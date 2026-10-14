extends GdUnitTestSuite
## The raise hint over a ragdoll (the knockdown ADR's §7 and §9, ARCHITECTURE §4.7.9), over the
## loopback: the host's player is knocked down and its ragdoll comes to rest on the joiner's
## screen. Aimed at a limb of the ragdoll, the joiner's hint names its peer; aimed past it, none.
## The reach is measured to the peer's interpolated point, never to the part the ray hit: standing
## past the hint's reach of the point, with the ragdoll's near end within it, the hint names none;
## with the ragdoll's pose held off its point, the hint follows the point, not the pose (728d).

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const RESPAWN_S := 2.0
## Long enough a knockdown for the whole test.
const KNOCKDOWN_S := 60.0
## Physics frames the ragdoll gets to come to rest.
const REST_FRAMES := 120

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	_pair.mode.player_rules.knockdown_s = KNOCKDOWN_S
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_the_raise_hint_names_a_ragdolls_peer_at_a_limb_and_none_past_it_or_out_of_reach() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var model := _pair.client.client().model
	var downed := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var life := _pair.client.life()
	var avatars := _pair.client.avatars()
	_pair.knock_down(_pair.host)
	var drawn := func() -> bool:
		return (
			model.life_of(downed) == ClientModel.Life.DOWNED and avatars.ragdoll_of(downed) != null
		)
	assert_bool(await _until(drawn)).is_true()
	await _pair.frames(REST_FRAMES)
	var ragdoll := avatars.ragdoll_of(downed)
	var point := ragdoll.held_point()
	var rules := _pair.mode.player_rules
	# The capsule's axis along the floor, from the point to one end.
	var axis := ragdoll.global_basis.y
	axis.y = 0.0
	assert_float(axis.length()).is_greater(0.9)
	axis = axis.normalized()
	var limb_reach := rules.capsule_height_m * 0.5 - rules.capsule_radius_m
	var hint := LifeView.raise_hint_reach_of(_pair.mode)
	# Out of reach of the point, the near end within it: the hint measures to the point.
	assert_bool(await _pair.walk_to(player, point + axis * (hint + 0.35))).is_true()
	await _pair.frames(10)
	var limb := ragdoll.global_position + ragdoll.global_basis.y.normalized() * limb_reach
	if (
		limb.distance_to(player.global_position)
		> ragdoll.global_position.distance_to(player.global_position)
	):
		limb = ragdoll.global_position - ragdoll.global_basis.y.normalized() * limb_reach
	assert_float(player.global_position.distance_to(point)).is_greater(hint)
	(
		assert_float(
			Vector2(limb.x, limb.z).distance_to(
				Vector2(player.global_position.x, player.global_position.z)
			)
		)
		. is_less(hint)
	)
	_pair.aim(player, limb)
	await _pair.frames(2)
	assert_int(life.raise_target()).is_equal(0)
	# Within reach, aimed at the limb: its peer.
	assert_bool(await _pair.walk_to(player, point + axis * (hint - 0.5))).is_true()
	await _pair.frames(10)
	_pair.aim(player, limb)
	await _pair.frames(2)
	assert_int(life.raise_target()).is_equal(downed)
	# Aimed past it, at the floor beside the ragdoll: none.
	var beside := point + axis.cross(Vector3.UP) * 1.5
	_pair.aim(player, beside)
	await _pair.frames(2)
	assert_int(life.raise_target()).is_equal(0)
	await _pair.stop()


## 728d: the reach goes to the held point, never to the tumbling pose. The ragdoll is held (frozen)
## off its point, within SNAP_M: near the point and far from the pose the hint names its peer; far
## from the point and near the pose it names none.
func test_the_raise_reach_goes_to_the_held_point_never_to_the_ragdolls_pose() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var model := _pair.client.client().model
	var downed := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var life := _pair.client.life()
	var avatars := _pair.client.avatars()
	_pair.knock_down(_pair.host)
	var drawn := func() -> bool:
		return (
			model.life_of(downed) == ClientModel.Life.DOWNED and avatars.ragdoll_of(downed) != null
		)
	assert_bool(await _until(drawn)).is_true()
	await _pair.frames(REST_FRAMES)
	var ragdoll := avatars.ragdoll_of(downed)
	var point := ragdoll.held_point()
	var axis := ragdoll.global_basis.y
	axis.y = 0.0
	axis = axis.normalized()
	var hint := LifeView.raise_hint_reach_of(_pair.mode)
	# The pose pushed 0.8 m along the axis, within SNAP_M, and kept there.
	var off := 0.8
	assert_float(off).is_less(RagdollView.SNAP_M)
	ragdoll.freeze = true
	var pose := point + axis * off + Vector3.UP * _pair.mode.player_rules.capsule_radius_m
	ragdoll.global_position = pose
	await _pair.frames(5)
	assert_float(ragdoll.global_position.distance_to(pose)).is_less(0.01)
	assert_vector(ragdoll.held_point()).is_equal_approx(point, Vector3.ONE * 0.01)
	# Near the point, on the far side from the pose: its peer.
	assert_bool(await _pair.walk_to(player, point - axis * (hint - 0.3))).is_true()
	await _pair.frames(10)
	assert_float(player.global_position.distance_to(point)).is_less(hint)
	assert_float(player.global_position.distance_to(ragdoll.global_position)).is_greater(hint)
	_pair.aim(player, ragdoll.global_position)
	await _pair.frames(2)
	assert_int(life.raise_target()).is_equal(downed)
	# Past the point, near the pose: none.
	assert_bool(await _pair.walk_to(player, point + axis * (hint + 0.3))).is_true()
	await _pair.frames(10)
	assert_float(player.global_position.distance_to(point)).is_greater(hint)
	assert_float(player.global_position.distance_to(ragdoll.global_position)).is_less(hint)
	_pair.aim(player, ragdoll.global_position)
	await _pair.frames(2)
	assert_int(life.raise_target()).is_equal(0)
	await _pair.stop()


## Waits until `done` holds, at most `frames` physics frames; whether it held.
func _until(done: Callable, frames := 60) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()
