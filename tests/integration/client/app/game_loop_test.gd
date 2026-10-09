extends GdUnitTestSuite
## The game (client/app/game.tscn, ARCHITECTURE §4.7) headless through a whole loop: a host and
## two clients, three Game roots in one tree over a LoopbackHub on a simulated clock, go through
## the lobby, Ready, the countdown, loading, the round, time up, the end screen and, 3 s later with
## no intent, back to the lobby, then a client leaves and the host closes. Each Game is driven
## through the methods its screens call (headless runs have no input); the screens themselves are
## `shot`.
##
## Each Game sits in a SubViewport with its own World3D, as on three machines (like NetPair): in
## one shared physics space each player stood inside the body another game drew of it and was
## pushed off its spot (#225, #238).
##
## The sessions fold the host's messages in physics steps, and under load several steps run in
## one idle frame before Game._process shows the screen, so every wait for a screen also waits for
## the Game to show it (#225). The player's step and input flags follow the phase from the physics
## step that folds it: a loop with no Game._process from the lobby on proves it (#241).

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
		assert_bool(game.player().reads_device_input).is_true()
	# Loading placed everyone with a Correction: the player stands where it said.
	_assert_at_the_last_correction(games)
	# The others are shown at the newest snapshot's positions.
	assert_bool(await _until(games, _avatars_shown.bind(games, 2))).is_true()
	# With no input everyone still stands there half a second later, the others' bodies drawn
	# around it (each Game has a physics world of its own, #238). The clock stands still.
	for i in HOLD_FRAMES:
		await get_tree().physics_frame
	_assert_at_the_last_correction(games)
	# Time up, with no Game._process (as when physics steps run ahead of it under load, #225): the
	# model reaches the end screen, nothing has shown it yet, and a wait for it does not stop there.
	for game: Game in games:
		game.set_process(false)
	assert_bool(await _until(games, _models_on.bind(games, S.END))).is_true()
	assert_bool(_all_on(games, S.END, 3)).is_false()
	for game: Game in games:
		game.set_process(true)
	# The end screen names the winning side (#498): on the title plate for its players, as plain
	# text for the others.
	assert_bool(await _until(games, _all_on.bind(games, S.END, 3))).is_true()
	for game: Game in games:
		var model := game.client().model
		assert_object(game.mode.find_side(model.winner)).is_not_null()
		var won := game.mode.find_role(model.role).side == model.winner
		var shown := game.ui.end.winner_shown()
		assert_object(shown).is_same(game.ui.end.winner_label if won else game.ui.end.loser_label)
		assert_bool(shown.is_visible_in_tree()).is_true()
		assert_str(shown.text).is_equal(EndScreen.SIDE_KEYS[model.winner])
		# Everyone, the host too, sees the countdown to the lobby and no button (#212).
		assert_str(game.ui.end.countdown_label.text).starts_with("Back to the lobby in ")
		assert_array(game.ui.end.find_children("*", "BaseButton", true, false)).is_empty()
		assert_bool(game.player().reads_device_input).is_false()
	# With no intent, End's 3 s pass: the lobby level again, the match's facts gone.
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
	# The host's own leaving goes straight to the menu; the client sees `lost` first (#494).
	assert_int(host.screen()).is_equal(S.MENU)
	assert_bool(await _until(games, func() -> bool: return one.screen() == S.FAILURE)).is_true()
	assert_str(String(one.ui.connecting.state())).is_equal("lost")
	assert_str(String(host.last_reason)).is_equal(String(EndReasons.CLOSED))
	assert_str(String(one.last_reason)).is_equal(String(ClientSession.HOST_LOST))
	assert_str(one.ui.menu.reason_label.text).contains(EndReasons.words(ClientSession.HOST_LOST))
	one.back_to_menu()
	assert_int(one.screen()).is_equal(S.MENU)
	for game: Game in games:
		assert_object(game.level()).is_null()
		assert_object(game.player()).is_null()
		assert_object(game.client()).is_null()
	await get_tree().process_frame


