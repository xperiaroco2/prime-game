extends GdUnitTestSuite
## A ghost in the first-person controller over real physics steps (Jolt, headless): it moves like
## the living (gravity, floor, steps, slopes, jumps, walls) at `ghost_speed_factor` times their
## speeds, stamina never limits it, and it passes through players (the engineer's correction of
## 2026-09-30, #46: ghosts do not fly). Forward is -Z. Each test builds its own small world.

const SPEED_TOLERANCE := 0.05
const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")

var _tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_ghost_is_on_the_ghost_layer_and_collides_with_the_level_only() -> void:
	var player := _world.add_player(Vector3.ZERO)
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD | PhysicsLayers.LIVING)
	player.ghost = true
	assert_int(player.collision_layer).is_equal(PhysicsLayers.GHOSTS)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD)
	player.ghost = false
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD | PhysicsLayers.LIVING)


func test_ghost_speed_factor_is_the_engineers_1_3() -> void:
	# The engineer's decision of 2026-09-30 (#46); the base speeds stay placeholders.
	assert_float(_tuning.ghost_speed_factor).is_equal_approx(1.3, 0.0001)


func test_ghost_walks_on_the_floor_at_the_factor_times_walk_speed() -> void:
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(player)
	assert_float(speed).is_equal_approx(
		_tuning.walk_speed * _tuning.ghost_speed_factor, SPEED_TOLERANCE
	)
	assert_bool(player.is_sprinting()).is_false()
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_ghost_falls_like_the_living() -> void:
	var living := _world.add_player(Vector3(-3.0, 2.0, 0.0))
	var ghost := _world.add_ghost(Vector3(3.0, 2.0, 0.0))
	for i: int in 45:
		await _world.frames(1)
		assert_float(ghost.global_position.y).is_equal_approx(living.global_position.y, 0.0001)
	assert_float(ghost.global_position.y).is_equal_approx(0.0, 0.01)
	assert_bool(ghost.is_on_floor()).is_true()


func test_ghost_looking_up_walks_on_the_floor() -> void:
	var player := _world.add_ghost(Vector3.ZERO)
	player.look(0.0, deg_to_rad(60.0))
	player.move_input = Vector2(0.0, 1.0)
	var highest := 0.0
	for i: int in 30:
		await _world.frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(0.01)
	assert_float(player.global_position.z).is_less(-1.0)


func test_ghost_jumps_no_higher_than_the_living_however_often_it_asks() -> void:
	var player := _world.add_ghost(Vector3.ZERO)
	await _world.frames(10)
	var peak := 0.0
	for i: int in 90:
		player.jump_requested = true
		await _world.frames(1)
		peak = maxf(peak, player.global_position.y)
	assert_float(peak).is_between(_tuning.jump_height - 0.02, _tuning.jump_height + 0.005)


func test_ghost_sprints_at_the_factor_times_sprint_speed_and_jumps_with_no_stamina() -> void:
	var player := _world.add_ghost(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).stamina = 0.0
	player.jump_requested = true
	var peak: float = await _world.peak_height(player, 60)
	assert_float(peak).is_greater(_tuning.jump_height - 0.02)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _world.measure_speed(player)
	assert_float(speed).is_equal_approx(
		_tuning.sprint_speed * _tuning.ghost_speed_factor, SPEED_TOLERANCE
	)
	assert_bool(player.is_sprinting()).is_true()


func test_ghost_stamina_neither_spends_nor_regenerates() -> void:
	var player := _world.add_ghost(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).stamina = 50.0
	player.jump_requested = true
	await _world.frames(60)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	await _world.frames(30)
	player.sprint_held = false
	await _world.frames(30)
	assert_float(player.stamina.get_stamina()).is_equal(50.0)


func test_ghost_sprints_up_stairs_like_the_living() -> void:
	var steps := 5
	_world.add_stairs(steps)
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var lowest_eye := _tuning.eye_height
	# Half a second at the ghost's sprint speed ends on the last, long tread, not past it.
	for i: int in 30:
		await _world.frames(1)
		var eye := player.get_camera().global_position.y - player.global_position.y
		lowest_eye = minf(lowest_eye, eye)
	assert_float(player.global_position.y).is_equal_approx(_tuning.step_height * steps, 0.01)
	assert_bool(player.is_on_floor()).is_true()
	assert_float(lowest_eye).is_greater_equal(_tuning.eye_height - _tuning.step_height - 0.001)


