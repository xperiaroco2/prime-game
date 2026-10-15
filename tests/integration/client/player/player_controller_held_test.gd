extends GdUnitTestSuite
## PlayerController.held (#786, the photo camera's viewfinder; ARCHITECTURE §4.7.56): while it is
## set the device neither moves nor turns the player (the movement keys are not read, a mouse
## motion does not look), and setting it lets go of every key held. Clearing it gives both back.

const World := preload("res://tests/integration/client/player/player_test_world.gd")

var _world: Node3D
var _player: PlayerController


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_player.mouse_captured = func() -> bool: return true


func after_test() -> void:
	Input.action_release(&"move_forward")
	_world.free()


func test_holding_lets_go_of_the_keys_held() -> void:
	_player.move_input = Vector2(0, 1)
	_player.sprint_held = true
	_player.crouch_held = true
	_player.held = true
	assert_vector(_player.move_input).is_equal(Vector2.ZERO)
	assert_bool(_player.sprint_held).is_false()
	assert_bool(_player.crouch_held).is_false()


func test_held_movement_keys_are_not_read_until_it_is_cleared() -> void:
	_player.reads_device_input = true
	_player.held = true
	Input.action_press(&"move_forward")
	await _frames(2)
	assert_vector(_player.move_input).is_equal(Vector2.ZERO)
	_player.held = false
	await _frames(2)
	assert_float(_player.move_input.y).is_greater(0.0)


func test_a_mouse_motion_turns_nobody_while_held() -> void:
	_player.reads_device_input = true
	_player.held = true
	var before := _player.look_vector()
	_move_mouse()
	assert_vector(_player.look_vector()).is_equal_approx(before, Vector3.ONE * 1e-6)
	_player.held = false
	_move_mouse()
	assert_float(_player.look_vector().distance_to(before)).is_greater(1e-3)


## A mouse motion of 40 px to the right, as the mouse sends it.
func _move_mouse() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)
	motion.screen_relative = Vector2(40, 0)
	motion.position = Vector2(960, 540)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
