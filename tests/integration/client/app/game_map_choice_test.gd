extends GdUnitTestSuite
## A human match always loads the House (#767; the map pick of #627): a host and a client, two Game
## roots over a LoopbackHub on a simulated clock (as game_loop_test.gd, each in its own SubViewport
## world). Both lobbies start on the House, the mode's default map (the greybox, a test bench, is
## never a match's default), a guest's pick is refused, and the match then loads the House on both
## machines.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7420
const HOUSE := "res://levels/house/house.tscn"
const GREYBOX := "res://levels/greybox/greybox.tscn"
## The simulated clock moves this much per physics frame: five host ticks.
const STEP_USEC := 250000
const MAX_FRAMES := 600

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func test_a_human_match_loads_the_house_on_every_machine() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % PORT])
	var guest := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var games: Array[Game] = [host, guest]
	assert_bool(await _until(_all_on.bind(games, S.LOBBY, 2))).is_true()
	assert_bool(host.mode.maps.has(GREYBOX)).is_true()
	assert_str(host.mode.default_map()).is_equal(HOUSE)
	for game: Game in games:
		assert_str(game.client().model.map).is_equal(HOUSE)
	# A guest's pick is refused by the host: the map stays the House.
	guest.change_map(GREYBOX)
	host.change_setting(&"match_duration", 1)
	assert_bool(await _until(_setting_is.bind(games, &"match_duration", 1))).is_true()
	for game: Game in games:
		assert_str(game.client().model.map).is_equal(HOUSE)
	for game: Game in games:
		game.set_ready(true)
	assert_bool(await _until(_on_the_map.bind(games))).is_true()
	for game: Game in games:
		assert_str(game.level().scene_file_path).is_equal(HOUSE)
	# Leave as game_loop_test.gd does, so the levels and sessions are freed with the games.
	guest.leave()
	host.leave()
	var on_menu := func() -> bool: return host.screen() == S.MENU and guest.screen() == S.MENU
	assert_bool(await _until(on_menu)).is_true()
	for game: Game in games:
		assert_object(game.level()).is_null()
	await get_tree().process_frame
	await get_tree().process_frame


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
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


func _all_on(games: Array[Game], screen: S, players: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != screen or game.ui.screen != screen:
			return false
		if game.client().model.roster.size() != players:
			return false
	return true


func _setting_is(games: Array[Game], id: StringName, value: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.client().model.settings.get(id, -1) != value:
			return false
	return true


func _on_the_map(games: Array[Game]) -> bool:
	for game: Game in games:
		if game.level_kind() != PhaseSpec.Level.MAP or game.level() == null:
			return false
	return true
