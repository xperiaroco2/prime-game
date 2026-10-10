extends GdUnitTestSuite
## Esc's menu, the Ready key and the Controls tab (#211) through Input events (#169): a host's Game
## alone over a LoopbackHub on a simulated clock, in the lobby; and on the main menu, with no
## session, Esc leaves the Voice page (#301) and opens no Esc menu. One Esc closes one overlay
## (#488): the host's question before the menu, a key capture before the menu. A new screen closes
## the menu (#726): a guest's, its host apart in a SubViewport no key reaches. Keys go in through
## Input.parse_input_event, which reaches the nodes' _input and _unhandled_input and the action
## states headless too (probed on 4.7.2).
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
	for action: StringName in [&"move_forward", &"ready", &"ui_cancel", &"jump", &"sprint"]:
		Input.action_release(action)
	# The InputMap is global too: a rebind in the Controls tab must not outlive its test.
	Controls.new().apply()


func test_the_lobby_shows_no_panel_over_the_game_and_one_esc_opens_the_lobby_tab() -> void:
	var game := await _lobby_game(PORT)
	# Walking in the lobby with the mouse captured (a click): nothing clickable covers the game,
	# only the keys' hint and the roster.
	game.pointer.capture(true)
	assert_array(_visible_buttons(game.ui)).is_empty()
	assert_bool(game.ui.lobby_hud.is_visible_in_tree()).is_true()
	assert_str(game.ui.lobby_hud.hint_label.text).is_equal("Esc: menu  ·  F: ready")
	assert_str(game.ui.lobby_hud.roster_label.text).contains("(host, you)  not ready")
	# One Esc: the menu on its Lobby tab (Ready and the host's settings), the mouse free.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_bool(game.pointer.captured()).is_false()
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.lobby)
	assert_array(_visible_buttons(game.ui)).contains(
		["esc.tab.game", "esc.tab.guide", "esc.tab.lobby", "esc.tab.settings", "esc.lobby.ready"]
	)
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
	game.ui.esc.resume_button.pressed.emit()
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.pointer.captured()).is_true()
	game.leave()
	await get_tree().process_frame


func test_an_esc_in_the_frame_of_the_welcome_opens_the_lobby_tab() -> void:
	# #204: the Welcome folds in the session's physics step and Game._process draws the lobby
	# after it, so an Esc in between found the UI still on Connecting and opened on Resume.
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 3)])
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
	# The lobby captures the mouse, but not from under the menu it kept.
	assert_bool(game.pointer.captured()).is_false()
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.lobby)
	assert_array(_visible_buttons(game.ui)).contains(
		["esc.tab.game", "esc.tab.lobby", "esc.lobby.ready"]
	)
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


func test_esc_closes_the_hosts_question_first_and_then_the_menu() -> void:
	var game := await _lobby_game(PORT + 5)
	game.pointer.capture(true)
	_press(KEY_ESCAPE)
	await _frames(2)
	game.ui.esc.press_leave()
	await _frames(1)
	assert_bool(game.ui.esc.state.asking()).is_true()
	# One Esc: the question goes, the tab as it was; the menu stays, the mouse free.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_bool(game.ui.esc.state.asking()).is_false()
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.lobby)
	assert_bool(game.pointer.captured()).is_false()
	assert_object(game.client()).is_not_null()
	# The next one closes the menu and captures the mouse again.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.pointer.captured()).is_true()
	# The window's close button asks too: Esc takes the question back first.
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames(2)
	assert_bool(game.ui.esc.state.asking()).is_true()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_bool(game.ui.esc.state.asking()).is_false()
	game.leave()
	await get_tree().process_frame


