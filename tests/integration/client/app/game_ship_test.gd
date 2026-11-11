extends GdUnitTestSuite
## The own ship with no session (#1285, GameShip, ARCHITECTURE §4.7.66), headless on a simulated
## clock: a Game living in the ship boots into the base mode's lobby hosted on a private
## LoopbackHub (no networked transport, nobody else in, Game.hosting() false), the UI in the
## ship's place (the lobby HUD's Esc hint, the suit menu's Find a lobby, Host and Tutorial); Find's
## direct Host leaves it and hosts for real, and leaving that session brings a new ship. A Game
## with no command line and no ship_home keeps the main menu. Like game_loop_test, each Game sits
## in a SubViewport with its own World3D.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7440
const STEP_USEC := 250000
const MAX_FRAMES := 600

const S := GameFlow.Screen
const T := EscMenuState.Tab

var _hub: LoopbackHub
var _now := 1000000
## How often a Game asked for a networked transport (make_transport).
var _made := 0


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000
	_made = 0


func test_the_game_boots_into_its_own_private_ship() -> void:
	var game := _game(true)
	assert_bool(game.ship.running).is_true()
	assert_object(game.client()).is_not_null()
	# Private: no networked transport, and Leave or Quit ask nobody.
	assert_int(_made).is_equal(0)
	assert_bool(game.hosting()).is_false()
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	assert_int(game.client().model.roster.size()).is_equal(1)
	await _frames()
	# The ship's place: the lobby HUD's Esc hint alone, the suit menu's own tabs and buttons.
	assert_bool(game.ui.lobby_hud.hint.visible).is_true()
	assert_bool(game.ui.esc.state.ship).is_true()
	assert_array(game.ui.esc.state.tabs()).contains_exactly([T.GAME, T.FIND, T.GUIDE, T.SETTINGS])
	game.ui.open_esc(game.hosting(), game.client().model)
	await _frames()
	assert_bool(game.ui.esc.host_button.visible).is_true()
	assert_bool(game.ui.esc.tutorial_button.visible).is_true()
	assert_bool(game.ui.esc.resume_button.visible).is_false()
	assert_bool(game.ui.esc.leave_button.visible).is_false()
	game.ui.close_esc()
	await _close(game)


func test_find_hosts_directly_and_the_ship_comes_back_after_leaving() -> void:
	var game := _game(true)
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	game.ui.esc.find.direct_host_requested.emit(PORT)
	# The ship left first: one real host on the networked transport, no ship's place.
	assert_bool(game.ship.running).is_false()
	assert_bool(game.hosting()).is_true()
	assert_int(_made).is_equal(1)
	assert_bool(game.ui.esc.state.ship).is_false()
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	await _frames()
	assert_bool(game.ui.lobby_hud.hint.visible).is_false()
	# Leaving the real lobby (nothing to read) brings a new private ship after the frame.
	game.leave()
	assert_bool(game.hosting()).is_false()
	assert_bool(await _until(func() -> bool: return game.ship.running)).is_true()
	assert_int(_made).is_equal(1)
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	assert_bool(game.ui.esc.state.ship).is_true()
	await _close(game)


func test_the_tutorial_leaves_the_ship() -> void:
	var game := _game(true)
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	game.ui.esc.tutorial_requested.emit()
	assert_bool(game.ship.running).is_false()
	assert_bool(game.tutorial.running).is_true()
	assert_bool(game.ui.esc.state.ship).is_false()
	assert_int(_made).is_equal(0)
	await _close(game)


func test_a_game_without_a_ship_keeps_the_main_menu() -> void:
	var game := _game(false)
	assert_bool(game.ship.running).is_false()
	assert_object(game.client()).is_null()
	assert_int(game.screen()).is_equal(S.MENU)
	assert_bool(game.ui.esc.state.ship).is_false()
	await _frames()
	assert_bool(game.ui.lobby_hud.hint.visible).is_false()


func test_the_ready_key_starts_no_match_in_the_ship() -> void:
	var game := _game(true)
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	game.toggle_ready()
	for i in 40:
		_now += STEP_USEC
		await get_tree().physics_frame
	var model := game.client().model
	assert_bool((model.roster[model.own_peer] as ClientModel.Member).ready).is_false()
	assert_bool(model.phase == &"lobby").is_true()
	await _close(game)


func test_an_address_that_does_not_parse_brings_the_ship_back() -> void:
	var game := _game(true)
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	game.ui.esc.find.direct_join_requested.emit("a b", PORT)
	assert_bool(game.ship.running).is_false()
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	assert_bool(game.ship.running).is_true()
	assert_int(_made).is_equal(0)
	await _close(game)


func test_a_failures_join_directly_opens_find_s_address_in_the_ship() -> void:
	var game := _game(true)
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	game.open_direct()
	await _frames()
	assert_bool(game.ship.running).is_true()
	assert_bool(game.ui.esc_open()).is_true()
	assert_int(game.ui.esc.state.selected).is_equal(T.FIND)
	assert_bool(game.ui.esc.find.direct_open()).is_true()
	game.ui.close_esc()
	await _close(game)


func test_only_the_launched_game_or_a_game_asking_lives_in_the_ship() -> void:
	# A Game in the tree (one built off it leaves its parts orphaned), its fields set after.
	var game := _game(false)
	game.settings = UserSettings.new()
	game.settings.path = "user://game_ship_test.cfg"
	game.options = LaunchOptions.parse(PackedStringArray())
	game.read_command_line = true
	assert_bool(game.options.given).is_false()
	assert_bool(GameShip.homes(game)).is_true()
	# A launch option (the runner's, a playcheck window's), or no settings file: the main menu.
	game.options = LaunchOptions.parse(PackedStringArray(["--host"]))
	assert_bool(GameShip.homes(game)).is_false()
	game.options = LaunchOptions.parse(PackedStringArray())
	game.settings.path = ""
	assert_bool(GameShip.homes(game)).is_false()
	# No command line read (a test's Game) unless it asks.
	game.settings.path = "user://game_ship_test.cfg"
	game.read_command_line = false
	assert_bool(GameShip.homes(game)).is_false()
	game.ship_home = true
	assert_bool(GameShip.homes(game)).is_true()


func _game(ship_home: bool) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.ship_home = ship_home
	game.load_character = false
	game.clock = _clock
	game.make_transport = _transport
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
	_made += 1
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


## The game's model and its shown screen are the lobby with the own player in.
func _in_lobby(game: Game) -> bool:
	if game.client() == null or game.client().model.own_peer == 0:
		return false
	return game.screen() == S.LOBBY and game.ui.screen == S.LOBBY


## Ends the session with no ship coming back, and lets its nodes go before the test ends
## (orphans fail it).
func _close(game: Game) -> void:
	game.ship_home = false
	game.leave()
	await _frames()


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


## Two idle frames: what Game._process writes is shown (tests.md, #222), and the nodes a Leave
## queued for freeing are gone before the test ends.
func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
