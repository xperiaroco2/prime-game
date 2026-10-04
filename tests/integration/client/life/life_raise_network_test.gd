extends GdUnitTestSuite
## E at the first raise hint while walking in (#352, as #319's pick-up; ARCHITECTURE §4.7,
## Interactions, and §7.1): the host's player is knocked down, and a joined Game's player walks at
## its body, aiming at it, and the moment its LifeView offers the raise (raise_target()) it stops
## and presses E, as a player would. The host measures the raise's TargetInReach from the feet of
## the last MoveClaim it accepted, which trails the feet the hint measures from (claims go at
## 20 Hz against 60 Hz physics, and a claim carries the step before it); the hint's margin
## (TargetChoice.HINT_MARGIN_S, through LifeView.raise_hint_reach_of) covers that, so the host
## starts every such raise: a RaiseStarted, never a Rejected. Three walk-ins from 3 m, from three
## sides, so the first frame of the hint falls on different steps of the claim interval; each
## raise is let go before the next. On an even clock and on one that stands still and then jumps
## (NetPair.uneven).

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The respawn NetPair.with_life() wants; nobody dies here.
const RESPAWN_S := 2.0
## Long enough a knockdown for every walk-in (the raise pauses it only while it runs).
const KNOCKDOWN_S := 60.0
## Where each walk in starts: this far from the body, on these sides of it.
const START_M := 3.0
const SIDES: Array[Vector3] = [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
## The most physics frames a walk takes.
const WALK_FRAMES := 600
## The most physics frames the host's RaiseStarted or RaiseStopped takes to arrive.
const ANSWER_FRAMES := 30

var _pair: NetPair
var _rejected: Array[StringName] = []


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	_pair.mode.player_rules.knockdown_s = KNOCKDOWN_S
	add_child(_pair)
	_rejected.clear()


func after_test() -> void:
	_pair.free()


func test_e_at_the_first_raise_hint_while_walking_in_starts_the_raise() -> void:
	await _walk_in_from_every_side()


func test_e_at_the_first_raise_hint_on_an_uneven_clock_starts_the_raise() -> void:
	_pair.uneven = true
	await _walk_in_from_every_side()


func _walk_in_from_every_side() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var session := _pair.client.client()
	session.event_received.connect(_on_event)
	var model := session.model
	var joiner := _pair.peer_of(_pair.client)
	var downed := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var life := _pair.client.life()
	_pair.knock_down(_pair.host)
	var lying := func() -> bool:
		return (
			model.life_of(downed) == ClientModel.Life.DOWNED
			and _pair.client.avatars().body_of(downed) != null
		)
	assert_bool(await _until(lying)).is_true()
	# Let the snapshots catch up with the lying body before its position is read.
	await _pair.frames(20)
	var at := _pair.client.avatars().body_of(downed).global_position
	var hint := LifeView.raise_hint_reach_of(_pair.mode)
	for side: Vector3 in SIDES:
		assert_bool(await _walk_to(player, at + side * START_M)).is_true()
		await _pair.frames(10)
		var feet := await _walk_in(player, life, downed, at)
		# The hint first showed at its own edge, inside the host's reach by the margin.
		(
			assert_float(Vector2(feet.x - at.x, feet.z - at.z).length())
			. override_failure_message("from %s: the hint showed at %s" % [side, feet])
			. is_between(hint - 0.1, hint)
		)
		_rejected.clear()
		life.press_raise()
		var answered := func() -> bool:
			return model.raiser_of(downed) == joiner or not _rejected.is_empty()
		await _until(answered, ANSWER_FRAMES)
		(
			assert_array(_rejected)
			. override_failure_message("from %s: %s" % [side, _rejected])
			. is_empty()
		)
		assert_int(model.raiser_of(downed)).is_equal(joiner)
		# Let go before the raise completes; the next walk-in raises it afresh.
		life.release_raise()
		var stopped := func() -> bool: return model.raiser_of(downed) == 0
		assert_bool(await _until(stopped, ANSWER_FRAMES)).is_true()
	assert_int(session.corrections).is_equal(0)
	await _pair.stop()


## Walks `player` at the downed `peer` lying at `at`, aiming at its body every frame, until `life`
## offers its raise; then stops and returns where its feet were when the hint showed.
func _walk_in(player: PlayerController, life: LifeView, peer: int, at: Vector3) -> Vector3:
	var middle := at + Vector3.UP * _pair.mode.player_rules.capsule_radius_m
	for i: int in WALK_FRAMES:
		await _pair.frames(1)
		if life.raise_target() == peer:
			player.move_input = Vector2.ZERO
			return player.global_position
		_aim(player, middle)
		player.move_input = Vector2(0.0, 1.0)
	player.move_input = Vector2.ZERO
	return Vector3.INF


## Turns `player`'s camera at `point`.
func _aim(player: PlayerController, point: Vector3) -> void:
	var eye := player.get_camera().global_position
	var to := point - eye
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var current_pitch := player.get_camera().get_parent_node_3d().rotation.x
	player.look(angle_difference(player.rotation.y, yaw), pitch - current_pitch)


## Walks `player` toward `target` on the floor, turning to it every frame; false when it is not
## within 0.2 m after WALK_FRAMES frames. It stops giving input once there.
func _walk_to(player: PlayerController, target: Vector3) -> bool:
	for i: int in WALK_FRAMES:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < 0.2:
			player.move_input = Vector2.ZERO
			return true
		player.look(angle_difference(player.rotation.y, atan2(-to.x, -to.z)), 0.0)
		player.move_input = Vector2(0.0, 1.0)
		await _pair.frames(1)
	player.move_input = Vector2.ZERO
	return false


## Waits until `done` holds, at most `frames` physics frames; whether it held.
func _until(done: Callable, frames := 30) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()


func _on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"Rejected":
		_rejected.append(fields.get("reason", &"") as StringName)
