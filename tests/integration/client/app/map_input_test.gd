extends GdUnitTestSuite
## The map key in the game (#253) through Input events, as esc_menu_input_test.gd: a host's Game
## alone over a LoopbackHub on a simulated clock (the base mode plays with one), its pointer one
## that remembers what the game asked (headless Godot keeps no mouse mode). M opens the map and
## frees the mouse, M again closes it and captures it; Tab does nothing; with the map open the
## player still walks and a click never recaptures the mouse; Esc closes only the map; under the
## Esc menu M does nothing, and a close request closes the map under the menu it opens; the end of
## the round closes it, and the next round starts with it closed.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7395
const STEP_USEC := 250000
const MAX_FRAMES := 900

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000
## The mouse buttons that reached this suite, the last node to see unhandled input.
var _unhandled_clicks := 0


## Remembers what the game asked of the mouse.
class RecordingPointer:
	extends MousePointer
	var on := false
	var asked: Array[bool] = []

	func capture(value: bool) -> void:
		on = value
		asked.append(value)

	func captured() -> bool:
		return on

	func focused() -> bool:
		return true


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000
	_unhandled_clicks = 0


func after_test() -> void:
	# Input's action states are global: nothing stays held for the next suite.
	for action: StringName in [&"move_forward", &"map", &"ui_cancel"]:
		Input.action_release(action)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		_unhandled_clicks += 1


func test_m_opens_and_closes_the_map_and_the_player_keeps_walking() -> void:
	var game := await _round_game(PORT)
	var pointer := game.pointer as RecordingPointer
	var player := game.player()
	assert_bool(pointer.captured()).is_true()
	# Tab is kept for an inventory later: nothing.
	_press(KEY_TAB)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	_press(KEY_M)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_true()
	assert_bool(game.ui.map.is_visible_in_tree()).is_true()
	assert_bool(pointer.captured()).is_false()
	assert_bool(player.mouse_free).is_true()
	# The keys still move the player (the designer's answer on #253).
	assert_bool(player.reads_device_input).is_true()
	_hold(KEY_W, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(player.move_input.y).is_greater(0.0)
	_hold(KEY_W, false)
	# A click on the open map never captures the mouse (the controller leaves it unhandled).
	_click(Vector2(4, 4))
	assert_int(_unhandled_clicks).is_equal(1)
	_press(KEY_M)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	assert_bool(pointer.captured()).is_true()
	assert_bool(player.mouse_free).is_false()
	game.leave()
	await get_tree().process_frame


func test_esc_closes_only_the_map_and_under_the_esc_menu_m_does_nothing() -> void:
	var game := await _round_game(PORT + 1)
	var pointer := game.pointer as RecordingPointer
	_press(KEY_M)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_true()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(pointer.captured()).is_true()
	# The Esc menu: M opens nothing under it.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	_press(KEY_M)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(pointer.captured()).is_true()
	# Closing the window while the map is open: the host's Esc menu asks, over no map, the mouse
	# free; Resume captures it again with the map still closed.
	_press(KEY_M)
	await _frames(2)
	pointer.asked.clear()
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_bool(game.ui.map_is_open()).is_false()
	assert_bool(pointer.captured()).is_false()
	assert_array(pointer.asked).not_contains([true])
	game.close_esc()
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	assert_bool(pointer.captured()).is_true()
	game.leave()
	await get_tree().process_frame


func test_the_end_of_the_round_closes_the_map_and_the_next_round_starts_closed() -> void:
	var game := await _round_game(PORT + 2)
	var pointer := game.pointer as RecordingPointer
	_press(KEY_M)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_true()
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.END)).is_true()
	assert_bool(game.ui.map_is_open()).is_false()
	assert_bool(game.ui.map.visible).is_false()
	assert_bool(pointer.captured()).is_false()
	game.return_to_lobby()
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.LOBBY)).is_true()
	game.set_ready(true)
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.ROUND)).is_true()
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	assert_bool(game.player().mouse_free).is_false()
	assert_bool(pointer.captured()).is_true()
	game.leave()
	await get_tree().process_frame


## A host's Game alone in the round of a one-minute match, its screens shown.
func _round_game(port: int) -> Game:
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % port])
	game.pointer = RecordingPointer.new()
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.LOBBY)).is_true()
	game.change_setting(&"match_duration", 1)
	(
		assert_bool(
			await _until(
				func() -> bool: return game.client().model.settings.get(&"match_duration", -1) == 1
			)
		)
		. is_true()
	)
	game.set_ready(true)
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.ROUND)).is_true()
	await _frames(2)
	return game


## `count` whole frames: process_frame fires before the nodes' _process.
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _press(key: Key) -> void:
	_hold(key, true)
	_hold(key, false)


func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Presses and releases the left mouse button at `at` (viewport coordinates).
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = func() -> int: return _now
	game.make_transport = _transport
	add_child(game)
	auto_free(game)
	return game


func _transport() -> NetTransport:
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


func _until(done: Callable, frames := MAX_FRAMES) -> bool:
	for i in frames:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()