func test_ghost_stops_at_a_ledge_above_step_height() -> void:
	var height := _tuning.step_height + 0.2
	_world.add_box(Vector3(0.0, height * 0.5, -3.0), Vector3(4.0, height, 2.0))
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(60)
	assert_float(player.global_position.y).is_less(0.01)
	assert_float(player.global_position.z).is_greater(-2.0 + _tuning.capsule_radius - 0.02)


func test_ghost_cannot_jump_onto_a_ledge_the_living_cannot() -> void:
	# Above the jump height plus a landing on the ledge's corner (ARCHITECTURE §7).
	var height := _tuning.jump_height + 0.3
	_world.add_box(Vector3(0.0, height * 0.5, -3.0), Vector3(4.0, height, 2.0))
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var highest := 0.0
	for i: int in 120:
		player.jump_requested = true
		await _world.frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(_tuning.jump_height + 0.005)
	assert_float(player.global_position.z).is_greater(-2.0 + _tuning.capsule_radius - 0.02)


func test_ghost_sprints_up_a_ramp_at_the_steepest_walkable_angle_smoothly() -> void:
	# The slope, not a ledge's lift, carries the body at the ghost's faster sprint too: on the
	# floor every step, no rise beyond the slope's, and the view at eye height.
	var angle := deg_to_rad(44.0)
	_world.add_ramp(angle, -1.0)
	var player := _world.add_ghost(Vector3.ZERO)
	assert_float(angle).is_less(player.floor_max_angle)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	await _world.frames(15)
	var off_floor := 0
	var largest_rise := 0.0
	var eye_off := 0.0
	var last_y := player.global_position.y
	for i: int in 25:
		await _world.frames(1)
		if not player.is_on_floor():
			off_floor += 1
		largest_rise = maxf(largest_rise, player.global_position.y - last_y)
		last_y = player.global_position.y
		# A false step-up lowers the view; the slope never does.
		var eye := player.get_camera().global_position.y - last_y
		eye_off = maxf(eye_off, absf(eye - _tuning.eye_height))
	assert_int(off_floor).is_equal(0)
	assert_float(eye_off).is_less(0.001)
	var speed := _tuning.sprint_speed * _tuning.ghost_speed_factor
	var slope_rise := speed * tan(angle) / Engine.physics_ticks_per_second
	assert_float(largest_rise).is_less(slope_rise * 1.05)
	assert_float(last_y).is_greater(0.5)


func test_ghost_steps_over_a_low_round_pipe() -> void:
	_world.add_pipe(0.1, -2.0)
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	await _world.frames(40)
	assert_float(player.global_position.z).is_less(-3.0)
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)


func test_ghost_does_not_climb_a_slope_too_steep_to_walk() -> void:
	_world.add_ramp(deg_to_rad(50.0), -1.0)
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var highest := 0.0
	for i: int in 120:
		await _world.frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(0.05)


func test_ghost_passes_through_players() -> void:
	var other := _world.add_remote(Vector3(0.0, 0.0, -2.0))
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(60)
	assert_float(player.global_position.z).is_less(-4.0)
	assert_float(player.global_position.y).is_less(0.01)
	assert_vector(other.global_position).is_equal(Vector3(0.0, 0.0, -2.0))


func test_ghost_is_stopped_by_walls() -> void:
	_world.add_box(Vector3(0.0, 1.5, -3.0), Vector3(6.0, 3.0, 0.2))
	var player := _world.add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(60)
	assert_float(player.global_position.z).is_greater(-3.0 + 0.1 + _tuning.capsule_radius - 0.02)


func test_turning_back_into_the_living_limits_it_by_stamina_again() -> void:
	var player := _world.add_ghost(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).stamina = 0.0
	player.ghost = false
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _world.measure_speed(player, 5, 10)
	assert_float(speed).is_equal_approx(_tuning.walk_speed, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()
