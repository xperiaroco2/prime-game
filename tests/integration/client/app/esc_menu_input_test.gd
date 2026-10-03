extends GdUnitTestSuite
## Esc's menu and the Ready key through Input events (#169): a host's Game alone over a LoopbackHub
## on a simulated clock, in the lobby. Keys go in through Input.parse_input_event, which reaches
## the nodes' _input and _unhandled_input and the action states headless too (probed on 4.7.2).
## Headless Godot keeps no mouse mode, so the game's pointer is a FakePointer.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7320
const STEP_USEC := 250000
const MAX_FRAMES := 200

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


## Remembers what the game asked of the mouse.
class FakePointer:
	extends MousePointer
	var on := false

	func capture(value: bool) -> void:
		on = value

	func captured() -> bool:
		return on


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func after_test() -> void:
	# Input's action states are global: nothing stays held for the next suite.
	for action: StringName in [&"move_forward", &"ready", &"ui_cancel"]:
		Input.action_release(action)


func test_the_lobby_shows_no_panel_over_the_game_and_one_esc_opens_the_lobby_tab() -> void:
	var game := await _lobby_game(PORT)
	# Walking in the lobby with the mouse captured (a click): nothing clickable covers the game,
	# only the keys' hint and the roster.
	game.pointer.capture(true)
	assert_array(_visible_buttons(game.ui)).is_empty()
	assert_bool(game.ui.lobby_hud.is_visible_in_tree()).is_true()
	assert_str(game.ui.lobby_hud.hint_label.text).is_equal(LobbyHud.HINT)
	assert_str(game.ui.lobby_hud.roster_label.text).contains("(host, you)  not ready")
	# One Esc: the menu on its Lobby tab (Ready and the host's settings), the mouse free.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_bool(game.pointer.captured()).is_false()
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.lobby)
	assert_array(_visible_buttons(game.ui)).contains(["Resume", "Lobby", "Leave", "Quit", "Ready"])
	assert_bool(game.ui.esc.lobby.settings_editable()).is_true()
	# Esc again: closed, the mouse captured again.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.pointer.captured()).is_true()
	assert_array(_visible_buttons(game.ui)).is_empty()
	# Resume closes it the same way.
	_press(KEY_ESCAPE)
	await _frames(2)
	game.ui.esc.tab_buttons[EscMenuState.Tab.RESUME].pressed.emit()
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.pointer.captured()).is_true()
	game.leave()
	await get_tree().process_frame


func test_an_esc_in_the_frame_of_the_welcome_opens_the_lobby_tab() -> void:
	# #204: the Welcome folds in the session's physics step and Game._process draws the lobby
	# after it, so an Esc in between found the UI still on Connecting and opened on Resume.
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 3)])
	game.pointer = FakePointer.new()
	var drawn_at_esc: Array[GameFlow.Screen] = []
	game.client().welcomed.connect(
		func(_own: int) -> void:
			drawn_at_esc.append(game.ui.screen)
			_press(KEY_ESCAPE)
	)
	assert_bool(await _until(func() -> bool: return game.screen() == S.LOBBY)).is_true()
	# The Esc came before any _process drew the lobby (Connecting, or the menu if no _process ran
	# yet under load): the frame of the Welcome.
	assert_int(drawn_at_esc.size()).is_equal(1)
	assert_int(drawn_at_esc[0]).is_not_equal(S.LOBBY)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.lobby)
	assert_array(_visible_buttons(game.ui)).contains(["Resume", "Lobby", "Ready"])
	game.leave()
	await get_tree().process_frame


func test_under_the_menu_held_keys_are_released_and_gameplay_keys_ignored() -> void:
	var game := await _lobby_game(PORT + 1)
	var player := game.player()
	_hold(KEY_W, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(player.move_input.y).is_greater(0.0)
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(player.reads_device_input).is_false()
	assert_vector(player.move_input).is_equal(Vector2.ZERO)
	# F under the menu readies nobody.
	_press(KEY_F)
	await _until(_ready_flag_is.bind(game, true), 20)
	assert_bool(_own_ready(game)).is_false()
	_hold(KEY_W, false)
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(player.reads_device_input).is_true()
	game.leave()
	await get_tree().process_frame


func test_the_ready_key_sends_what_the_ready_toggle_sends() -> void:
	var game := await _lobby_game(PORT + 2)
	assert_bool(_own_ready(game)).is_false()
	# F with no menu: SetReady(true), seen in the roster the host sends back.
	_press(KEY_F)
	assert_bool(await _until(_ready_flag_is.bind(game, true))).is_true()
	# F again: SetReady(false).
	_press(KEY_F)
	assert_bool(await _until(_ready_flag_is.bind(game, false))).is_true()
	# The Lobby tab's Ready toggle: the same intent, the same flag.
	_press(KEY_ESCAPE)
	await _frames(2)
	game.ui.esc.lobby.ready_button.button_pressed = true
	assert_bool(await _until(_ready_flag_is.bind(game, true))).is_true()
	game.leave()
	await get_tree().process_frame


## A host's Game alone in the lobby, its pointer a FakePointer, its screens shown.
func _lobby_game(port: int) -> Game:
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % port])
	game.pointer = FakePointer.new()
	assert_bool(await _until(func() -> bool: return game.screen() == S.LOBBY)).is_true()
	await _frames(2)
	return game


func _own_ready(game: Game) -> bool:
	var model := game.client().model
	var own: ClientModel.Member = model.roster.get(model.own_peer)
	return own != null and own.ready


func _ready_flag_is(game: Game, on: bool) -> bool:
	return _own_ready(game) == on


## `count` whole frames: process_frame fires before the nodes' _process.
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Presses and releases `key`.
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


## The texts of the buttons that show under `ui`.
func _visible_buttons(ui: GameUi) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in ui.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.is_visible_in_tree() and button is Button:
			texts.append((button as Button).text)
	return texts


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