func test_physics_steps_alone_stop_the_player_at_each_frozen_phase() -> void:
	# From the lobby on no Game._process runs, as when physics steps run ahead of it under load
	# (#225's method): the frozen state and the input flags follow each phase from the physics step
	# that folds it (#241). Before, a player walking in the countdown kept walking (and falling,
	# with no level) through Loading, and on past the round's placement.
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 5)])
	var one := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 5)])
	var two := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 5)])
	var games: Array[Game] = [host, one, two]
	for game: Game in games:
		game.device_input = false
		_corrections[game] = []
		game.client().corrected.connect(_on_corrected.bind(game))
	assert_bool(await _until(games, _all_on.bind(games, S.LOBBY, 3))).is_true()
	host.change_setting(&"match_duration", 1)
	assert_bool(await _until(games, _setting_is.bind(games, &"match_duration", 1))).is_true()
	for game: Game in games:
		game.set_process(false)
		game.player().move_input = Vector2(0, 1)
		game.set_ready(true)
	var found: Dictionary[Game, Vector3] = {}
	var stepped: Dictionary[Game, int] = {}
	var watch := _round_watching_loading.bind(games, found, stepped)
	assert_bool(await _until(games, watch)).is_true()
	assert_int(found.size()).is_equal(games.size())
	assert_int(stepped.size()).is_equal(0)
	# The round's placement: everyone stands where it said.
	_assert_at_the_last_correction(games)
	# Time up; then the host's ReturnToLobby, still with no Game._process. End -> Lobby drops the
	# others' bodies and places everyone in one host step, and the greybox lobby's markers share
	# the round's coordinates: the player, stepping again from the next physics step, is pushed off
	# its lobby Correction neither by a dropped body still in the space (#242) nor by another
	# player drawn at its round spot from the round's snapshots behind the interpolation delay
	# (seen in about half the runs before AvatarViews forgot them, as the spots are random).
	assert_bool(await _until(games, _models_on.bind(games, S.END))).is_true()
	for game: Game in games:
		assert_bool(game.player().is_physics_processing()).is_false()
		assert_bool(game.player().reads_device_input).is_false()
	host.return_to_lobby()
	assert_bool(await _until(games, _models_on.bind(games, S.LOBBY))).is_true()
	# Three steps with the clock held, so a stale pose would stay drawn; then the others again.
	for frame in 3:
		await get_tree().physics_frame
	assert_bool(await _until(games, _avatars_shown.bind(games, 2))).is_true()
	for game: Game in games:
		assert_bool(game.player().is_physics_processing()).is_true()
	_assert_at_the_last_correction(games)
	for game: Game in games:
		assert_int(game.client().corrections).is_equal(0)
		game.set_process(true)
	host.leave()
	await get_tree().process_frame


func test_a_join_nobody_answers_shows_why_then_back_keeps_the_address() -> void:
	var lonely := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 1)])
	assert_bool(await _until([lonely], func() -> bool: return lonely.client() == null)).is_true()
	assert_int(lonely.screen()).is_equal(S.FAILURE)
	assert_str(String(lonely.ui.connecting.state())).is_equal("fail-no-answer")
	assert_str(String(lonely.last_reason)).is_equal(String(ClientSession.CONNECT_FAILED))
	assert_str(lonely.ui.menu.reason_label.text).contains("no answer from the host")
	# Try again joins the same address; it fails alike.
	lonely.ui.connecting.retry_requested.emit()
	assert_object(lonely.client()).is_not_null()
	assert_int(lonely.screen()).is_equal(S.CONNECTING)
	assert_bool(await _until([lonely], func() -> bool: return lonely.client() == null)).is_true()
	assert_int(lonely.screen()).is_equal(S.FAILURE)
	# Back: the menu, the address and port as the command line gave them.
	lonely.ui.connecting.back_requested.emit()
	assert_int(lonely.screen()).is_equal(S.MENU)
	assert_str(lonely.ui.menu.address_edit.text).is_equal("127.0.0.1")
	assert_int(lonely.ui.menu.port()).is_equal(PORT + 1)
	await get_tree().process_frame


func test_a_host_that_cannot_start_says_why_and_tries_again_the_same_way() -> void:
	var first := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 2)])
	assert_bool(first.hosting()).is_true()
	var second := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 2)])
	assert_bool(second.hosting()).is_false()
	assert_object(second.client()).is_null()
	assert_int(second.screen()).is_equal(S.FAILURE)
	assert_str(String(second.ui.connecting.state())).is_equal("host-failed")
	assert_str(String(second.last_reason)).is_equal(String(EndReasons.CANNOT_HOST))
	assert_str(second.ui.menu.reason_label.text).contains(EndReasons.words(EndReasons.CANNOT_HOST))
	assert_bool(second.host(PORT + 2)).is_false()
	# Try again hosts on the same port: it starts once the port is free.
	first.leave()
	second.ui.connecting.retry_requested.emit()
	assert_bool(second.hosting()).is_true()
	second.leave()
	assert_int(second.screen()).is_equal(S.MENU)
	await get_tree().process_frame


func test_a_port_alone_fills_the_menu_and_the_tree_gets_its_quit_back() -> void:
	var game := _game(["--port=%d" % (PORT + 3)])
	assert_int(game.screen()).is_equal(S.MENU)
	assert_int(game.ui.menu.port()).is_equal(PORT + 3)
	assert_bool(get_tree().auto_accept_quit).is_false()
	game.get_parent().remove_child(game)
	assert_bool(get_tree().auto_accept_quit).is_true()


