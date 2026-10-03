extends GdUnitTestSuite
## The game (client/app/game.tscn, ARCHITECTURE §4.7) headless through a whole loop: a host and
## two clients, three Game roots in one tree, each in a physics world of its own, over a
## LoopbackHub on a simulated clock, go through the lobby, Ready, the countdown, loading, the
## round, time up, the end screen and back to the lobby, then a client leaves and the host closes.
## Each Game is driven through the methods its screens call (headless runs have no input); the
## screens themselves are `shot`.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7300
## The simulated clock moves this much per physics frame: five host ticks, so the 60 s round
## takes 240 frames.
const STEP_USEC := 250000
const MAX_FRAMES := 600
## Physics frames the players stand without input in the round: half a second at 60 Hz.
const HOLD_FRAMES := 30

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000
## Each game's Corrections so far, newest last.
var _corrections: Dictionary[Game, Array] = {}


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func test_a_host_and_two_clients_play_the_loop_and_back() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % PORT])
	var one := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var two := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var games: Array[Game] = [host, one, two]
	for game: Game in games:
		_corrections[game] = []
		game.client().corrected.connect(_on_corrected.bind(game))
	assert_bool(host.hosting()).is_true()
	assert_int(one.screen()).is_equal(S.CONNECTING)
	# The lobby: everyone welcomed, the lobby level under World, the player at its spot.
	assert_bool(await _until(games, _all_on.bind(games, S.LOBBY, 3))).is_true()
	for game: Game in games:
		assert_int(game.level_kind()).is_equal(PhaseSpec.Level.LOBBY)
		assert_str(game.level().scene_file_path).is_equal(game.mode.lobby_level)
		var model := game.client().model
		assert_vector(game.player().global_position).is_equal_approx(
			model.spots[model.own_peer], Vector3.ONE * 0.01
		)
	# Under the Esc menu nothing reads the keys, and a key held when it opened stops counting.
	host.open_esc()
	await get_tree().process_frame
	var held := host.player()
	held.move_input = Vector2(0, -1)
	held.sprint_held = true
	held.jump_requested = true
	await get_tree().process_frame
	assert_bool(held.reads_device_input).is_false()
	assert_vector(held.move_input).is_equal(Vector2.ZERO)
	assert_bool(held.sprint_held or held.jump_requested).is_false()
	host.ui.close_esc()
	# The host's setting reaches everyone; then Ready, the countdown and loading.
	host.change_setting(&"match_duration", 1)
	assert_bool(await _until(games, _setting_is.bind(games, &"match_duration", 1))).is_true()
	for game: Game in games:
		game.set_ready(true)
	assert_bool(await _until(games, _all_on.bind(games, S.ROUND, 3))).is_true()
	for game: Game in games:
		assert_int(game.level_kind()).is_equal(PhaseSpec.Level.MAP)
		assert_bool(game.mode.maps.has(game.level().scene_file_path)).is_true()
	# Loading placed everyone with a Correction: the player stands where it said.
	_assert_at_the_last_correction(games)
	# The round's screen lets the player read the keys again.
	await _drawn()
	for game: Game in games:
		assert_bool(game.player().reads_device_input).is_true()
	# The others are shown at the newest snapshot's positions.
	assert_bool(await _until(games, _avatars_shown.bind(games, 2))).is_true()
	# With no input everyone still stands there half a second later, the others' bodies drawn
	# around it (each Game has a physics world of its own, #238). The clock stands still.
	for i in HOLD_FRAMES:
		await get_tree().physics_frame
	_assert_at_the_last_correction(games)
	# Time up: the end screen names the winning side by its display name.
	assert_bool(await _until(games, _all_on.bind(games, S.END, 3))).is_true()
	await _drawn()
	for game: Game in games:
		var winner := game.mode.find_side(game.client().model.winner)
		assert_object(winner).is_not_null()
		assert_str(game.ui.end.winner_label.text).is_equal("The %s won" % winner.display_name)
		assert_bool(game.ui.end.back_button.visible).is_equal(game.hosting())
		# No click outside the end screen's button captures the mouse again.
		assert_bool(game.player().reads_device_input).is_false()
	# The host's Back to lobby: the lobby level again, the match's facts gone.
	host.return_to_lobby()
	assert_bool(await _until(games, _all_on.bind(games, S.LOBBY, 3))).is_true()
	for game: Game in games:
		assert_int(game.level_kind()).is_equal(PhaseSpec.Level.LOBBY)
		assert_str(game.level().scene_file_path).is_equal(game.mode.lobby_level)
	_assert_at_the_last_correction(games)
	# A client leaves; then the host closes, and the other client hears why.
	two.leave()
	assert_int(two.screen()).is_equal(S.MENU)
	assert_str(String(two.last_reason)).is_equal(String(ClientSession.LEFT))
	var stayed: Array[Game] = [host, one]
	assert_bool(await _until(games, _all_on.bind(stayed, S.LOBBY, 2))).is_true()
	host.leave()
	assert_bool(await _until(games, func() -> bool: return one.screen() == S.MENU)).is_true()
	assert_str(String(host.last_reason)).is_equal(String(EndReasons.CLOSED))
	assert_str(String(one.last_reason)).is_equal(String(ClientSession.HOST_LOST))
	assert_str(one.ui.menu.reason_label.text).contains(EndReasons.words(ClientSession.HOST_LOST))
	for game: Game in games:
		assert_object(game.level()).is_null()
		assert_object(game.player()).is_null()
		assert_object(game.client()).is_null()
	await get_tree().process_frame


