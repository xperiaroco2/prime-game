extends GdUnitTestSuite
## The real PlayerController on the network (ARCHITECTURE §4.7 and §7, M4-7): a joined Game's
## player walks, sprints, jumps and climbs steps on a fixture level, claiming through its
## ClientSession over a LoopbackHub to the host's HostSession, which checks every claim
## (MovementRule) against its own copy of the level. Honest play is corrected 0 times; a placement
## the test forces on the controller is corrected once, and play goes on without another. The host
## sees the joiner where it walked, through the snapshots and SnapshotBuffer.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The top of the fixture's stairs.
const TOP_Y := 1.2

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_walking_sprinting_jumping_and_steps_are_never_corrected() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	assert_vector(player.global_position).is_equal_approx(Vector3(0, 0, -2), Vector3.ONE * 0.01)
	# A quarter turn to the right: toward the stairs along +X. Walk, then sprint up the steps.
	player.look(-PI / 2.0, 0.0)
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(60)
	assert_float(player.global_position.x).is_between(4.0, 5.0)
	player.sprint_held = true
	await _pair.frames(60)
	assert_bool(player.is_sprinting()).is_true()
	assert_float(player.global_position.y).is_equal_approx(TOP_Y, 0.02)
	assert_float(player.global_position.x).is_greater(10.0)
	# Turn back, jump on the top while looking down a little, then walk down the steps.
	player.sprint_held = false
	player.move_input = Vector2.ZERO
	player.look(PI, -0.4)
	await _pair.frames(10)
	player.jump_requested = true
	await _pair.frames(70)
	assert_float(player.global_position.y).is_equal_approx(TOP_Y, 0.02)
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(150)
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.02)
	assert_float(player.global_position.x).is_less(6.0)
	# Strafe and jump on the floor, then stand.
	player.move_input = Vector2(1.0, 0.0)
	player.jump_requested = true
	await _pair.frames(60)
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_int(_pair.client.client().corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	# The host draws the joiner where it stands, from the snapshots.
	var seen := _pair.host.avatars().body_of(_pair.peer_of(_pair.client))
	assert_object(seen).is_not_null()
	assert_vector(seen.global_position).is_equal_approx(player.global_position, Vector3.ONE * 0.05)
	await _pair.stop()


func test_a_forced_placement_is_corrected_once_and_play_goes_on() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
	var stood := player.global_position
	# The test puts the controller 5 m away at once: no walk covers that in a tick.
	player.teleport(Transform3D(player.global_basis, stood + Vector3(5.0, 0.0, 0.0)))
	for i: int in 30:
		if session.corrections > 0:
			break
		await _pair.frames(1)
	assert_int(session.corrections).is_equal(1)
	# The Correction put it back where the host last accepted it.
	await _pair.frames(1)
	assert_vector(player.global_position).is_equal_approx(stood, Vector3.ONE * 0.05)
	# Play goes on under the new epoch: walking and a jump draw no further Correction.
	player.move_input = Vector2(0.0, -1.0)
	player.jump_requested = true
	await _pair.frames(90)
	player.move_input = Vector2.ZERO
	await _pair.frames(20)
	assert_float(player.global_position.z).is_greater(stood.z + 3.0)
	assert_int(session.corrections).is_equal(1)
	await _pair.stop()
