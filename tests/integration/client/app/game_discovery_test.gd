extends GdUnitTestSuite
## The lobbies nearby in the game (#1316, GameDiscovery, ARCHITECTURE §4.9): two Games living in the
## ship (as game_ship_test.gd, each in a SubViewport with its own World3D, the sessions over one
## LoopbackHub on a simulated clock, the discovery over real UDP on 127.0.0.1 and a test port).
## The ship answers nobody (no shared session); once one hosts directly, the other's Find a lobby
## lists its lobby with its players, and Join on the row joins it. A Game not living in the ship
## opens no discovery socket.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7462
const DISCOVERY_PORT := 47462
const STEP_USEC := 250000
const MAX_FRAMES := 600

const S := GameFlow.Screen
const T := EscMenuState.Tab

var _hub: LoopbackHub
var _now := 1000000


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func test_a_hosts_lobby_shows_on_the_others_find_page_and_joins() -> void:
	var host := _game()
	var guest := _game()
	var games: Array[Game] = [host, guest]
	assert_bool(await _until(func() -> bool: return _in_lobby(host) and _in_lobby(guest))).is_true()
	# In the own ship nothing answers: no shared session.
	assert_bool(host.discovery.enabled).is_true()
	assert_bool(host.discovery.responder.running()).is_false()
	host.ui.esc.find.direct_host_requested.emit(PORT)
	assert_bool(await _until(func() -> bool: return host.hosting() and _in_lobby(host))).is_true()
	assert_bool(host.discovery.responder.running()).is_true()
	# The guest opens Find a lobby: the finder runs and lists the host's lobby.
	guest.ui.open_esc(guest.hosting(), guest.client().model)
	guest.ui.esc.press(T.FIND)
	var find := guest.ui.esc.find
	assert_bool(await _until(func() -> bool: return find.rows.size() == 1)).is_true()
	assert_bool(guest.discovery.finder.running()).is_true()
	var row: Button = find.rows.values()[0]
	var host_name := host.client().model.host_name()
	assert_str((row.get_node(^"H/Name") as Label).text).is_equal("%s's lobby" % host_name)
	assert_str((row.get_node(^"H/Count") as Label).text).is_equal("1 / %d" % host.mode.max_players)
	# Join on the row: the guest leaves its ship and joins the host directly.
	find.join_chosen()
	var joined := func() -> bool: return host.client().model.roster.size() == 2 and _in_lobby(guest)
	assert_bool(await _until(joined)).is_true()
	assert_bool(guest.ship.running).is_false()
	# Out of Find a lobby the finder stops.
	assert_bool(guest.discovery.finder.running()).is_false()
	# The host leaves: its responder stops with the hosting.
	host.ship_home = false
	host.leave()
	(
		assert_bool(await _until(func() -> bool: return not host.discovery.responder.running()))
		. is_true()
	)
	guest.ship_home = false
	guest.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func test_a_host_bound_to_this_machine_alone_answers_nobody() -> void:
	# Nobody nearby could join it: GameDiscovery.describe gives no answer.
	var game := _game()
	assert_bool(await _until(func() -> bool: return _in_lobby(game))).is_true()
	game.ship.go(game, func() -> void: game.host(PORT + 2, LaunchOptions.LOCALHOST))
	assert_bool(await _until(func() -> bool: return game.hosting() and _in_lobby(game))).is_true()
	assert_str(game.hosted_bind).is_equal(LaunchOptions.LOCALHOST)
	assert_object(GameDiscovery.describe(game)).is_null()
	# The same lobby on every interface answers.
	game.hosted_bind = LaunchOptions.EVERY_INTERFACE
	var answer := GameDiscovery.describe(game)
	assert_object(answer).is_not_null()
	assert_int(answer.port).is_equal(PORT + 2)
	assert_int(answer.players).is_equal(1)
	game.ship_home = false
	game.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func test_a_game_not_living_in_the_ship_opens_no_discovery_socket() -> void:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.load_character = false
	game.clock = _clock
	game.make_transport = _transport
	add_child(game)
	auto_free(game)
	assert_bool(game.discovery.enabled).is_false()
	assert_bool(game.host(PORT + 1)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(game.discovery.responder.running()).is_false()
	game.leave()
	await get_tree().process_frame
	await get_tree().process_frame


## A Game living in the ship, its discovery on the test port and this machine only.
func _game() -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.ship_home = true
	game.load_character = false
	game.clock = _clock
	game.make_transport = _transport
	game.discovery.enabled = true
	game.discovery.responder.port = DISCOVERY_PORT
	game.discovery.responder.bind_address = "127.0.0.1"
	game.discovery.finder.port = DISCOVERY_PORT
	game.discovery.finder.targets = PackedStringArray(["127.0.0.1"])
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


func _in_lobby(game: Game) -> bool:
	if game.client() == null or game.client().model.own_peer == 0:
		return false
	return game.screen() == S.LOBBY and game.ui.screen == S.LOBBY


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()
