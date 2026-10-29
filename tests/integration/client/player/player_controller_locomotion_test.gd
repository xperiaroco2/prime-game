extends GdUnitTestSuite
## The own move's direction caps and ramp (#1334, art #196) over real physics steps (Jolt,
## headless): with the mode's side_speed_mps and back_speed_mps a strafe and a backpedal are
## capped (a forward diagonal's sideways part only), a backpedal never enters the sprint state (no
## stamina for no speed), and PlayerTuning.accel_seconds eases a start and a stop.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const SPEED_TOLERANCE := 0.05
const SIDE := 3.0
const BACK := 2.0

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld


func before_test() -> void:
	_rules.side_speed_mps = SIDE
	_rules.back_speed_mps = BACK
	_world = PlayerTestWorld.new()
	_world.rules = _rules
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_a_strafe_is_capped_at_the_side_speed() -> void:
	var player := await _player(0.0)
	player.move_input = Vector2(1.0, 0.0)
	assert_float(await _world.measure_speed(player, 4, 30)).is_equal_approx(SIDE, SPEED_TOLERANCE)


func test_a_backpedal_is_capped_at_the_back_speed_even_sprinting() -> void:
	var player := await _player(0.0)
	player.move_input = Vector2(0.0, -1.0)
	assert_float(await _world.measure_speed(player, 4, 30)).is_equal_approx(BACK, SPEED_TOLERANCE)
	player.sprint_held = true
	var stamina := _world.stand_in(player).stamina
	assert_float(await _world.measure_speed(player, 4, 30)).is_equal_approx(BACK, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()
	assert_int(_world.stand_in(player).stamina).is_greater_equal(stamina)
	player.sprint_held = false


func test_a_back_diagonal_is_capped_at_the_back_speed() -> void:
	var player := await _player(0.0)
	player.move_input = Vector2(1.0, -1.0).normalized()
	assert_float(await _world.measure_speed(player, 4, 30)).is_equal_approx(BACK, SPEED_TOLERANCE)


func test_a_forward_diagonal_caps_only_its_sideways_part() -> void:
	var player := await _player(0.0)
	player.move_input = Vector2(1.0, 1.0).normalized()
	# Its sideways part is sin(45 deg) of the speed: 3.0 / 0.707 = 4.24 m/s, below the walk's 4.5.
	var expected := SIDE / sin(PI / 4.0)
	assert_float(await _world.measure_speed(player, 4, 30)).is_equal_approx(
		expected, SPEED_TOLERANCE
	)
	player.move_input = Vector2(0.0, 1.0)
	assert_float(await _world.measure_speed(player, 4, 30)).is_equal_approx(
		_rules.walk_speed_mps, SPEED_TOLERANCE
	)


func test_a_start_and_a_stop_take_the_accel_seconds() -> void:
	var player := await _player(0.2)
	player.move_input = Vector2(0.0, 1.0)
	# Halfway through the ramp: about half the walk; after it, the walk.
	await _world.frames(6)
	assert_float(_flat(player.velocity)).is_between(
		0.3 * _rules.walk_speed_mps, 0.7 * _rules.walk_speed_mps
	)
	await _world.frames(10)
	assert_float(_flat(player.velocity)).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)
	player.move_input = Vector2.ZERO
	await _world.frames(6)
	assert_float(_flat(player.velocity)).is_between(
		0.3 * _rules.walk_speed_mps, 0.7 * _rules.walk_speed_mps
	)
	await _world.frames(10)
	assert_float(_flat(player.velocity)).is_equal_approx(0.0, 0.001)


func test_a_stop_holding_sprint_coasts_no_faster_than_the_walk() -> void:
	# The host allows a tick without own movement only the walk's travel (MovementRule
	# _allowed_travel): the coast from a sprint starts at the walk speed at most.
	var player := await _player(0.2)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	await _world.frames(30)
	assert_float(_flat(player.velocity)).is_equal_approx(_rules.sprint_speed_mps, SPEED_TOLERANCE)
	player.move_input = Vector2.ZERO
	await _world.frames(1)
	assert_float(_flat(player.velocity)).is_less_equal(_rules.walk_speed_mps)
	assert_float(_flat(player.velocity)).is_greater(0.0)
	player.sprint_held = false


func test_a_cap_s_drop_eases_over_the_accel_seconds() -> void:
	# From the walk to a strafe: the drive eases down to the side cap, no jump in one frame (the
	# turn from (0, 4.5) to (3, 0) at 3.0 / 0.2 m/s^2 takes about 22 frames).
	var player := await _player(0.2)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(20)
	assert_float(_flat(player.velocity)).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)
	player.move_input = Vector2(1.0, 0.0)
	await _world.frames(1)
	assert_float(_flat(player.velocity)).is_greater(SIDE + 0.5)
	await _world.frames(30)
	assert_float(_flat(player.velocity)).is_equal_approx(SIDE, SPEED_TOLERANCE)


func test_no_accel_seconds_moves_at_once() -> void:
	var player := await _player(0.0)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(1)
	assert_float(_flat(player.velocity)).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)


## A player on the floor with `accel_seconds` on a copy of the shipped tuning.
func _player(accel_seconds: float) -> PlayerController:
	var player := _world.add_player(Vector3.ZERO)
	player.tuning = player.tuning.duplicate() as PlayerTuning
	player.tuning.accel_seconds = accel_seconds
	await _world.frames(3)
	return player


func _flat(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()
