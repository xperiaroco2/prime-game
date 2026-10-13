extends GdUnitTestSuite
## The local crouch (the crouch ADR, #791: KE5, KE6, KD4 (a), KD5 (b), KD6 (b)) over real physics
## steps (Jolt, headless), on the fixture level `crouch_room.tscn`: a slab whose underside is 1.4 m
## above the floor, between the crouched 1.2 m and the standing 1.8 m of FixtureModes' rules. The
## slab spans x -9.5 to -6.5 and z -1 to 3; the player starts at (-8, 0, 6) and walks -Z under it.
## Over the network: `player_network_crouch_test.gd`.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const CROUCH_ROOM := "res://tests/fixtures/client/crouch_room.tscn"
const SPEED_TOLERANCE := 0.05
const START := Vector3(-8.0, 0.0, 6.0)
## Under the middle of the slab.
const UNDER := Vector3(-8.0, 0.0, 1.0)
## The slab's near and far edges along Z.
const SLAB_NEAR_Z := 3.0
const SLAB_FAR_Z := -1.0

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)
	_world.add_child((load(CROUCH_ROOM) as PackedScene).instantiate())


func after_test() -> void:
	_world.free()


func test_the_capsule_switches_with_the_feet_kept_and_the_view_eases() -> void:
	var player := await _player(START)
	var feet := player.global_position.y
	player.crouch_held = true
	await _world.frames(1)
	assert_bool(player.is_crouched()).is_true()
	assert_float(_capsule(player).height).is_equal_approx(_rules.crouch_height_m, 0.0001)
	assert_float(_capsule(player).radius).is_equal_approx(_rules.capsule_radius_m, 0.0001)
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	assert_float(shape.position.y).is_equal_approx(_rules.crouch_height_m * 0.5, 0.0001)
	assert_float(player.global_position.y).is_equal_approx(feet, 0.01)
	# The view eases down at the step's catch-up rate rather than popping.
	var eye := player.get_camera().global_position.y - player.global_position.y
	assert_float(eye).is_greater(_rules.crouch_eye_height_m + 0.05)
	await _world.frames(30)
	eye = player.get_camera().global_position.y - player.global_position.y
	assert_float(eye).is_equal_approx(_rules.crouch_eye_height_m, 0.001)
	# Let go in the open: the standing capsule, and the view eases back up.
	player.crouch_held = false
	await _world.frames(1)
	assert_bool(player.is_crouched()).is_false()
	assert_float(_capsule(player).height).is_equal_approx(_rules.capsule_height_m, 0.0001)
	assert_float(shape.position.y).is_equal_approx(_rules.capsule_height_m * 0.5, 0.0001)
	await _world.frames(30)
	eye = player.get_camera().global_position.y - player.global_position.y
	assert_float(eye).is_equal_approx(_rules.eye_height_m, 0.001)


func test_standing_the_slab_blocks_the_body_and_crouched_it_passes_under() -> void:
	var player := await _player(START)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(150)
	# Stopped at the slab's near edge by the capsule's top.
	assert_float(player.global_position.z).is_greater(SLAB_NEAR_Z)
	assert_float(player.global_position.z).is_less(SLAB_NEAR_Z + _rules.capsule_radius_m + 0.1)
	player.crouch_held = true
	await _world.frames(200)
	assert_float(player.global_position.z).is_less(SLAB_FAR_Z - _rules.capsule_radius_m)
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)


func test_letting_go_underneath_keeps_the_crouch_until_the_body_is_out() -> void:
	var player := await _player(START)
	player.crouch_held = true
	player.move_input = Vector2(0.0, 1.0)
	await _until_z(player, UNDER.z)
	player.crouch_held = false
	var stood_at := INF
	for i: int in 200:
		await _world.frames(1)
		if not player.is_crouched():
			stood_at = player.global_position.z
			break
		# Still under some of the slab: a standing capsule would meet it.
		assert_float(player.global_position.z).is_greater(SLAB_FAR_Z - _rules.capsule_radius_m)
	# It stands up by itself once it is out, with no key pressed again.
	assert_float(stood_at).is_less(SLAB_FAR_Z - _rules.capsule_radius_m + 0.05)
	assert_float(_capsule(player).height).is_equal_approx(_rules.capsule_height_m, 0.0001)


func test_a_teleport_underneath_starts_crouched_and_one_in_the_open_stands() -> void:
	var player := await _player(START)
	player.teleport(Transform3D(player.global_basis, UNDER))
	assert_bool(player.is_crouched()).is_true()
	var eye := player.get_camera().position.y + player.get_camera().get_parent_node_3d().position.y
	assert_float(eye).is_equal_approx(_rules.crouch_eye_height_m, 0.001)
	await _world.frames(20)
	assert_bool(player.is_crouched()).is_true()
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)
	player.teleport(Transform3D(player.global_basis, START))
	assert_bool(player.is_crouched()).is_false()
	# Held Ctrl keeps the crouch through a teleport into the open.
	player.crouch_held = true
	await _world.frames(1)
	player.teleport(Transform3D(player.global_basis, START + Vector3(1.0, 0.0, 0.0)))
	assert_bool(player.is_crouched()).is_true()


func test_a_life_change_into_the_living_underneath_starts_crouched() -> void:
	var player := await _player(START)
	player.life = ClientModel.Life.DEAD
	player.global_position = UNDER
	await _world.frames(2)
	player.life = ClientModel.Life.ALIVE
	assert_bool(player.is_crouched()).is_true()
	await _world.frames(10)
	assert_bool(player.is_crouched()).is_true()
	# Out of the living: the standing capsule (the downed keep it, KE4).
	player.life = ClientModel.Life.DOWNED
	assert_bool(player.is_crouched()).is_false()
	assert_float(_capsule(player).height).is_equal_approx(_rules.capsule_height_m, 0.0001)