func test_under_the_menu_the_mouse_turns_nothing_and_after_it_the_look_is_back() -> void:
	var game := await _lobby_game(PORT + 6)
	var player := game.player()
	# Headless keeps no mouse mode: the controller is told the mouse is captured.
	player.mouse_captured = func() -> bool: return true
	_press(KEY_ESCAPE)
	await _frames(2)
	var yaw := player.rotation.y
	_move_mouse()
	await _frames(1)
	assert_float(player.rotation.y).is_equal(yaw)
	_hold(KEY_SPACE, true)
	_hold(KEY_SHIFT, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(player.jump_requested).is_false()
	assert_bool(player.sprint_held).is_false()
	_hold(KEY_SPACE, false)
	_hold(KEY_SHIFT, false)
	_press(KEY_ESCAPE)
	await _frames(2)
	_move_mouse()
	await _frames(1)
	assert_float(player.rotation.y).is_not_equal(yaw)
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


func test_the_controls_tab_rebinds_ready_through_real_keys_and_esc_cancels_a_capture() -> void:
	# #211: Settings › Controls in the Esc menu. A capture takes the next key in _input before the
	# menu sees it: Esc cancels the capture and the menu stays open; K binds Ready, which K then
	# toggles in the lobby while F no longer does.
	var game := await _lobby_game(PORT + 4)
	_press(KEY_ESCAPE)
	await _frames(2)
	game.ui.esc.press(EscMenuState.Tab.SETTINGS)
	game.ui.esc.settings.show_page(SettingsPage.Page.CONTROLS)
	await _frames(1)
	var panel := game.ui.esc.controls
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.settings)
	assert_bool(panel.is_visible_in_tree()).is_true()
	assert_object(panel.controls).is_same(game.controls)
	panel.key_buttons[&"ready"].pressed.emit()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(panel.is_capturing()).is_false()
	assert_bool(game.ui.esc_open()).is_true()
	# One Esc, one overlay (#488): the capture's, the tab still Controls.
	assert_object(game.ui.esc.page()).is_same(game.ui.esc.settings)
	assert_str(panel.key_buttons[&"ready"].text).is_equal("F")
	panel.key_buttons[&"ready"].pressed.emit()
	_press(KEY_K)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_true()
	assert_str(panel.key_buttons[&"ready"].text).is_equal("K")
	assert_str(KeyLabel.of_action(&"ready")).is_equal("K")
	# A real click on another row's key while capturing binds nothing: it reaches that button,
	# which starts its own capture; Esc ends that one.
	panel.key_buttons[&"ready"].pressed.emit()
	var back := panel.key_buttons[&"move_back"]
	# Input takes the window's coordinates; the button's rect is in the 1920x1080 base's.
	_click(back.get_viewport().get_screen_transform() * back.get_global_rect().get_center())
	await _frames(2)
	assert_str(String(panel.capturing)).is_equal("move_back")
	assert_str(KeyLabel.of_action(&"ready")).is_equal("K")
	assert_bool(panel.controls.is_default(&"move_back")).is_true()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(panel.is_capturing()).is_false()
	assert_str(back.text).is_equal("S")
	# The menu closes on Esc as before; the lobby's hint names the new key.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_false()
	assert_str(game.ui.lobby_hud.hint_label.text).is_equal("Esc: menu  ·  K: ready")
	_press(KEY_F)
	await _until(_ready_flag_is.bind(game, true), 20)
	assert_bool(_own_ready(game)).is_false()
	_press(KEY_K)
	assert_bool(await _until(_ready_flag_is.bind(game, true))).is_true()
	game.leave()
	await get_tree().process_frame


## #493 (#488 rule 2, the `menu_panel` overlay): Esc closes the open panel, the code, Direct and
## Settings ones, and gives the focus back to its item; no Esc menu opens with no session.
func test_on_the_main_menu_esc_closes_the_open_panel_and_opens_no_esc_menu() -> void:
	var game := _game([])
	await _frames(2)
	assert_int(game.screen()).is_equal(S.MENU)
	var menu := game.ui.menu
	for item: Button in [menu.settings_item, menu.join_item, menu.direct_item]:
		item.button_pressed = true
		await _frames(2)
		assert_str(String(game.ui.menu.state())).is_not_equal("main")
		_press(KEY_ESCAPE)
		await _frames(2)
		assert_str(String(game.ui.menu.state())).is_equal("main")
		assert_bool(item.button_pressed).is_false()
		assert_object(get_viewport().gui_get_focus_owner()).is_same(item)
		assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.ui.menu.voice.is_visible_in_tree()).is_false()
	# Esc on the menu with no panel open does nothing.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.ui.menu.is_visible_in_tree()).is_true()


