extends GdUnitTestSuite
## The local crouch on the network (the crouch ADR, #791): the real PlayerController of a joined
## Game claims through its ClientSession over a LoopbackHub to the host's HostSession, on the
## fixture `crouch_room.tscn` (NetPair.with_crouch_room: a slab 1.4 m above the floor). A crouched
## walk under the slab and out, with Shift for a while and Ctrl let go underneath, gets no
## Correction, also with every packet held back and with jitter; the host relays the crouch to the
## others. Keys go in through Input.parse_input_event (the action states are global; the joiner's
## Game alone reads devices) and Esc through the joiner's SubViewport: a held Ctrl does not block W
## and Shift, the Esc menu lets go of it, and it does nothing in the lobby and on a map the mode's
## crouch_maps leaves out (KE10). The controller alone: `player_controller_crouch_test.gd`.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## Where the joiner starts its walk -Z under the slab (x -9.5 to -6.5, z -1 to 3).
const START := Vector3(-8.0, 0.0, 6.0)
const SLAB_NEAR_Z := 3.0
const SLAB_FAR_Z := -1.0
const DELAY_FRAMES := 4
const JITTER_FRAMES := 8
const SPEED_TOLERANCE := 0.1

var _pair: NetPair
## The modifier keys held now: real key events carry them, and the actions must match inexactly.
var _ctrl_down := false
var _shift_down := false


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	for key: Key in [KEY_CTRL, KEY_W, KEY_SHIFT, KEY_ESCAPE]:
		_hold(key, false)
	_pair.free()


func test_a_crouched_walk_under_the_slab_and_out_is_never_corrected() -> void:
	await _walk_under_and_out()


func test_a_crouched_walk_under_the_slab_with_delay_is_never_corrected() -> void:
	_pair.delay_frames = DELAY_FRAMES
	await _walk_under_and_out()


func test_a_crouched_walk_under_the_slab_with_jitter_is_never_corrected() -> void:
	_pair.delay_frames = 1
	_pair.jitter_frames = JITTER_FRAMES
	await _walk_under_and_out()


func test_ctrl_held_with_w_and_shift_still_moves_and_esc_lets_go_of_it() -> void:
	var player := await _in_the_round(true)
	assert_bool(await _pair.walk_to(player, START + Vector3(4.0, 0.0, 0.0))).is_true()
	_face_forward(player)
	_pair.client.device_input = true
	await _pair.frames(2)
	_hold(KEY_CTRL, true)
	_hold(KEY_W, true)
	_hold(KEY_SHIFT, true)
	await _pair.frames(10)
	assert_bool(player.crouch_held).is_true()
	assert_bool(player.is_crouched()).is_true()
	assert_bool(player.is_sprinting()).is_true()
	assert_float(player.move_input.y).is_greater(0.0)
	var from := player.global_position
	await _pair.frames(30)
	var to := player.global_position
	var speed := (
		Vector2(to.x - from.x, to.z - from.z).length() * Engine.physics_ticks_per_second / 30
	)

	assert_float(speed).is_equal_approx(
		_pair.mode.player_rules.crouch_fast_speed_mps, SPEED_TOLERANCE
	)
	_hold(KEY_SHIFT, false)
	_hold(KEY_W, false)
	# Esc alone, into the joiner's window, with Ctrl still held: the menu lets go of it, and the
	# body stands where there is room.
	_push_esc()
	await _pair.frames(3)
	assert_bool(_pair.client.ui.blocks_keys()).is_true()
	assert_bool(player.crouch_held).is_false()
	assert_bool(player.is_crouched()).is_false()
	_hold(KEY_CTRL, false)
	_push_esc()
	await _pair.frames(3)
	assert_bool(_pair.client.ui.blocks_keys()).is_false()
	await _pair.frames(10)
	assert_int(_pair.client.client().corrections).is_equal(0)
	await _pair.stop()


func test_the_key_does_nothing_in_the_lobby() -> void:
	_pair.with_crouch_room(true)
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	_pair.client.device_input = true
	_hold(KEY_CTRL, true)
	await _pair.frames(20)
	assert_bool(player.crouch_held).is_true()
	assert_bool(player.crouch_plays).is_false()
	assert_bool(player.is_crouched()).is_false()
	assert_bool(_pair.host.client().model.is_crouched(_pair.peer_of(_pair.client))).is_false()
	_hold(KEY_CTRL, false)
	await _pair.stop()


func test_the_key_does_nothing_on_a_map_the_list_leaves_out() -> void:
	var player := await _in_the_round(false)
	assert_bool(player.crouch_plays).is_false()
	assert_bool(await _pair.walk_to(player, START)).is_true()
	_face_forward(player)
	player.crouch_held = true
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(150)
	# Standing, stopped at the slab's near edge.
	assert_bool(player.is_crouched()).is_false()
	assert_float(player.global_position.z).is_greater(SLAB_NEAR_Z)
	assert_bool(_pair.host.client().model.is_crouched(_pair.peer_of(_pair.client))).is_false()
	player.move_input = Vector2.ZERO
	await _pair.stop()


## From START a crouched walk -Z under the slab (Shift for the first second, the fast crouch paid
## as a sprint), Ctrl let go underneath, on until out and stood up; the host's own client sees
## the crouch relayed and then gone; no Correction on either side.
func _walk_under_and_out() -> void:
	var player := await _in_the_round(true)
	assert_bool(player.crouch_plays).is_true()
	assert_bool(await _pair.walk_to(player, START)).is_true()
	_face_forward(player)
	var joiner := _pair.peer_of(_pair.client)
	var host_model := _pair.host.client().model
	player.crouch_held = true
	player.sprint_held = true
	player.move_input = Vector2(0.0, 1.0)
	var relayed := false
	for i: int in 60:
		await _pair.frames(1)
		relayed = relayed or host_model.is_crouched(joiner)
	assert_bool(player.is_crouched()).is_true()
	player.sprint_held = false
	for i: int in 300:
		if player.global_position.z <= 1.0:
			break
		await _pair.frames(1)
		relayed = relayed or host_model.is_crouched(joiner)
	assert_bool(relayed).is_true()
	assert_float(player.global_position.z).is_less_equal(1.0)
	player.crouch_held = false
	for i: int in 300:
		if not player.is_crouched():
			break
		await _pair.frames(1)
	assert_bool(player.is_crouched()).is_false()
	assert_float(player.global_position.z).is_less(SLAB_FAR_Z)
	await _pair.frames(20)
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_bool(host_model.is_crouched(joiner)).is_false()
	assert_int(_pair.client.client().corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	if _pair.jitter_frames > 0:
		assert_int(_pair.host_transport.latest_superseded).is_greater(0)
	await _pair.stop()


## Both in the round on crouch_room (`listed`: where the crouch plays); the joiner's player.
func _in_the_round(listed: bool) -> PlayerController:
	_pair.with_crouch_room(listed)
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	return _pair.client.player()


## Turns the body to face -Z, level.
func _face_forward(player: PlayerController) -> void:
	player.look(angle_difference(player.rotation.y, 0.0), 0.0)


func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	if key == KEY_CTRL:
		_ctrl_down = pressed
	elif key == KEY_SHIFT:
		_shift_down = pressed
	event.ctrl_pressed = _ctrl_down
	event.shift_pressed = _shift_down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Esc pressed and let go in the joiner's window (its SubViewport), where its Game's _input reads
## it; the root viewport's Input never reaches a SubViewport by itself.
func _push_esc() -> void:
	var viewport := _pair.client.get_viewport()
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		viewport.push_input(event)