func test_shift_while_crouched_is_the_fast_crouch_at_the_sprints_cost() -> void:
	var player := await _player(Vector3(8.0, 0.0, 8.0))
	player.crouch_held = true
	player.sprint_held = true
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(2)
	var before := player.stamina.get_stamina()
	var speed: float = await _world.measure_speed(player, 4, 30)
	assert_bool(player.is_crouched()).is_true()
	assert_bool(player.is_sprinting()).is_true()
	assert_float(speed).is_equal_approx(_rules.crouch_fast_speed_mps, SPEED_TOLERANCE)
	# 34 physics steps of the sprint's cost, give or take a 20 Hz tick.
	var spent := before - player.stamina.get_stamina()
	var expected := _rules.sprint_cost_per_s * 34.0 / Engine.physics_ticks_per_second
	var tick := _rules.sprint_cost_per_s / float(Ticks.RATE)
	assert_float(spent).is_between(expected - tick - 0.01, expected + tick + 0.01)


func test_the_crouch_walk_once_the_stamina_runs_out() -> void:
	var player := await _player(Vector3(8.0, 0.0, 8.0))
	_world.stand_in(player).set_status(Ticks.thousandths(_rules.sprint_start))
	player.crouch_held = true
	player.sprint_held = true
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(2)
	assert_bool(player.is_sprinting()).is_true()
	var seconds := float(_rules.sprint_start) / _rules.sprint_cost_per_s
	await _world.frames(ceili(seconds * Engine.physics_ticks_per_second) + 3)
	assert_bool(player.is_sprinting()).is_false()
	var speed: float = await _world.measure_speed(player, 2, 20)
	assert_float(speed).is_equal_approx(_rules.crouch_speed_mps, SPEED_TOLERANCE)
	assert_bool(player.is_crouched()).is_true()


func test_space_while_crouched_stands_jumps_and_crouches_again_on_landing() -> void:
	var player := await _player(START)
	player.crouch_held = true
	await _world.frames(30)
	assert_bool(player.is_crouched()).is_true()
	var start_y := player.global_position.y
	player.jump_requested = true
	await _world.frames(1)
	# Stood up and took off in the same step, Ctrl still held.
	assert_bool(player.is_crouched()).is_false()
	assert_float(player.velocity.y).is_greater(0.0)
	var peak := start_y
	var landed := false
	for i: int in 120:
		await _world.frames(1)
		if player.is_on_floor():
			landed = true
			break
		peak = maxf(peak, player.global_position.y)
		# No crouch again before it lands.
		assert_bool(player.is_crouched()).is_false()
	assert_bool(landed).is_true()
	assert_float(peak - start_y).is_between(
		_rules.jump_height_m - 0.02, _rules.jump_height_m + 0.005
	)
	# Landed with Ctrl held: crouched again.
	await _world.frames(1)
	assert_bool(player.is_crouched()).is_true()


func test_space_under_the_slab_does_nothing() -> void:
	var player := await _player(START)
	player.teleport(Transform3D(player.global_basis, UNDER))
	player.crouch_held = true
	await _world.frames(10)
	var stamina := player.stamina.get_stamina()
	var start_y := player.global_position.y
	player.jump_requested = true
	var peak: float = await _world.peak_height(player, 30)
	assert_float(peak - start_y).is_less(0.01)
	assert_bool(player.is_crouched()).is_true()
	assert_float(player.stamina.get_stamina()).is_greater_equal(stamina)
	assert_bool(player.jump_requested).is_false()


func test_where_the_crouch_does_not_play_the_key_does_nothing() -> void:
	var player := await _player(START)
	player.crouch_plays = false
	player.crouch_held = true
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(150)
	assert_bool(player.is_crouched()).is_false()
	assert_float(player.global_position.z).is_greater(SLAB_NEAR_Z)
	# A teleport underneath stands too, and so does a crouch the level change ends.
	player.teleport(Transform3D(player.global_basis, UNDER))
	assert_bool(player.is_crouched()).is_false()
	player.teleport(Transform3D(player.global_basis, START))
	player.crouch_plays = true
	await _world.frames(1)
	assert_bool(player.is_crouched()).is_true()
	player.crouch_plays = false
	assert_bool(player.is_crouched()).is_false()
	assert_float(_capsule(player).height).is_equal_approx(_rules.capsule_height_m, 0.0001)


func test_the_downed_and_the_dead_never_crouch() -> void:
	var player := await _player(START)
	player.crouch_held = true
	player.life = ClientModel.Life.DOWNED
	await _world.frames(5)
	assert_bool(player.is_crouched()).is_false()
	player.life = ClientModel.Life.DEAD
	assert_bool(player.is_crouched()).is_false()


func test_each_body_keeps_its_own_capsule() -> void:
	var one := await _player(START)
	var two := _world.add_player(START + Vector3(4.0, 0.0, 0.0))
	two.crouch_plays = true
	one.crouch_held = true
	await _world.frames(2)
	assert_float(_capsule(one).height).is_equal_approx(_rules.crouch_height_m, 0.0001)
	assert_float(_capsule(two).height).is_equal_approx(_rules.capsule_height_m, 0.0001)


## A living player at `at` where the crouch plays, at rest on the floor.
func _player(at: Vector3) -> PlayerController:
	var player := _world.add_player(at)
	player.crouch_plays = true
	await _world.frames(3)
	return player


func _capsule(player: PlayerController) -> CapsuleShape3D:
	return (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D


## Walks on until the feet are at or past `z` (walking -Z), at most 300 steps.
func _until_z(player: PlayerController, z: float) -> void:
	for i: int in 300:
		if player.global_position.z <= z:
			return
		await _world.frames(1)