## #494: Esc on the connecting screen is its Cancel (the menu, the address kept), and on a failure
## its Back, the failure's Primary focused till then; no Esc menu opens on either.
func test_esc_cancels_a_join_and_leaves_a_failure_for_the_menu() -> void:
	var game := _game([])
	await _frames(2)
	game.ui.menu.address_edit.text = "127.0.0.1:%d" % (PORT + 9)
	game.ui.menu.join_requested.emit(game.ui.menu.address_edit.text, game.ui.menu.default_port)
	assert_int(game.screen()).is_equal(S.CONNECTING)
	_press(KEY_ESCAPE)
	assert_object(game.client()).is_null()
	assert_str(String(game.last_reason)).is_equal(String(ClientSession.LEFT))
	assert_int(game.screen()).is_equal(S.MENU)
	assert_bool(game.ui.esc_open()).is_false()
	assert_str(game.ui.menu.address_edit.text).is_equal("127.0.0.1:%d" % (PORT + 9))
	# Nobody listens there: the join fails, and its failure shows with Try again focused.
	game.ui.menu.join_requested.emit(game.ui.menu.address_edit.text, game.ui.menu.default_port)
	assert_bool(await _until(func() -> bool: return game.screen() == S.FAILURE)).is_true()
	await _frames(2)
	assert_bool(game.ui.connecting.failure.is_visible_in_tree()).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(game.ui.connecting.primary.face)
	assert_bool(game.pointer.captured()).is_false()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_int(game.screen()).is_equal(S.MENU)
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.ui.menu.is_visible_in_tree()).is_true()
	assert_bool(game.ui.connecting.visible).is_false()
	assert_str(game.ui.menu.address_edit.text).is_equal("127.0.0.1:%d" % (PORT + 9))


## #726: a guest readies with F, opens the Esc menu with Esc and waits; the match started and the
## menu went along over Loading into the round. The countdown still runs in the lobby's scene, so
## the menu stays open there (its Ready can take the ready back); every screen the match swaps in
## closes it, and the mouse follows that screen. The host plays apart, where no key reaches it.
func test_a_ready_guests_esc_menu_closes_as_the_match_leaves_the_lobby() -> void:
	var port := PORT + 7
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % port], true)
	var guest := _game(["--join=127.0.0.1", "--port=%d" % port])
	assert_bool(await _until(_both_on.bind(host, guest, S.LOBBY))).is_true()
	await _frames(2)
	_press(KEY_F)
	assert_bool(await _until(_ready_flag_is.bind(guest, true))).is_true()
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(guest.ui.esc_open()).is_true()
	assert_bool(guest.pointer.captured()).is_false()
	host.set_ready(true)
	assert_bool(await _until(func() -> bool: return _phase(guest) == &"countdown")).is_true()
	await _frames(2)
	assert_bool(guest.ui.esc_open()).is_true()
	# Loading: no menu over it, the mouse captured again as the lobby had it.
	assert_bool(await _until(func() -> bool: return guest.ui.screen == S.LOADING, 400)).is_true()
	_assert_menu_gone(guest)
	assert_bool(guest.pointer.captured()).is_true()
	# The round: no menu, the mouse captured, the keys read.
	assert_bool(await _until(func() -> bool: return guest.ui.screen == S.ROUND, 400)).is_true()
	_assert_menu_gone(guest)
	assert_bool(guest.pointer.captured()).is_true()
	assert_bool(guest.player().reads_device_input).is_true()
	# One Esc opens it again, on Game.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(guest.ui.esc_open()).is_true()
	assert_object(guest.ui.esc.page()).is_same(guest.ui.esc.actions)
	guest.leave()
	host.leave()
	await get_tree().process_frame


