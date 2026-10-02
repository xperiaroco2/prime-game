extends GdUnitTestSuite
## Spectating through the target's eyes on the network (ARCHITECTURE §4.7, Spectating; #168): a
## host Game and a joined Game over a LoopbackHub (NetPair, with the base mode's life rules). The
## joiner gives up and dies, and spectates the host's player while that player walks and turns.
## Frame after frame the spectate camera is the target's interpolated eye transform: the pose of
## the joiner's own SnapshotBuffer at the tick the avatars were drawn at, the eye height of the
## mode's PlayerRules, the guarded yaw and pitch; it retraces the target's own camera, later by the
## interpolation delay. The target's own meshes are drawn by no camera the spectator uses, and its
## items show as it sees them itself (the hand item in the first-person hand, none at its body),
## until it goes down or the spectator respawns.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const RESPAWN_S := 30.0
## How close the camera must be to the target's eyes, in metres and in the basis's components.
const TOLERANCE := 0.001
## The physics frames the target walks and turns while it is watched.
const WATCHED_FRAMES := 90
## Frames of the target's own camera recorded before the spectate camera is compared with them:
## more than the interpolation delay.
const DELAY_FRAMES := 30
## How close the spectate camera comes to the path of the target's own camera: in metres from the
## nearest segment between two consecutive recorded poses (the target walks about 7 cm a frame, so
## a pose drawn between two physics frames lies on that segment, whatever the render tick's phase),
## and in radians from the look of that segment's nearer end (it turns 1.7 degrees a frame).
const RETRACE_M := 0.01
const RETRACE_RAD := 0.05
## The respawn of the suite that waits for it, in seconds.
const SHORT_RESPAWN_S := 2.0
## The target's items in the spectator's model.
const HAND_ITEM := 90
const BELT_ITEM := 91

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_the_spectate_camera_is_the_targets_interpolated_eye_frame_after_frame() -> void:
	assert_bool(await _dead_joiner()).is_true()
	var life := _pair.client.life()
	var target := _pair.peer_of(_pair.host)
	assert_int(life.target()).is_equal(target)
	var walker := _pair.host.player()
	walker.move_input = Vector2(0.3, 1.0)
	var compared := 0
	for i: int in WATCHED_FRAMES:
		# Turning and nodding as a player does: the yaw on the body, the pitch on the head.
		walker.look(0.03, 0.02 if i < WATCHED_FRAMES / 2 else -0.03)
		await _pair.frames(1)
		assert_int(life.view()).is_equal(LifeView.View.SPECTATE_EYES)
		var camera := life.spectate_camera()
		assert_bool(camera.current).is_true()
		var want := _eye_of(target)
		var got := camera.global_transform
		var where := "frame %d: camera %s, the target's eye %s" % [i, got, want]
		assert_vector(got.origin).override_failure_message(where).is_equal_approx(
			want.origin, Vector3.ONE * TOLERANCE
		)
		for axis: int in 3:
			assert_vector(got.basis[axis]).override_failure_message(where).is_equal_approx(
				want.basis[axis], Vector3.ONE * TOLERANCE
			)
		compared += 1
	walker.move_input = Vector2.ZERO
	assert_int(compared).is_equal(WATCHED_FRAMES)
	# The target did walk and turn while it was watched.
	var moved := _pair.client.avatars().body_of(target).global_position
	assert_float(Vector2(moved.x, moved.z).length()).is_greater(0.5)
	await _pair.stop()


func test_the_spectate_camera_retraces_the_targets_own_camera() -> void:
	# Against the target's own first-person camera on the host's screen, not the spectator's body
	# of it: the spectate camera passes through the very poses the target's camera had, only later
	# by the interpolation delay (§4.7: remote players are drawn that late).
	assert_bool(await _dead_joiner()).is_true()
	var life := _pair.client.life()
	var walker := _pair.host.player()
	walker.move_input = Vector2(0.3, 1.0)
	var truth: Array[Transform3D] = []
	for i: int in WATCHED_FRAMES:
		walker.look(0.03, 0.02 if i < WATCHED_FRAMES / 2 else -0.03)
		await _pair.frames(1)
		truth.append(walker.get_camera().global_transform)
		if i < DELAY_FRAMES:
			continue
		var got := life.spectate_camera().global_transform
		var nearest := truth[0]
		var gap := INF
		for k: int in range(1, truth.size()):
			var a := truth[k - 1]
			var b := truth[k]
			var on := Geometry3D.get_closest_point_to_segment(got.origin, a.origin, b.origin)
			if on.distance_to(got.origin) < gap:
				gap = on.distance_to(got.origin)
				nearest = a if on.distance_to(a.origin) <= on.distance_to(b.origin) else b
		var where := "frame %d: camera %s, the target's nearest %s" % [i, got, nearest]
		assert_float(gap).override_failure_message(where).is_less(RETRACE_M)
		var off := (-nearest.basis.z).angle_to(-got.basis.z)
		assert_float(off).override_failure_message(where).is_less(RETRACE_RAD)
	walker.move_input = Vector2.ZERO
	await _pair.stop()


