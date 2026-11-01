extends GdUnitTestSuite
## PlayerController.face (#1522): a placement on a marker with a facing (the Correction's facing,
## ClientSession.faced; a joiner's Welcome, Game) turns the body to the facing's yaw and levels the
## head (look_level, #191, #240), the dead too (End -> Lobby places a player who died in the round),
## while a zero or vertical facing (every Correction that is no placement, a marker with none)
## keeps the look. Forward is -Z. Each test builds its own small world.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const EPS := 0.0001

var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_a_facing_turns_the_body_to_its_yaw_and_levels_the_head() -> void:
	var player := _world.add_player(Vector3.ZERO)
	await _world.frames(1)
	player.look(0.7, 0.9)
	assert_float(_pitch(player)).is_equal_approx(0.9, EPS)
	# The lobby's window: south, +z, a yaw of PI.
	player.face(Vector3.BACK)
	assert_float(angle_difference(player.rotation.y, PI)).is_equal_approx(0.0, EPS)
	assert_float(_pitch(player)).is_equal_approx(0.0, EPS)
	assert_vector(player.look_vector()).is_equal_approx(Vector3.BACK, Vector3.ONE * EPS)
	# East, +x: a yaw of -PI / 2. A facing that is not level turns by its level part alone.
	player.face(Vector3(2.0, 1.0, 0.0))
	assert_float(angle_difference(player.rotation.y, -PI / 2.0)).is_equal_approx(0.0, EPS)
	assert_vector(player.look_vector()).is_equal_approx(Vector3.RIGHT, Vector3.ONE * EPS)


func test_a_zero_or_vertical_facing_keeps_the_look() -> void:
	var player := _world.add_player(Vector3.ZERO)
	await _world.frames(1)
	player.look(0.7, 0.9)
	var yaw := player.rotation.y
	for facing: Vector3 in [Vector3.ZERO, Vector3.UP, Vector3.DOWN]:
		player.face(facing)
		assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, EPS)
		assert_float(_pitch(player)).is_equal_approx(0.9, EPS)


func test_the_dead_and_the_downed_turn_to_a_facing() -> void:
	var downed := _world.add_downed(Vector3.ZERO)
	await _world.frames(1)
	downed.look(0.7, 0.9)
	downed.face(Vector3.LEFT)
	assert_float(angle_difference(downed.rotation.y, PI / 2.0)).is_equal_approx(0.0, EPS)
	assert_float(_pitch(downed)).is_equal_approx(0.0, EPS)
	# Dead, the mouse turns nothing (look), but a placement turns the hidden body.
	downed.look(0.0, 0.6)
	downed.set_life(ClientModel.Life.DEAD)
	await _world.frames(1)
	downed.look(1.0, 0.0)
	assert_float(angle_difference(downed.rotation.y, PI / 2.0)).is_equal_approx(0.0, EPS)
	downed.face(Vector3.BACK)
	assert_float(angle_difference(downed.rotation.y, PI)).is_equal_approx(0.0, EPS)
	assert_float(_pitch(downed)).is_equal_approx(0.0, EPS)


func _pitch(player: PlayerController) -> float:
	return player.get_camera().get_parent_node_3d().rotation.x
