extends GdUnitTestSuite
## The game (client/app/game.tscn, ARCHITECTURE §4.7) headless through a whole loop: a host and
## two clients, three Game roots in one tree over a LoopbackHub on a simulated clock, go through
## the lobby, Ready, the countdown, loading, the round, time up, the end screen and back to the
## lobby, then a client leaves and the host closes. Each Game is driven through the methods its
## screens call (headless runs have no input); the screens themselves are `shot`.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7300
## The simulated clock moves this much per physics frame: five host ticks, so the 60 s round
## takes 240 frames.
const STEP_USEC := 250000
const MAX_FRAMES := 600

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func test_a_host_and_two_clients_play_the_loop_and_back() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % PORT])
	var one := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var two := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var games: Array[Game] = [host, one, two]
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
	# The host's setting reaches everyone; then Ready, the countdown and loading.
	host.change_setting(&"match_duration", 1)
	assert_bool(await _until(games, _setting_is.bind(games, &"match_duration", 1))).is_true()
	for game: Game in games:
		game.set_ready(true)
	assert_bool(await _until(games, _all_on.bind(games, S.ROUND, 3))).is_true()
	for game: Game in games:
		assert_int(game.level_kind()).is_equal(PhaseSpec.Level.MAP)
		assert_bool(game.mode.maps.has(game.level().scene_file_path)).is_true()
		assert_bool(game.player().reads_device_input).is_true()
	# The others are shown at the newest snapshot's positions.
	assert_bool(await _until(games, _avatars_shown.bind(games, 2))).is_true()
	# Time up: the end screen names the winning side by its display name.
	assert_bool(await _until(games, _all_on.bind(games, S.END, 3))).is_true()
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


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = _clock
	game.make_transport = _transport
	add_child(game)
	auto_free(game)
	return game


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