func test_the_game_makes_the_buses_and_its_voices_under_the_world() -> void:
	var game := _game([])
	for bus: StringName in [AudioBuses.VOICE, AudioBuses.EFFECTS, AudioBuses.MUSIC]:
		assert_int(AudioBuses.index_of(bus)).is_greater(0)
	assert_object(game.voices().get_parent()).is_same(game.get_node(^"World"))
	# The addon's codec by default: unavailable where the addon is absent, and then nothing plays.
	assert_object(game.voice_codec).is_instanceof(TwoVoipCodec)
	assert_object(game.life().ears()).is_not_null()


func test_the_name_in_the_settings_is_the_name_the_game_asks_for() -> void:
	# Game hands UserSettings.player_name to its session (#550): the host names the joiner by it,
	# and a second player asking for the same name gets the suffix.
	var saved := UserSettings.new()
	saved.player_name = "Діма"
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 6)])
	var one := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 6)], saved)
	var two := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 6)], saved)
	var games: Array[Game] = [host, one, two]
	assert_str(one.client().player_name).is_equal("Діма")
	assert_bool(await _until(games, _all_on.bind(games, S.LOBBY, 3))).is_true()
	var names: Array[String] = []
	for member: ClientModel.Member in host.client().model.roster.values():
		names.append(member.name)
	names.sort()
	assert_array(names).contains_exactly(["Player1", "Діма", "Діма 2"])
	# The host's Lobby tab names the lobby (#214): Game sends it cleaned (a pasted zero-width
	# character would make the wire refuse it), and every model has it.
	# Once welcomed, the connecting screen's title names the lobby: the default, then the host's.
	for game: Game in games:
		assert_str(game.client().model.lobby_name).is_empty()
		assert_str(game.client().model.host_name()).is_equal("Player1")
		assert_str(game.ui.connecting.title_label.text).contains("Player1")
	host.ui.esc.lobby.lobby_name_changed.emit("Dima's" + String.chr(0x200B) + " den")
	assert_bool(await _until(games, _lobby_name_is.bind(games, "Dima's den"))).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	for game: Game in games:
		assert_str(game.ui.connecting.title_label.text).contains("Dima's den")
	two.leave()
	one.leave()
	host.leave()
	await get_tree().process_frame


func test_a_session_end_forgets_the_voices_flushes() -> void:
	# Host ticks start again at 0 in the next session and the host is always peer 1: a flush kept
	# from this session would mute it there until the new ticks passed the old one.
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 4)])
	var welcomed := func() -> bool: return host.client().model.own_peer != 0
	assert_bool(await _until([host], welcomed)).is_true()
	var voices := host.voices()
	voices.on_snapshot(500, {})
	voices.fade(2)
	assert_int(voices.flushed_at(2)).is_equal(500)
	host.leave()
	assert_object(host.client()).is_null()
	assert_int(voices.flushed_at(2)).is_equal(-1)
	assert_object(voices.model).is_null()
	await get_tree().process_frame


func _game(args: Array[String], settings: UserSettings = null) -> Game:
	var game := GAME.instantiate() as Game
	game.settings = settings
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
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


## Every game is on `screen` with `players` in its roster, and its Game._process has shown that
## screen: the screens' texts change only there (the player's flags follow each event, #241).
func _all_on(games: Array[Game], screen: S, players: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != screen or game.ui.screen != screen:
			return false
		if game.client().model.roster.size() != players:
			return false
	return true


## Every game's model is on `screen`, whether or not its Game has shown it yet.
func _models_on(games: Array[Game], screen: S) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != screen:
			return false
	return true


## Every game's model is on the round. Until then each game whose model is in Loading counts in
## `stepped` every physics frame its player still steps or stands off where Loading found it
## (`found`), checked at the start of each physics frame, after the steps of the frame before.
func _round_watching_loading(
	games: Array[Game], found: Dictionary[Game, Vector3], stepped: Dictionary[Game, int]
) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != S.LOADING:
			continue
		var player := game.player()
		if not found.has(game):
			found[game] = player.global_position
		if player.is_physics_processing() or player.global_position != found[game]:
			stepped[game] = stepped.get(game, 0) + 1
	return _models_on(games, S.ROUND)


func _setting_is(games: Array[Game], id: StringName, value: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.client().model.settings.get(id, -1) != value:
			return false
	return true


func _lobby_name_is(games: Array[Game], lobby: String) -> bool:
	for game: Game in games:
		if game.client() == null or game.client().model.lobby_name != lobby:
			return false
	return true


func _avatars_shown(games: Array[Game], others: int) -> bool:
	for game: Game in games:
		if game.avatars().count() != others:
			return false
	return true
