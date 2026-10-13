extends GdUnitTestSuite
## The ragdoll in flight over the loopback (the knockdown ADR's KE7, KE8 and §9, ARCHITECTURE
## §4.7.9), on NetPair.MOTION_LEVEL, the one map where a body moves. A launched joiner's downed
## camera and ears follow its own avatar's point, never the controller held where the knockdown
## found it; the pivot keeps the eye height above the floor below the point in mid-flight and
## stops under the fixture's low slab; the ragdoll's root stays within the snap distance of the
## point in every frame. A dead spectator's camera over a launched target keeps the floor clamp,
## and a raise after the rest stands the joiner at the host's point with its ragdoll gone.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const RESPAWN_S := 2.0
## Long enough a knockdown for each test.
const KNOCKDOWN_S := 60.0
## Up and away: about 1.8 m high at the top, about 5 m away when it lands.
const HIGH_LAUNCH := Vector3(0.0, 6.0, -4.0)
## Along the floor under the fixture's slab, from SLAB_START.
const LOW_LAUNCH := Vector3(6.0, 1.0, 0.0)
## Just short of the slab (x 1.5 to 5.5, z 9 to 13, its underside 1.4 m up): the standing
## controller's capsule clears its edge.
const SLAB_START := Vector3(0.9, 0.0, 11.0)
const SLAB_UNDERSIDE_M := 1.4
## The slab's footprint, shrunk by a margin so the ceiling ray at the point surely meets it.
const SLAB_MIN := Vector2(1.6, 9.1)
const SLAB_MAX := Vector2(5.4, 12.9)
## Physics frames the flights are watched for.
const FLIGHT_FRAMES := 150
## The ragdoll's root may be a frame's motion past the snap distance when a frame reads it.
const SNAP_SLACK_M := 0.25
const EPS := 0.001

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	_pair.mode.player_rules.knockdown_s = KNOCKDOWN_S
	_pair.mode.maps = PackedStringArray([NetPair.MOTION_LEVEL])
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_a_launched_joiners_camera_and_ears_follow_its_avatar_with_the_floor_clamp() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var model := _pair.client.client().model
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var life := _pair.client.life()
	var avatars := _pair.client.avatars()
	var rules := _pair.mode.player_rules
	_pair.knock_down(_pair.client, HIGH_LAUNCH)
	var downed := func() -> bool: return model.life_of(joiner) == ClientModel.Life.DOWNED
	assert_bool(await _until(downed)).is_true()
	var highest := -INF
	var farthest := 0.0
	var followed := 0
	for i: int in FLIGHT_FRAMES:
		await _pair.frames(1)
		var pivot := life.downed_camera().pivot()
		(
			assert_bool(pivot.is_finite())
			. override_failure_message("frame %d: %s" % [i, pivot])
			. is_true()
		)
		var ragdoll := avatars.ragdoll_of(joiner)
		if ragdoll == null:
			continue
		followed += 1
		var point := ragdoll.held_point()
		_assert_over(pivot, point, "frame %d" % i)
		# KE8: never higher than the eye height above the floor (y = 0) below the point.
		(
			assert_float(pivot.y)
			. override_failure_message("frame %d: pivot %s over %s" % [i, pivot, point])
			. is_less_equal(rules.eye_height_m + EPS)
		)
		_assert_held(ragdoll, "frame %d" % i)
		# KE8: the ears at the body's lying head height above the point.
		var ears := life.ears().global_position
		assert_float(ears.y).is_equal_approx(point.y + rules.capsule_radius_m, EPS)
		assert_float(Vector2(ears.x - point.x, ears.z - point.z).length()).is_less_equal(
			rules.eye_height_m - rules.capsule_height_m * 0.5 + EPS
		)
		highest = maxf(highest, point.y)
		farthest = maxf(
			farthest,
			Vector2(point.x, point.z).distance_to(
				Vector2(player.global_position.x, player.global_position.z)
			)
		)
	assert_int(followed).is_greater(FLIGHT_FRAMES / 2)
	# It flew: above the floor clamp's reach, and away from the held controller.
	assert_float(highest).is_greater(1.0)
	assert_float(farthest).is_greater(1.0)
	await _pair.stop()


func test_a_joiner_launched_under_a_low_ceiling_has_its_camera_stop_under_it() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var model := _pair.client.client().model
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var life := _pair.client.life()
	var avatars := _pair.client.avatars()
	assert_bool(await _pair.walk_to(player, SLAB_START)).is_true()
	await _pair.frames(10)
	_pair.knock_down(_pair.client, LOW_LAUNCH)
	var downed := func() -> bool: return model.life_of(joiner) == ClientModel.Life.DOWNED
	assert_bool(await _until(downed)).is_true()
	var under := 0
	var moving_under := 0
	var last := Vector3.INF
	for i: int in FLIGHT_FRAMES:
		await _pair.frames(1)
		var ragdoll := avatars.ragdoll_of(joiner)
		if ragdoll == null:
			continue
		var point := ragdoll.held_point()
		var pivot := life.downed_camera().pivot()
		_assert_over(pivot, point, "frame %d" % i)
		_assert_held(ragdoll, "frame %d" % i)
		var flat := Vector2(point.x, point.z)
		if flat.clamp(SLAB_MIN, SLAB_MAX) == flat:
			under += 1
			if point.distance_to(last) > EPS:
				moving_under += 1
			# KE8: CEILING_MARGIN_M under the slab, where the eye height over the point is above it.
			(
				assert_float(pivot.y)
				. override_failure_message("frame %d: pivot %s under the slab" % [i, pivot])
				. is_less_equal(SLAB_UNDERSIDE_M - DownedCamera.CEILING_MARGIN_M + EPS)
			)
		last = point
	assert_int(under).is_greater(0)
	# The clamp held while the host's body still slid in under the slab.
	assert_int(moving_under).is_greater(0)
	await _pair.stop()


