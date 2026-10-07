extends GdUnitTestSuite
## Alt+Enter through Input events (#517): a Game on its main menu with a window that remembers
## what was asked (headless Godot keeps no window mode). Keys go in through
## Input.parse_input_event, which reaches Game._input headless (#169).

const GAME := preload("res://client/app/game.tscn")


## Remembers the modes the game asked for, starting fullscreen as an exported game does.
class RecordingWindow:
	extends GameWindow
	var now := DisplayServer.WINDOW_MODE_FULLSCREEN
	var asked: Array[DisplayServer.WindowMode] = []

	func mode() -> DisplayServer.WindowMode:
		return now

	func set_mode(value: DisplayServer.WindowMode) -> void:
		now = value
		asked.append(value)


func after_test() -> void:
	_key(KEY_ENTER, false, true)


func test_alt_enter_on_the_menu_flips_the_window() -> void:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray()
	var window := RecordingWindow.new()
	game.window = window
	add_child(game)
	auto_free(game)
	await get_tree().process_frame
	assert_int(game.screen()).is_equal(GameFlow.Screen.MENU)
	_press_alt_enter()
	await get_tree().process_frame
	assert_array(window.asked).contains_exactly([DisplayServer.WINDOW_MODE_WINDOWED])
	_press_alt_enter()
	await get_tree().process_frame
	assert_array(window.asked).contains_exactly(
		[DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN]
	)
	assert_object(game.client()).is_null()


func _press_alt_enter() -> void:
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false, true)


func _key(key: Key, pressed: bool, alt: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.alt_pressed = alt
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
