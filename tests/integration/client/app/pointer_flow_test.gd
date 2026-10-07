extends GdUnitTestSuite
## The mouse from the lobby into the round (#517): a host and a joined client, two Game roots each
## in a SubViewport over a LoopbackHub on a simulated clock (as game_loop_test.gd), each with a
## pointer that remembers what the game asked of it (headless Godot keeps no mouse mode). The lobby
## and the round capture the mouse, Loading keeps it, the end screen and the menu free it; an open
## Esc menu or a window without the focus is never captured by a screen change.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7380
const STEP_USEC := 250000
const MAX_FRAMES := 600

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


## Remembers every capture the game asked for, in order.
class RecordingPointer:
	extends MousePointer
	var on := false
	var has_focus := true
	var asked: Array[bool] = []

	func capture(value: bool) -> void:
		on = value
		asked.append(value)

	func captured() -> bool:
		return on

	func focused() -> bool:
		return has_focus


## What each Game's Ui showed, frame by frame, and whether its mouse was captured then.
class Watch:
	var shown: Dictionary[Game, Array] = {}
	var freed_on: Dictionary[Game, Array] = {}


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func test_the_mouse_stays_captured_from_the_lobby_through_loading_into_the_round() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % PORT])
	var guest := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var games: Array[Game] = [host, guest]
	# The lobby's start captures the mouse: the player looks around without a click first.
	assert_bool(await _until(_all_on.bind(games, S.LOBBY, 2))).is_true()
	for game: Game in games:
		assert_bool(_pointer(game).captured()).is_true()
	host.change_setting(&"match_duration", 1)
	assert_bool(await _until(_setting_is.bind(games, &"match_duration", 1))).is_true()
	# Ready, the countdown (still the lobby's screen), Loading, the round: never freed on the way.
	var watch := Watch.new()
	for game: Game in games:
		watch.shown[game] = []
		watch.freed_on[game] = []
		_pointer(game).asked.clear()
		game.set_ready(true)
	assert_bool(await _until(_round_watching.bind(games, watch))).is_true()
	for game: Game in games:
		assert_array(watch.shown[game]).contains([S.LOADING])
		assert_array(watch.freed_on[game]).is_empty()
		assert_array(_pointer(game).asked).not_contains([false])
		assert_bool(_pointer(game).captured()).is_true()
		assert_bool(game.player().reads_device_input).is_true()
	# The end screen frees it for its button; Back to lobby captures it again.
	assert_bool(await _until(_all_on.bind(games, S.END, 2))).is_true()
	for game: Game in games:
		assert_bool(_pointer(game).captured()).is_false()
	host.return_to_lobby()
	assert_bool(await _until(_all_on.bind(games, S.LOBBY, 2))).is_true()
	for game: Game in games:
		assert_bool(_pointer(game).captured()).is_true()
	guest.leave()
	assert_bool(_pointer(guest).captured()).is_false()
	host.leave()
	await get_tree().process_frame


func test_an_open_esc_menu_or_a_window_without_the_focus_stays_free_into_the_round() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 1)])
	var guest := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 1)])
	var games: Array[Game] = [host, guest]
	# The guest's player alt-tabbed away while it joined: its window does not take the mouse.
	_pointer(guest).has_focus = false
	assert_bool(await _until(_all_on.bind(games, S.LOBBY, 2))).is_true()
	assert_bool(_pointer(guest).captured()).is_false()
	assert_array(_pointer(guest).asked).not_contains([true])
	# The host readies from its Esc menu and leaves it open: the round does not close it, nor take
	# the mouse from under it.
	host.open_esc()
	assert_bool(_pointer(host).captured()).is_false()
	for game: Game in games:
		game.set_ready(true)
	assert_bool(await _until(_all_on.bind(games, S.ROUND, 2))).is_true()
	assert_bool(host.ui.esc_open()).is_true()
	assert_bool(_pointer(host).captured()).is_false()
	assert_bool(_pointer(guest).captured()).is_false()
	assert_array(_pointer(guest).asked).not_contains([true])
	# Closing the menu in the round captures it, as in the lobby (#169).
	host.close_esc()
	assert_bool(_pointer(host).captured()).is_true()
	guest.leave()
	host.leave()
	await get_tree().process_frame


func _pointer(game: Game) -> RecordingPointer:
	return game.pointer as RecordingPointer


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = _clock
	game.make_transport = _transport
	game.pointer = RecordingPointer.new()
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	return game


func _clock() -> int:
	return _now


func _transport() -> NetTransport:
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


## Every game is on `screen` with `players` in its roster, and its Game._process has shown it.
func _all_on(games: Array[Game], screen: S, players: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != screen or game.ui.screen != screen:
			return false
		if game.client().model.roster.size() != players:
			return false
	return true


## Every game shows the round. Until then each frame notes the screen each Ui shows and whether
## its mouse was free on a screen the player looks around in or passes through.
func _round_watching(games: Array[Game], watch: Watch) -> bool:
	for game: Game in games:
		var shown: S = game.ui.screen
		if watch.shown[game].is_empty() or watch.shown[game].back() != shown:
			watch.shown[game].append(shown)
		if shown in [S.LOBBY, S.LOADING, S.ROUND] and not _pointer(game).captured():
			watch.freed_on[game].append(shown)
	return _all_on(games, S.ROUND, 2)


func _setting_is(games: Array[Game], id: StringName, value: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.client().model.settings.get(id, -1) != value:
			return false
	return true