## #726: the round's end and the lobby's return close the menu too, with what is open on it: the
## guest's dropdown list (Settings) and the host's Leave question; the end screen frees the mouse
## and the lobby captures it again.
func test_the_end_screen_and_the_lobby_close_the_menu_its_dropdown_and_the_question() -> void:
	var port := PORT + 8
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % port], true)
	var guest := _game(["--join=127.0.0.1", "--port=%d" % port])
	assert_bool(await _until(_both_on.bind(host, guest, S.LOBBY))).is_true()
	host.change_setting(&"match_duration", 1)
	assert_bool(await _until(func() -> bool: return _duration(guest) == 1)).is_true()
	host.set_ready(true)
	guest.set_ready(true)
	assert_bool(await _until(_both_on.bind(host, guest, S.ROUND), 400)).is_true()
	# The guest: Esc, the Settings tab, its talk mode's list open.
	_press(KEY_ESCAPE)
	await _frames(2)
	guest.ui.esc.press(EscMenuState.Tab.SETTINGS)
	await _frames(2)
	var mode_list := guest.ui.esc.voice.mode_button.get_popup()
	guest.ui.esc.voice.mode_button.show_popup()
	await _frames(2)
	assert_bool(mode_list.visible).is_true()
	# The host: Leave asks first.
	host.open_esc()
	host.ui.esc.press_leave()
	assert_bool(host.ui.esc.state.asking()).is_true()
	# Time up: the end screen, nothing of either menu left, the mouse free for it.
	assert_bool(await _until(_both_on.bind(host, guest, S.END), 400)).is_true()
	_assert_menu_gone(guest)
	# The list is a window of its own; under load (CI's shard) it was seen still open here.
	assert_bool(await _until(func() -> bool: return not mode_list.visible, 30)).is_true()
	assert_bool(guest.pointer.captured()).is_false()
	_assert_menu_gone(host)
	assert_bool(host.ui.esc.confirm_box.visible).is_false()
	assert_int(host.ui.esc.menu.focus_behavior_recursive).is_equal(Control.FOCUS_BEHAVIOR_INHERITED)
	# Esc on the end screen opens the menu; the lobby's return closes it and captures the mouse.
	_press(KEY_ESCAPE)
	await _frames(2)
	assert_bool(guest.ui.esc_open()).is_true()
	host.return_to_lobby()
	assert_bool(await _until(_both_on.bind(host, guest, S.LOBBY), 400)).is_true()
	_assert_menu_gone(guest)
	assert_bool(guest.pointer.captured()).is_true()
	guest.leave()
	host.leave()
	await get_tree().process_frame


## Both games show `screen` with both players in their rosters.
func _both_on(host: Game, guest: Game, screen: S) -> bool:
	for game: Game in [host, guest]:
		if game.client() == null or game.ui.screen != screen:
			return false
		if game.client().model.roster.size() != 2:
			return false
	return true


func _phase(game: Game) -> StringName:
	return game.client().model.phase if game.client() != null else &""


func _duration(game: Game) -> int:
	return game.client().model.settings.get(&"match_duration", -1) if game.client() != null else -1


## The Esc menu is shut and drawn shut: its state, its node and its dialog.
func _assert_menu_gone(game: Game) -> void:
	assert_bool(game.ui.esc_open()).is_false()
	assert_bool(game.ui.esc.visible).is_false()
	assert_bool(game.ui.esc.state.asking()).is_false()


## A host's Game alone in the lobby, its pointer a FakePointer, its screens shown.
func _lobby_game(port: int) -> Game:
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % port])
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


## A mouse motion of 40 px to the right, as the mouse sends it.
func _move_mouse() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)
	motion.screen_relative = Vector2(40, 0)
	motion.position = Vector2(960, 540)
	Input.parse_input_event(motion)
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


## A Game at the root, where the keys reach it; `apart`: in a SubViewport of its own instead, with
## its own World3D (as game_loop_test.gd), which no key reaches.
func _game(args: Array[String], apart := false) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = func() -> int: return _now
	game.make_transport = _transport
	game.pointer = FakePointer.new()
	if apart:
		var machine := SubViewport.new()
		machine.own_world_3d = true
		machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
		machine.add_child(game)
		add_child(machine)
		auto_free(machine)
	else:
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
