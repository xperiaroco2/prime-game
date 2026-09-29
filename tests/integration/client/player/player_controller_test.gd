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
	assert_float(climbed).is_equal_approx(_tuning.ghost_speed * 0.5, 0.05)
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
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)


func _stand_in(player: PlayerController) -> LocalStamina:
	return player.stamina as LocalStamina


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## Horizontal metres per second over `seconds_frames` physics steps, after `settle` steps to reach
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
