extends GdUnitTestSuite
## The tutorial's invite and plates in the game (#492: GameTutorial over GameUi.tutorial,
## TutorialScreen), through Input events as map_input_test.gd: a first launch's Game (settings
## from a file, the flag absent) on a simulated clock, its pointer one that remembers what the game
## asked (headless Godot keeps no mouse mode). Once the room is in, the invite shows over it with
## the HUD hidden, the mouse free, no key counting and the map key ignored; Start sets the flag,
## begins lesson 1 with its plates and captures the mouse; Esc on the invite, and Skip, set the flag
## and end at the main menu with no failure; a language chip applies and saves its language. The
## main menu's Tutorial shows the plates with no invite.

const GAME := preload("res://client/app/game.tscn")
const STEP_USEC := 250000
const MAX_FRAMES := 600
const SETTINGS_PATH := "user://game_tutorial_invite_test.cfg"

const S := GameFlow.Screen

var _now := 1000000
var _locale := ""


## Remembers what the game asked of the mouse.
class RecordingPointer:
	extends MousePointer
	var on := false

	func capture(value: bool) -> void:
		on = value

	func captured() -> bool:
		return on

	func focused() -> bool:
		return true


func before_test() -> void:
	_now = 1000000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func test_the_invite_waits_over_the_room_and_start_begins_lesson_1() -> void:
	var game := await _first_launch()
	var screen := game.ui.tutorial
	var pointer := game.pointer as RecordingPointer
	assert_bool(screen.invite_shown()).is_true()
	assert_bool(screen.visible).is_true()
	assert_bool(game.ui.hud.visible).is_false()
	assert_bool(screen.step.visible or screen.list.visible).is_false()
	assert_bool(pointer.captured()).is_false()
	assert_bool(game.player().mouse_free).is_true()
	assert_bool(game.player().reads_device_input).is_false()
	assert_object(game.get_viewport().gui_get_focus_owner()).is_same(screen.start_button)
	# No lesson yet, and the map key does nothing under the invite.
	assert_int(game.tutorial.runner.lesson()).is_equal(0)
	_press(KEY_M)
	await _frames(2)
	assert_bool(game.ui.map_is_open()).is_false()
	# Start: the flag is written, lesson 1 begins with its plates, the mouse is captured.
	screen.start_button.pressed.emit()
	assert_bool(_saved().tutorial_seen).is_true()
	assert_bool(screen.invite_shown()).is_false()
	assert_int(game.tutorial.runner.lesson()).is_equal(1)
	assert_bool(pointer.captured()).is_true()
	await _frames(2)
	assert_bool(game.ui.hud.visible).is_true()
	# s1's Hud: the round HUD without its role chip (the tutorial runs no clock: no timer).
	assert_bool(game.ui.hud.role.visible).is_false()
	assert_bool(game.ui.hud.timer.visible).is_false()
	assert_bool(screen.step.visible).is_true()
	assert_bool(screen.list.visible).is_true()
	assert_str(screen.progress_label.text).is_equal("Step 1 of 9")
	assert_str(String(screen.how.name)).is_equal("HowKeys")
	assert_str(String(screen.rows.get_child(0).name)).is_equal("MoveNow")
	assert_bool(game.player().reads_device_input).is_true()
	assert_bool(game.player().mouse_free).is_false()
	# Esc now opens the Esc menu (the invite is gone), not a Skip.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_bool(game.tutorial.running).is_true()
	game.leave()
	await _frames(2)
	assert_bool(screen.visible).is_false()
	assert_bool(screen.step.visible or screen.list.visible).is_false()


func test_esc_on_the_invite_skips_to_the_main_menu() -> void:
	var game := await _first_launch()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.tutorial.running).is_false()
	assert_bool(game.ui.esc_open()).is_false()
	assert_int(game.screen()).is_equal(S.MENU)
	assert_str(String(game.failure)).is_empty()
	assert_bool(_saved().tutorial_seen).is_true()
	assert_bool(game.ui.tutorial.invite_shown()).is_false()


func test_a_language_chip_applies_and_saves_and_skip_leaves() -> void:
	var game := await _first_launch()
	var screen := game.ui.tutorial
	var uk := screen.chips[Languages.UKRAINIAN]
	uk.button_pressed = true
	uk.pressed.emit()
	assert_str(TranslationServer.get_locale()).is_equal(Languages.UKRAINIAN)
	assert_str(_saved().language).is_equal(Languages.UKRAINIAN)
	assert_bool(screen.chips[Languages.ENGLISH].button_pressed).is_false()
	# The invite stays open with its focus; the flag waits for Start or Skip.
	assert_bool(screen.invite_shown()).is_true()
	assert_bool(_saved().tutorial_seen).is_false()
	screen.skip_button.pressed.emit()
	await _frames(2)
	assert_int(game.screen()).is_equal(S.MENU)
	assert_bool(_saved().tutorial_seen).is_true()


func test_the_menus_tutorial_shows_the_plates_with_no_invite() -> void:
	var game := _game(null)
	game.ui.menu.tutorial_item.pressed.emit()
	assert_bool(await _until(func() -> bool: return game.tutorial.runner.lesson() == 1)).is_true()
	await _frames(2)
	assert_bool(game.ui.tutorial.invite_shown()).is_false()
	assert_bool(game.ui.tutorial.step.visible).is_true()
	assert_str(game.ui.tutorial.title_label.text).is_equal("tutorial.step.move.title")
	game.leave()
	await _frames(2)


## A first launch in the room: its Game, its invite showing.
func _first_launch() -> Game:
	var settings := UserSettings.new(SETTINGS_PATH)
	settings.tutorial_seen = false
	var game := _game(settings)
	assert_bool(game.tutorial.invite_open).is_true()
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.ROUND)).is_true()
	await _frames(2)
	return game


func _saved() -> UserSettings:
	var back := UserSettings.new(SETTINGS_PATH)
	back.read()
	return back


func _game(settings: UserSettings) -> Game:
	var game := GAME.instantiate() as Game
	game.settings = settings
	game.read_command_line = false
	game.launch_args = PackedStringArray()
	game.clock = func() -> int: return _now
	game.make_transport = func() -> NetTransport: return null
	game.pointer = RecordingPointer.new()
	add_child(game)
	auto_free(game)
	return game


func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


## Idle frames: Game._process draws the screens and applies the player's flags.
func _frames(count: int) -> void:
	for i in count:
		_now += STEP_USEC
		await get_tree().process_frame


func _press(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
