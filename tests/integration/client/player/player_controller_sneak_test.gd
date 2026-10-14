extends GdUnitTestSuite
## The local sneak (#989, #990) over real physics steps (Jolt, headless): held Alt walks standing at
## the crouch walk's crouch_speed_mps; the crouch wins over it (Ctrl + Alt) and so does the sprint
## key (Shift + Alt, a walk on an empty stamina bar); the downed never sneak, and letting go of the
## keys ends it. Each step's sneak goes to ClientSession.set_motion. Its steps' silence:
## `world_sounds_steps_test.gd`.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const SPEED_TOLERANCE := 0.05

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_alt_walks_standing_at_the_crouch_walks_speed() -> void:
	var player := await _player()
	player.sneak_held = true
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(player, 4, 30)
	assert_bool(player.is_sneaking()).is_true()
	assert_bool(player.is_crouched()).is_false()
	assert_bool(player.is_sprinting()).is_false()
	assert_float(speed).is_equal_approx(_rules.crouch_speed_mps, SPEED_TOLERANCE)
	# Standing: the standing capsule and eye.
	assert_float(_capsule(player).height).is_equal_approx(_rules.capsule_height_m, 0.0001)
	var eye := player.get_camera().global_position.y - player.global_position.y
	assert_float(eye).is_equal_approx(_rules.eye_height_m, 0.001)
	# Let go: a walk again.
	player.sneak_held = false
	speed = await _world.measure_speed(player, 4, 30)
	assert_bool(player.is_sneaking()).is_false()
	assert_float(speed).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)


func test_ctrl_and_alt_crouch() -> void:
	var player := await _player()
	player.sneak_held = true
	player.crouch_held = true
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(player, 4, 30)
	assert_bool(player.is_crouched()).is_true()
	assert_bool(player.is_sneaking()).is_false()
	assert_float(speed).is_equal_approx(_rules.crouch_speed_mps, SPEED_TOLERANCE)


func test_shift_and_alt_sprint() -> void:
	var player := await _player()
	player.sneak_held = true
	player.sprint_held = true
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(player, 4, 30)
	assert_bool(player.is_sprinting()).is_true()
	assert_bool(player.is_sneaking()).is_false()
	assert_float(speed).is_equal_approx(_rules.sprint_speed_mps, SPEED_TOLERANCE)


func test_shift_and_alt_on_an_empty_stamina_bar_walk() -> void:
	var player := await _player()
	_world.stand_in(player).set_status(0)
	player.sneak_held = true
	player.sprint_held = true
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(player, 4, 30)
	assert_bool(player.is_sprinting()).is_false()
	assert_bool(player.is_sneaking()).is_false()
	assert_float(speed).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)


func test_a_jump_from_the_crouch_with_alt_held_never_sneaks() -> void:
	var player := await _player()
	player.sneak_held = true
	player.crouch_held = true
	await _world.frames(5)
	player.jump_requested = true
	await _world.frames(1)
	# Stood up to jump with Ctrl held: neither crouched nor sneaking in the air.
	assert_bool(player.is_crouched()).is_false()
	assert_bool(player.is_sneaking()).is_false()


func test_the_downed_never_sneak_and_release_keys_ends_it() -> void:
	var player := await _player()
	player.sneak_held = true
	await _world.frames(2)
	assert_bool(player.is_sneaking()).is_true()
	player.release_keys()
	assert_bool(player.sneak_held).is_false()
	assert_bool(player.is_sneaking()).is_false()
	player.sneak_held = true
	await _world.frames(2)
	assert_bool(player.is_sneaking()).is_true()
	player.life = ClientModel.Life.DOWNED
	assert_bool(player.is_sneaking()).is_false()
	await _world.frames(3)
	assert_bool(player.is_sneaking()).is_false()


func test_each_step_claims_its_sneak() -> void:
	var player := await _player()
	var schema := WireSchema.game(OS.is_debug_build())
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	var session := ClientSession.new(transport, FixtureBaseMode.mode(), schema)
	player.attach(session)
	player.sneak_held = true
	await _world.frames(2)
	assert_bool(session._sneaking).is_true()
	assert_bool(session._crouched).is_false()
	player.crouch_held = true
	await _world.frames(2)
	assert_bool(session._sneaking).is_false()
	assert_bool(session._crouched).is_true()
	player.crouch_held = false
	await _world.frames(2)
	assert_bool(session._sneaking).is_true()
	player.sneak_held = false
	await _world.frames(1)
	assert_bool(session._sneaking).is_false()


## A living player at rest on the floor.
func _player() -> PlayerController:
	var player := _world.add_player(Vector3.ZERO)
	await _world.frames(3)
	return player


func _capsule(player: PlayerController) -> CapsuleShape3D:
	return (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