func test_a_spectators_camera_over_a_launched_target_keeps_the_floor_clamp() -> void:
	assert_bool(await _dead_joiner()).is_true()
	var model := _pair.client.client().model
	var target := _pair.peer_of(_pair.host)
	var life := _pair.client.life()
	var avatars := _pair.client.avatars()
	_pair.knock_down(_pair.host, HIGH_LAUNCH)
	var above := func() -> bool:
		return (
			model.life_of(target) == ClientModel.Life.DOWNED
			and life.view() == LifeView.View.SPECTATE_ABOVE
		)
	assert_bool(await _until(above)).is_true()
	var highest := -INF
	for i: int in FLIGHT_FRAMES:
		await _pair.frames(1)
		var body := avatars.body_of(target)
		var pivot := life.downed_camera().pivot()
		_assert_over(pivot, body.global_position, "frame %d" % i)
		(
			assert_float(pivot.y)
			. override_failure_message("frame %d: pivot %s" % [i, pivot])
			. is_less_equal(_pair.mode.player_rules.eye_height_m + EPS)
		)
		highest = maxf(highest, body.global_position.y)
	assert_float(highest).is_greater(1.0)
	await _pair.stop()


func test_a_raise_after_the_rest_stands_the_joiner_at_the_hosts_point() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var model := _pair.client.client().model
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var avatars := _pair.client.avatars()
	_pair.knock_down(_pair.client, HIGH_LAUNCH)
	assert_bool(await _until(func() -> bool: return avatars.ragdoll_of(joiner) != null)).is_true()
	# At rest: the point has not moved for a second (the host's rest time and its StopBody).
	var still := 0
	var last := Vector3.INF
	for i: int in FLIGHT_FRAMES * 2:
		await _pair.frames(1)
		var now := avatars.point_of(joiner, Vector3.INF)
		still = still + 1 if now.distance_to(last) < EPS else 0
		last = now
		if still >= 60:
			break
	assert_int(still).is_greater_equal(60)
	var rested := last
	(
		assert_float(
			Vector2(rested.x, rested.z).distance_to(
				Vector2(player.global_position.x, player.global_position.z)
			)
		)
		. is_greater(1.0)
	)
	# The host walks up to the body as its own client draws it and raises it.
	var raiser := _pair.host.player()
	var raiser_life := _pair.host.life()
	var drawn := _pair.host.avatars().ragdoll_of(joiner)
	assert_object(drawn).is_not_null()
	assert_bool(await _pair.walk_to(raiser, rested + Vector3(1.2, 0.0, 0.0))).is_true()
	await _pair.frames(10)
	_pair.aim(raiser, drawn.lying_centre())
	await _pair.frames(2)
	assert_int(raiser_life.raise_target()).is_equal(joiner)
	raiser_life.press_raise()
	var raised := func() -> bool: return model.life_of(joiner) == ClientModel.Life.ALIVE
	assert_bool(await _until(raised, 400)).is_true()
	raiser_life.release_raise()
	await _pair.frames(10)
	assert_object(avatars.ragdoll_of(joiner)).is_null()
	(
		assert_float(
			Vector2(player.global_position.x, player.global_position.z).distance_to(
				Vector2(rested.x, rested.z)
			)
		)
		. is_less(0.05)
	)
	assert_bool(player.is_downed()).is_false()
	await _pair.stop()


## The joiner dead on MOTION_LEVEL (knocked down where it stands, then given up), spectating the
## host with its eyes.
func _dead_joiner() -> bool:
	if not await _pair.start() or not await _pair.to_round():
		return false
	var joiner := _pair.peer_of(_pair.client)
	var session := _pair.client.client()
	var life := _pair.client.life()
	_pair.knock_down(_pair.client)
	if not await _until(func() -> bool: return _pair.client.player().is_downed()):
		return false
	life.give_up()
	var dead := func() -> bool: return session.model.life_of(joiner) == ClientModel.Life.DEAD
	if not await _until(dead):
		return false
	var eyes := func() -> bool: return life.view() == LifeView.View.SPECTATE_EYES
	return await _until(eyes)


## The pivot straight over `point` (KE8): only its height is clamped.
func _assert_over(pivot: Vector3, point: Vector3, at: String) -> void:
	(
		assert_float(Vector2(pivot.x, pivot.z).distance_to(Vector2(point.x, point.z)))
		. override_failure_message("%s: pivot %s over %s" % [at, pivot, point])
		. is_less(EPS)
	)


## KE7: the ragdoll's root within the snap distance of the lying centre over its point.
func _assert_held(ragdoll: RagdollView, at: String) -> void:
	var off := ragdoll.global_position.distance_to(ragdoll.lying_centre())
	assert_float(off).override_failure_message("%s: the root %.3f m off" % [at, off]).is_less_equal(
		RagdollView.SNAP_M + SNAP_SLACK_M
	)


## Waits until `done` holds, at most `frames` physics frames; whether it held.
func _until(done: Callable, frames := 60) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()
