extends GdUnitTestSuite
## The first-person controller over real physics steps (Jolt, headless): speeds, a jump's height,
## stamina gating, steps, pushing apart and ghost flight. Forward is -Z. Each test builds its own
## small world under `_world`, freed after the test.

const PLAYER_SCENE := preload("res://client/player/player.tscn")
const REMOTE_SCENE := preload("res://client/player/remote_player_body.tscn")
const SPEED_TOLERANCE := 0.05

var _tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
var _world: Node3D


func before_test() -> void:
	_world = Node3D.new()
	add_child(_world)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))


func after_test() -> void:
	_world.free()


func test_body_and_eyes_come_from_the_tuning() -> void:
	var player := _add_player(Vector3.ZERO)
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape.shape as CapsuleShape3D
	assert_float(capsule.radius).is_equal_approx(_tuning.capsule_radius, 0.0001)
	assert_float(capsule.height).is_equal_approx(_tuning.capsule_height, 0.0001)
	assert_float(player.get_camera().global_position.y).is_equal_approx(_tuning.eye_height, 0.001)
	assert_float(player.floor_snap_length).is_equal_approx(_tuning.step_height, 0.0001)


func test_walks_at_walk_speed() -> void:
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _measure_speed(player)
	assert_float(speed).is_equal_approx(_tuning.walk_speed, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()


func test_diagonal_input_is_not_faster() -> void:
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(1.0, 1.0)
	var speed: float = await _measure_speed(player)
	assert_float(speed).is_equal_approx(_tuning.walk_speed, SPEED_TOLERANCE)


func test_sprints_at_sprint_speed_and_spends_stamina() -> void:
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _measure_speed(player)
	assert_float(speed).is_equal_approx(_tuning.sprint_speed, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_true()
	assert_float(player.stamina.get_stamina()).is_less(_tuning.max_stamina)


func test_sprint_held_while_standing_still_spends_nothing() -> void:
	var player := _add_player(Vector3.ZERO)
	_stand_in(player).stamina = 50.0
	player.sprint_held = true
	await _frames(30)
	assert_float(player.stamina.get_stamina()).is_greater(50.0)


func test_sprint_does_not_start_below_its_threshold() -> void:
	var player := _add_player(Vector3.ZERO)
	# No regeneration can lift it to the threshold within the measurement below.
	_stand_in(player).stamina = _tuning.sprint_start_stamina - 12.0
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _measure_speed(player, 5, 30)
	assert_float(speed).is_equal_approx(_tuning.walk_speed, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()


func test_a_sprint_ends_when_stamina_runs_out() -> void:
	var player := _add_player(Vector3.ZERO)
	await _frames(5)
	_stand_in(player).stamina = _tuning.sprint_start_stamina
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	await _frames(2)
	assert_bool(player.is_sprinting()).is_true()
	var seconds := _tuning.sprint_start_stamina / _tuning.sprint_cost_per_second
	await _frames(ceili(seconds * Engine.physics_ticks_per_second) + 3)
	assert_bool(player.is_sprinting()).is_false()
	assert_float(player.stamina.get_stamina()).is_less(_tuning.sprint_start_stamina)


func test_jumps_to_the_jump_height_and_pays_for_it() -> void:
	var player := _add_player(Vector3.ZERO)
	await _frames(10)
	_stand_in(player).stamina = 50.0
	var start_y := player.global_position.y
	player.jump_requested = true
	await _frames(1)
	var paid := 50.0 - player.stamina.get_stamina()
	var peak: float = await _peak_height(player, 90)
	assert_float(peak - start_y).is_between(_tuning.jump_height - 0.02, _tuning.jump_height + 0.005)
	# The jump's cost, less one step of regeneration.
	var regen := _tuning.regen_per_second / Engine.physics_ticks_per_second
	assert_float(paid).is_equal_approx(_tuning.jump_cost - regen, 0.001)
	assert_bool(player.is_on_floor()).is_true()


func test_no_jump_without_its_full_cost() -> void:
	var player := _add_player(Vector3.ZERO)
	await _frames(10)
	_stand_in(player).stamina = _tuning.jump_cost - 1.0
	var start_y := player.global_position.y
	player.jump_requested = true
	var peak: float = await _peak_height(player, 30)
	assert_float(peak - start_y).is_less(0.01)


func test_no_jump_in_the_air() -> void:
	var player := _add_player(Vector3(0.0, 3.0, 0.0))
	await _frames(3)
	var stamina_before := player.stamina.get_stamina()
	player.jump_requested = true
	await _frames(1)
	assert_float(player.velocity.y).is_less(0.0)
	assert_float(player.stamina.get_stamina()).is_greater_equal(stamina_before)


func test_walks_up_a_step_of_step_height() -> void:
	# A ledge from z = -2 to -8, so the player is still on it after walking 3.4 m.
	_add_box(Vector3(0.0, _tuning.step_height * 0.5, -5.0), Vector3(4.0, _tuning.step_height, 6.0))
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(45)
	assert_float(player.global_position.z).is_less(-2.5)
	assert_float(player.global_position.y).is_equal_approx(_tuning.step_height, 0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_stops_at_a_ledge_above_step_height() -> void:
	var height := _tuning.step_height + 0.2
	_add_box(Vector3(0.0, height * 0.5, -3.0), Vector3(4.0, height, 2.0))
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(60)
	assert_float(player.global_position.y).is_less(0.01)
	assert_float(player.global_position.z).is_greater(-2.0 + _tuning.capsule_radius - 0.02)


func test_walks_up_stairs_whose_risers_are_step_height() -> void:
	var steps := 5
	_add_stairs(steps)
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(60)
	assert_float(player.global_position.y).is_equal_approx(_tuning.step_height * steps, 0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_sprints_up_stairs_and_the_view_lags_one_step_at_most() -> void:
	var steps := 10
	_add_stairs(steps)
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var lowest_eye := _tuning.eye_height
	for i: int in 60:
		await _frames(1)
		var eye := player.get_camera().global_position.y - player.global_position.y
		lowest_eye = minf(lowest_eye, eye)
	assert_float(player.global_position.y).is_equal_approx(_tuning.step_height * steps, 0.01)
	assert_float(lowest_eye).is_greater_equal(_tuning.eye_height - _tuning.step_height - 0.001)


func test_walks_up_a_low_step_too() -> void:
	var height := 0.1
	_add_box(Vector3(0.0, height * 0.5, -5.0), Vector3(4.0, height, 6.0))
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(45)
	assert_float(player.global_position.z).is_less(-2.5)
	assert_float(player.global_position.y).is_equal_approx(height, 0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_the_view_eases_up_a_step_instead_of_popping() -> void:
	_add_box(Vector3(0.0, _tuning.step_height * 0.5, -5.0), Vector3(4.0, _tuning.step_height, 6.0))
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var eye_y := player.get_camera().global_position.y
	var largest_rise := 0.0
	for i: int in 60:
		await _frames(1)
		var now := player.get_camera().global_position.y
		largest_rise = maxf(largest_rise, now - eye_y)
		eye_y = now
	assert_float(player.global_position.y).is_equal_approx(_tuning.step_height, 0.01)
	assert_float(largest_rise).is_less(_tuning.step_height * 0.5)
	assert_float(eye_y).is_equal_approx(_tuning.step_height + _tuning.eye_height, 0.001)


func test_walks_up_a_walkable_ramp_smoothly() -> void:
	await _assert_climbs_ramp_smoothly(25.0, false)


func test_sprints_up_a_ramp_at_the_steepest_walkable_angle_smoothly() -> void:
	await _assert_climbs_ramp_smoothly(44.0, true)


func test_does_not_hop_against_a_slope_too_steep_to_walk() -> void:
	_add_ramp(deg_to_rad(50.0), -1.0)
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var largest_change := 0.0
	var highest := 0.0
	var last_y := player.global_position.y
	for i: int in 120:
		await _frames(1)
		largest_change = maxf(largest_change, absf(player.global_position.y - last_y))
		last_y = player.global_position.y
		highest = maxf(highest, last_y)
	assert_float(largest_change).is_less(0.05)
	assert_float(highest).is_less(0.05)


func test_steps_over_a_low_round_pipe() -> void:
	_add_pipe(0.1, -2.0)
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(60)
	assert_float(player.global_position.z).is_less(-3.0)
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)


func test_stops_at_a_round_pipe_above_step_height() -> void:
	# Its top is above step height, though the capsule touches it lower down.
	_add_pipe(0.2, -2.0)
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var highest := 0.0
	for i: int in 90:
		await _frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(0.05)
	assert_float(player.global_position.z).is_greater(-2.0)


func test_walking_into_a_player_stops_without_moving_it() -> void:
	var other := _add_remote(Vector3(0.0, 0.0, -2.0))
	var player := _add_player(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(60)
	assert_vector(other.global_position).is_equal(Vector3(0.0, 0.0, -2.0))
	# It stopped in front of the other capsule instead of passing through or climbing it.
	var touching := -2.0 + 2.0 * _tuning.capsule_radius
	assert_float(player.global_position.z).is_between(touching - 0.02, touching + 0.1)
	assert_float(player.global_position.y).is_less(0.01)


func test_resolves_its_own_overlap_with_a_player() -> void:
	var other := _add_remote(Vector3(0.3, 0.0, 0.0))
	var player := _add_player(Vector3.ZERO)
	await _frames(30)
	assert_vector(other.global_position).is_equal(Vector3(0.3, 0.0, 0.0))
	var apart := _horizontal_distance(player.global_position, other.global_position)
	assert_float(apart).is_greater(2.0 * _tuning.capsule_radius - 0.02)
	assert_float(player.global_position.y).is_less(0.01)


func test_a_player_moved_into_it_is_resolved_while_it_stands() -> void:
	var other := _add_remote(Vector3(2.0, 0.0, 0.0))
	var player := _add_player(Vector3.ZERO)
	await _frames(5)
	# The other player walks into this one, as interpolation would carry it.
	for step: int in 40:
		other.global_position.x = maxf(2.0 - 0.075 * step, 0.2)
		await _frames(1)
	await _frames(10)
	var apart := _horizontal_distance(player.global_position, other.global_position)
	assert_float(apart).is_greater(2.0 * _tuning.capsule_radius - 0.02)
	assert_float(other.global_position.x).is_equal_approx(0.2, 0.0001)


func test_ghost_is_on_the_ghost_layer_and_collides_with_the_level_only() -> void:
	var player := _add_player(Vector3.ZERO)
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD | PhysicsLayers.LIVING)
	player.ghost = true
	assert_int(player.collision_layer).is_equal(PhysicsLayers.GHOSTS)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD)
	player.ghost = false
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD | PhysicsLayers.LIVING)


func test_remote_player_is_on_the_living_layer() -> void:
	var other := _add_remote(Vector3(5.0, 0.0, 0.0))
	assert_int(other.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(other.collision_mask).is_equal(0)


func test_ghost_hovers_without_gravity() -> void:
	var player := _add_ghost(Vector3(0.0, 2.0, 0.0))
	await _frames(30)
	assert_float(player.global_position.y).is_equal_approx(2.0, 0.001)


func test_ghost_flies_at_ghost_speed() -> void:
	var player := _add_ghost(Vector3(0.0, 2.0, 0.0))
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _measure_speed(player)
	assert_float(speed).is_equal_approx(_tuning.ghost_speed, SPEED_TOLERANCE)


func test_ghost_flies_up_and_down() -> void:
	var player := _add_ghost(Vector3(0.0, 2.0, 0.0))
	player.fly_up_held = true
	await _frames(1)
	var from_y := player.global_position.y
	await _frames(30)
	var climbed := player.global_position.y - from_y
	var seconds := 30.0 / Engine.physics_ticks_per_second
	assert_float(climbed).is_equal_approx(_tuning.ghost_speed * seconds, 0.05)
	player.fly_up_held = false
	player.fly_down_held = true
	await _frames(120)
	# The floor stops it: its feet rest on the level, not below it.
	assert_float(player.global_position.y).is_between(-0.01, 0.05)


func test_ghost_flies_where_it_looks() -> void:
	var player := _add_ghost(Vector3(0.0, 2.0, 0.0))
	player.look(0.0, deg_to_rad(30.0))
	player.move_input = Vector2(0.0, 1.0)
	await _frames(30)
	assert_float(player.global_position.y).is_greater(2.5)
	assert_float(player.global_position.z).is_less(-1.0)


func test_ghost_passes_through_players() -> void:
	var other := _add_remote(Vector3(0.0, 0.0, -2.0))
	var player := _add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(45)
	assert_float(player.global_position.z).is_less(-4.0)
	assert_vector(other.global_position).is_equal(Vector3(0.0, 0.0, -2.0))


func test_ghost_is_stopped_by_walls() -> void:
	_add_box(Vector3(0.0, 1.5, -3.0), Vector3(6.0, 3.0, 0.2))
	var player := _add_ghost(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _frames(60)
	assert_float(player.global_position.z).is_greater(-3.0 + 0.1 + _tuning.capsule_radius - 0.02)


func test_turning_back_into_the_living_restores_gravity() -> void:
	var player := _add_ghost(Vector3(0.0, 2.0, 0.0))
	await _frames(5)
	player.ghost = false
	await _frames(60)
	assert_float(player.global_position.y).is_less(0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_look_clamps_the_pitch_and_turns_left_for_a_positive_yaw() -> void:
	var player := _add_player(Vector3.ZERO)
	player.look(0.0, deg_to_rad(120.0))
	assert_float(player.get_camera().global_rotation.x).is_equal_approx(
		PlayerController.MAX_PITCH, 0.001
	)
	player.look(0.0, deg_to_rad(-240.0))
	assert_float(player.get_camera().global_rotation.x).is_equal_approx(
		-PlayerController.MAX_PITCH, 0.001
	)
	player.look(PI / 2.0, 0.0)
	# Forward was -Z; a quarter turn to the left faces -X.
	assert_vector(-player.global_basis.z).is_equal_approx(Vector3.LEFT, Vector3.ONE * 0.001)


func _add_player(at: Vector3) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.reads_device_input = false
	player.position = at
	_world.add_child(player)
	return player


func _add_ghost(at: Vector3) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.reads_device_input = false
	player.ghost = true
	player.position = at
	_world.add_child(player)
	return player


func _add_remote(at: Vector3) -> RemotePlayerBody:
	var body := REMOTE_SCENE.instantiate() as RemotePlayerBody
	body.position = at
	_world.add_child(body)
	return body


func _add_box(center: Vector3, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	_add_static(box, Transform3D(Basis.IDENTITY, center))


## `steps` stairs rising toward -Z from z = -1, each riser step height and each tread 0.3 m,
## narrower than the capsule, so it rests on a stair's edge below the stair's top. The last one is
## long.
func _add_stairs(steps: int) -> void:
	for i: int in steps:
		var tread := 0.3 if i < steps - 1 else 3.0
		var height := _tuning.step_height * (i + 1)
		var near_z := -1.0 - 0.3 * i
		_add_box(Vector3(0.0, height * 0.5, near_z - tread * 0.5), Vector3(4.0, height, tread))


## Walks or sprints up a ramp of `degrees` and asserts that the slope, not a ledge's lift, carries
## the body: on the floor every step, no rise beyond the slope's, and the view at eye height.
func _assert_climbs_ramp_smoothly(degrees: float, sprint: bool) -> void:
	var angle := deg_to_rad(degrees)
	_add_ramp(angle, -1.0)
	var player := _add_player(Vector3.ZERO)
	assert_float(angle).is_less(player.floor_max_angle)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = sprint
	# Onto the ramp's plane, past its foot.
	await _frames(20)
	var off_floor := 0
	var largest_rise := 0.0
	var eye_off := 0.0
	var last_y := player.global_position.y
	for i: int in 30:
		await _frames(1)
		if not player.is_on_floor():
			off_floor += 1
		largest_rise = maxf(largest_rise, player.global_position.y - last_y)
		last_y = player.global_position.y
		var eye := player.get_camera().global_position.y - last_y
		eye_off = maxf(eye_off, absf(eye - _tuning.eye_height))
	assert_int(off_floor).is_equal(0)
	var speed := _tuning.sprint_speed if sprint else _tuning.walk_speed
	var slope_rise := speed * tan(angle) / Engine.physics_ticks_per_second
	assert_float(largest_rise).is_less(slope_rise * 1.05)
	assert_float(eye_off).is_less(0.001)
	assert_float(last_y).is_greater(0.5)


## A 10 m ramp rising toward -Z at `angle` (radians), leaving the floor at z = `foot_z`.
func _add_ramp(angle: float, foot_z: float) -> void:
	var length := 10.0
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.0, length)
	var basis := Basis(Vector3.RIGHT, angle)
	var up_slope := Vector3(0.0, sin(angle), -cos(angle))
	var surface_middle := Vector3(0.0, 0.0, foot_z) + up_slope * length * 0.5
	_add_static(box, Transform3D(basis, surface_middle - basis.y * 0.5))


## A pipe of `radius` lying on the floor across the way, along X, centred at z = `z`.
func _add_pipe(radius: float, z: float) -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 4.0
	_add_static(cylinder, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.0, radius, z)))


func _add_static(shape: Shape3D, at: Transform3D) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.transform = at
	_world.add_child(body)


func _stand_in(player: PlayerController) -> LocalStamina:
	return player.stamina as LocalStamina


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## Horizontal metres per second over `frames` physics steps, after `settle` steps to reach
## full speed.
func _measure_speed(player: PlayerController, settle: int = 10, frames: int = 60) -> float:
	await _frames(settle)
	var from := player.global_position
	await _frames(frames)
	var to := player.global_position
	var moved := to - from
	if not player.ghost:
		moved.y = 0.0
	return moved.length() * Engine.physics_ticks_per_second / frames


func _peak_height(player: PlayerController, frames: int) -> float:
	var peak := player.global_position.y
	for i: int in frames:
		await _frames(1)
		peak = maxf(peak, player.global_position.y)
	return peak


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