func test_a_join_nobody_answers_returns_to_the_menu_with_the_reason() -> void:
	var lonely := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 1)])
	assert_bool(await _until([lonely], func() -> bool: return lonely.client() == null)).is_true()
	assert_int(lonely.screen()).is_equal(S.MENU)
	assert_str(String(lonely.last_reason)).is_equal(String(ClientSession.CONNECT_FAILED))
	assert_str(lonely.ui.menu.reason_label.text).contains("no answer from the host")
	await get_tree().process_frame


func test_a_host_that_cannot_start_stays_on_the_menu_and_says_why() -> void:
	var first := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 2)])
	assert_bool(first.hosting()).is_true()
	var second := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 2)])
	assert_bool(second.hosting()).is_false()
	assert_object(second.client()).is_null()
	assert_int(second.screen()).is_equal(S.MENU)
	assert_str(String(second.last_reason)).is_equal(String(EndReasons.CANNOT_HOST))
	assert_str(second.ui.menu.reason_label.text).contains(EndReasons.words(EndReasons.CANNOT_HOST))
	assert_bool(second.host(PORT + 2)).is_false()
	first.leave()
	await get_tree().process_frame


func test_a_port_alone_fills_the_menu_and_the_tree_gets_its_quit_back() -> void:
	var game := _game(["--port=%d" % (PORT + 3)])
	assert_int(game.screen()).is_equal(S.MENU)
	assert_int(game.ui.menu.port()).is_equal(PORT + 3)
	assert_bool(get_tree().auto_accept_quit).is_false()
	remove_child(game.get_parent())
	assert_bool(get_tree().auto_accept_quit).is_true()


## A Game in a SubViewport with a physics world of its own, as on its own machine (net_pair.gd
## does the same): in one shared world each Game's RemotePlayerBody of another player would stand
## inside that player's own PlayerController, and the push would slide every player off its spot.
func _game(args: Array[String]) -> Game:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	auto_free(viewport)
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = _clock
	game.make_transport = _transport
	viewport.add_child(game)
	return game


func _on_corrected(position: Vector3, _velocity: Vector3, game: Game) -> void:
	_corrections[game].append(position)


func _assert_at_the_last_correction(games: Array[Game]) -> void:
	for game: Game in games:
		assert_array(_corrections[game]).is_not_empty()
		var last: Vector3 = _corrections[game].back()
		assert_vector(game.player().global_position).is_equal_approx(last, Vector3.ONE * 0.01)


func _clock() -> int:
	return _now


func _transport() -> NetTransport:
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(_games: Array[Game], done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


## Waits until every Game has run its _process since the state `_until` saw: the screens' labels
## and buttons and the player's reads_device_input are written there, once a frame. Under load
## several physics frames run inside one idle frame, before its _process, and process_frame is
## emitted before that frame's _process: the second one comes after a _process that saw the state.
func _drawn() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _all_on(games: Array[Game], screen: S, players: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != screen:
			return false
		if game.client().model.roster.size() != players:
			return false
	return true


func _setting_is(games: Array[Game], id: StringName, value: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.client().model.settings.get(id, -1) != value:
			return false
	return true


func _avatars_shown(games: Array[Game], others: int) -> bool:
	for game: Game in games:
		if game.avatars().count() != others:
			return false
	return true