func test_the_targets_own_meshes_are_drawn_by_no_camera_the_spectator_uses() -> void:
	assert_bool(await _dead_joiner()).is_true()
	var life := _pair.client.life()
	var target := _pair.peer_of(_pair.host)
	var watched := _pair.client.avatars().body_of(target)
	# The target holds a knife and wears another on its belt (folded into the spectator's model as
	# the host's item events would: the fixture level has no items).
	var model := _pair.client.client().model
	model.fold(&"ItemSpawned", {"item": HAND_ITEM, "kind": &"knife", "position": Vector3.ZERO})
	model.fold(&"ItemSpawned", {"item": BELT_ITEM, "kind": &"knife", "position": Vector3.ZERO})
	model.fold(&"ItemPickedUp", {"peer": target, "item": BELT_ITEM})
	model.fold(&"ItemPickedUp", {"peer": target, "item": HAND_ITEM, "belted": BELT_ITEM})
	await _pair.frames(2)
	var spectate := life.spectate_camera()
	assert_bool(_drawn_by(watched, spectate)).is_false()
	# As the target sees itself: its hand item in the first-person hand, neither item at its body.
	var views := _pair.client.items().items
	assert_str(String(life.spectate_hand().shown_kind())).is_equal("knife")
	assert_bool(life.spectate_hand().is_visible_in_tree()).is_true()
	for item_id: int in [HAND_ITEM, BELT_ITEM]:
		assert_bool(views.view_of(item_id).is_look_shown()).is_false()
	# The target goes down: watched from above its body, which is drawn again, its items with it.
	_pair.knock_down(_pair.host)
	var above := func() -> bool: return life.view() == LifeView.View.SPECTATE_ABOVE
	assert_bool(await _until(above)).is_true()
	await _pair.frames(1)
	assert_bool(_drawn_by(watched, life.downed_camera().camera())).is_true()
	assert_str(String(life.spectate_hand().shown_kind())).is_empty()
	for item_id: int in [HAND_ITEM, BELT_ITEM]:
		assert_bool(views.view_of(item_id).is_look_shown()).is_true()
	await _pair.stop()


func test_a_respawned_spectator_sees_the_target_it_watched_again() -> void:
	_pair.mode.player_rules.respawn_s = SHORT_RESPAWN_S
	assert_bool(await _dead_joiner()).is_true()
	var life := _pair.client.life()
	var player := _pair.client.player()
	var watched := _pair.client.avatars().body_of(_pair.peer_of(_pair.host))
	assert_bool(_drawn_by(watched, life.spectate_camera())).is_false()
	var joiner := _pair.peer_of(_pair.client)
	var living := func() -> bool: return _pair.client.client().model.is_alive(joiner)
	assert_bool(await _until(living, 240)).is_true()
	await _pair.frames(2)
	assert_int(life.view()).is_equal(LifeView.View.FIRST_PERSON)
	assert_bool(_drawn_by(watched, player.get_camera())).is_true()
	assert_str(String(life.spectate_hand().shown_kind())).is_empty()
	await _pair.stop()


## Knocks the joiner down, makes it give up, and waits until it is dead and spectating; false when
## it never got there.
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


## The target's interpolated eye transform on the spectator's client: the pose of its own
## SnapshotBuffer at the tick the avatars were drawn at in this physics frame, the eye height of
## the mode's PlayerRules above the feet, the guarded yaw and pitch.
func _eye_of(peer: int) -> Transform3D:
	var avatars := _pair.client.avatars()
	var pose := avatars.buffer.pose_of(peer, avatars.drawn_at())
	var eye := pose.position + Vector3.UP * _pair.mode.player_rules.eye_height_m
	return Transform3D(Basis.from_euler(Vector3(pose.pitch, pose.yaw, 0.0)), eye)


## Whether any mesh of `body` would be drawn by `camera`: a visible mesh on a render layer of the
## camera's cull mask.
func _drawn_by(body: RemotePlayerBody, camera: Camera3D) -> bool:
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree() and (mesh.layers & camera.cull_mask) != 0:
			return true
	return false


## Waits until `done` holds, at most `frames` physics frames; whether it held.
func _until(done: Callable, frames := 30) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()
