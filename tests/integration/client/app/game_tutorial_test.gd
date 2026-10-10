extends GdUnitTestSuite
## The solo tutorial session in the game (Game.start_tutorial, client/app/game_tutorial.gd,
## docs/design/tutorial.md §2.1, §5: E62, E69, E70, E71; #601), headless on a simulated clock: the
## tutorial mode hosted on a private LoopbackHub with the two stand-ins, the loading screen until
## the lessons, both stages (raise_stage downs a stand-in, death_stage kills the own player, who
## respawns), Leave with no question, no replay, the base mode again after it, and when a launch
## starts it by itself. Like game_loop_test, the Game sits in a SubViewport with its own World3D.

const GAME := preload("res://client/app/game.tscn")
const TUTORIAL := "res://content/modes/tutorial_mode.tres"
const BASE := "res://content/modes/base_mode.tres"
const PORT := 7320
## Five host ticks per physics frame, as in game_loop_test.
const STEP_USEC := 250000
const MAX_FRAMES := 600
## Physics frames the players stand without input: half a second at 60 Hz.
const HOLD_FRAMES := 30
const SETTINGS_PATH := "user://game_tutorial_test.cfg"

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000
## How often a Game asked for a networked transport (make_transport).
var _made := 0


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000
	_made = 0


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func test_the_tutorial_runs_to_the_lessons_and_through_both_stages() -> void:
	var game := _game([])
	assert_int(game.screen()).is_equal(S.MENU)
	assert_bool(game.start_tutorial()).is_true()
	assert_bool(game.start_tutorial()).is_false()
	assert_str(game.mode.resource_path).is_equal(TUTORIAL)
	assert_bool(game.tutorial.running).is_true()
	assert_bool(game.tutorial.invite_open).is_false()
	assert_int(game.tutorial.stand_ins()).is_equal(2)
	# The tutorial hosts, but not for anyone else: no question on Leave, no host-only settings.
	assert_bool(game.hosting()).is_false()
	# gather has no level: Loading until the lessons, never the round, and no level under World.
	var seen: Dictionary[S, bool] = {}
	var phases: Dictionary[StringName, bool] = {}
	var to_lessons := func() -> bool:
		var model := game.client().model
		if model.own_peer != 0 and model.phase != &"lessons":
			seen[game.screen()] = true
			phases[model.phase] = true
			if model.phase == &"gather":
				assert_int(game.level_kind()).is_equal(PhaseSpec.Level.NONE)
		return model.phase == &"lessons" and game.ui.screen == S.ROUND
	assert_bool(await _until(to_lessons)).is_true()
	assert_bool(phases.has(&"gather")).is_true()
	assert_array(seen.keys()).contains_exactly([S.LOADING])
	assert_int(game.level_kind()).is_equal(PhaseSpec.Level.MAP)
	assert_str(game.level().scene_file_path).is_equal(game.mode.maps[0])
	# The own player is peer 1 and readied itself (no Ready key); the stand-ins are 2 and 3, named
	# by the host as any joiner, and drawn at their spots.
	var model := game.client().model
	assert_int(model.own_peer).is_equal(NetTransport.HOST_ID)
	assert_array(model.roster.keys()).contains_exactly_in_any_order([1, 2, 3])
	assert_bool((model.roster[1] as ClientModel.Member).ready).is_true()
	var two := (model.roster[2] as ClientModel.Member).name
	var three := (model.roster[3] as ClientModel.Member).name
	# The stand-ins join once the own player is in: the host names them after it (design §2.2).
	assert_array([(model.roster[1] as ClientModel.Member).name, two, three]).contains_exactly(
		["Player1", "Player2", "Player3"]
	)
	await _hold()
	assert_object(game.avatars().body_of(2)).is_not_null()
	assert_object(game.avatars().body_of(3)).is_not_null()
	assert_int(game.client().corrections).is_equal(0)
	assert_vector(game.player().global_position).is_equal_approx(
		model.spots[model.own_peer], Vector3.ONE * 0.05
	)
	# Stage 1 (lesson 6): the first stand-in goes down.
	game.client().send_intent(Intents.NEXT_STAGE)
	assert_bool(await _until(func() -> bool: return model.phase == &"raise_stage")).is_true()
	assert_int(model.life_of(2)).is_equal(ClientModel.Life.DOWNED)
	assert_int(model.life_of(3)).is_equal(ClientModel.Life.ALIVE)
	assert_int(game.screen()).is_equal(S.ROUND)
	# Stage 2 (lesson 7): the own player dies, then respawns after respawn_s.
	game.client().send_intent(Intents.NEXT_STAGE)
	assert_bool(await _until(func() -> bool: return model.phase == &"death_stage")).is_true()
	var own_life := func(life: ClientModel.Life) -> bool: return model.life_of(1) == life
	assert_bool(await _until(own_life.bind(ClientModel.Life.DEAD))).is_true()
	assert_bool(await _until(own_life.bind(ClientModel.Life.ALIVE))).is_true()
	assert_int(game.screen()).is_equal(S.ROUND)
	assert_int(_made).is_equal(0)
	game.leave()
	await _settle()


func test_leave_ends_it_at_once_and_a_networked_session_after_it_uses_the_base_mode() -> void:
	var game := _game([])
	var base := game.mode
	assert_str(base.resource_path).is_equal(BASE)
	var replays := ReplayFiles.list()
	assert_bool(game.start_tutorial()).is_true()
	assert_bool(await _until(func() -> bool: return game.screen() == S.ROUND)).is_true()
	# The Esc menu is its tutorial variant (#491): Game, Guide and Settings, Game shown.
	game.open_esc()
	var esc := game.ui.esc.state
	assert_bool(esc.tutorial).is_true()
	assert_array(esc.tabs()).contains_exactly(
		[EscMenuState.Tab.GAME, EscMenuState.Tab.GUIDE, EscMenuState.Tab.SETTINGS]
	)
	assert_int(esc.selected).is_equal(EscMenuState.Tab.GAME)
	# The Game page's Leave acts at once: no "end the session for every player?".
	game.ui.esc.press_leave()
	assert_bool(esc.asking()).is_false()
	assert_bool(game.ui.esc_open()).is_false()
	assert_object(game.client()).is_null()
	assert_int(game.screen()).is_equal(S.MENU)
	assert_str(String(game.failure)).is_empty()
	assert_str(String(game.last_reason)).is_equal(String(EndReasons.CLOSED))
	assert_object(game.level()).is_null()
	assert_object(game.player()).is_null()
	assert_bool(game.tutorial.running).is_false()
	assert_int(game.tutorial.stand_ins()).is_equal(0)
	assert_object(game.get_node_or_null(GameTutorial.STAND_INS_NAME)).is_null()
	assert_object(game.mode).is_same(base)
	# The menu is the networked one again.
	assert_bool(esc.tutorial).is_false()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(game.get_node_or_null("HostNode")).is_null()
	# The tutorial's host wrote no replay (it would push a match's out of ReplayFiles.KEEP).
	assert_array(ReplayFiles.list()).contains_exactly(replays)
	# A networked host after it plays the base mode.
	assert_bool(game.host(PORT)).is_true()
	assert_bool(game.hosting()).is_true()
	assert_int(_made).is_equal(1)
	assert_bool(await _until(func() -> bool: return game.screen() == S.LOBBY)).is_true()
	assert_str(game.mode.resource_path).is_equal(BASE)
	assert_str(String(game.client().model.phase)).is_equal("lobby")
	game.leave()
	await _settle()


func test_a_launch_starts_it_by_itself_only_on_a_first_launch() -> void:
	# E70: no option, settings from a file and the flag absent: with the invite.
	var first := _game([], _file_settings(false))
	assert_bool(first.tutorial.running).is_true()
	assert_bool(first.tutorial.invite_open).is_true()
	# Its end counts as seen until #492's Start and Skip set the flag: written to the file.
	first.leave()
	assert_bool(first.tutorial.running).is_false()
	var back := UserSettings.new(SETTINGS_PATH)
	assert_int(back.read()).is_equal(OK)
	assert_bool(back.tutorial_seen).is_true()
	# The flag set, any option, or settings in memory (every test and runner window): the menu.
	assert_int(_game([], _file_settings(true)).screen()).is_equal(S.MENU)
	assert_int(_game(["--port=24999"], _file_settings(false)).screen()).is_equal(S.MENU)
	var in_memory := _game([])
	assert_int(in_memory.screen()).is_equal(S.MENU)
	assert_bool(in_memory.tutorial.running).is_false()
	# --tutorial (playcheck) starts it without the invite; a wrong launch starts nothing.
	var tooling := _game(["--tutorial"])
	assert_bool(tooling.tutorial.running).is_true()
	assert_bool(tooling.tutorial.invite_open).is_false()
	assert_bool(tooling.hosting()).is_false()
	var wrong := _game(["--tutorial", "--host"])
	assert_bool(wrong.tutorial.running).is_false()
	assert_object(wrong.client()).is_null()
	assert_str(wrong.options.problem).contains("--tutorial")
	# The main menu's Tutorial starts it without the invite (the item stays off until #492).
	assert_bool(in_memory.ui.menu.tutorial_item.disabled).is_true()
	in_memory.ui.menu.tutorial_requested.emit()
	assert_bool(in_memory.tutorial.running).is_true()
	assert_bool(in_memory.tutorial.invite_open).is_false()
	for game: Game in [first, tooling, in_memory]:
		game.leave()
	assert_int(_made).is_equal(0)
	await _settle()


func test_only_a_seen_invite_marks_the_tutorial_seen() -> void:
	# A tutorial without the invite (the menu, --tutorial) leaves the flag as it was.
	var plain := _game(["--port=24997"], _file_settings(false))
	plain.start_tutorial()
	assert_bool(plain.tutorial.running).is_true()
	plain.leave()
	var back := UserSettings.new(SETTINGS_PATH)
	back.read()
	assert_bool(back.tutorial_seen).is_false()
	# A first launch whose host cannot start (the port is taken in its hub) never showed the
	# invite: the flag stays absent, and Try again starts it without the invite.
	var failing := _game(["--port=24998"], _file_settings(false))
	var taken := LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)
	assert_int(taken.host(GameTutorial.PORT, 4)).is_equal(OK)
	failing.tutorial.hub = _hub
	assert_bool(failing.start_tutorial(true)).is_false()
	assert_bool(failing.tutorial.running).is_false()
	assert_bool(failing.tutorial.invite_open).is_false()
	assert_int(failing.screen()).is_equal(S.FAILURE)
	assert_bool(failing.ui.esc.state.tutorial).is_false()
	assert_str(String(failing.ui.connecting.state())).is_equal("host-failed")
	assert_object(failing.mode).is_same(load(BASE))
	back.read()
	assert_bool(back.tutorial_seen).is_false()
	taken.close()
	failing.retry()
	assert_bool(failing.tutorial.running).is_true()
	assert_bool(failing.tutorial.invite_open).is_false()
	failing.leave()
	back.read()
	assert_bool(back.tutorial_seen).is_false()
	await _settle()


func test_it_does_not_start_while_a_session_runs() -> void:
	var game := _game([])
	var base := game.mode
	assert_bool(game.host(PORT)).is_true()
	assert_bool(game.start_tutorial()).is_false()
	assert_bool(game.tutorial.running).is_false()
	assert_object(game.mode).is_same(base)
	assert_bool(game.hosting()).is_true()
	var hosts := game.get_children().filter(func(n: Node) -> bool: return n is HostNode)
	assert_int(hosts.size()).is_equal(1)
	game.leave()
	await _settle()
	# And not twice: a second start while the tutorial runs changes nothing.
	assert_bool(game.start_tutorial()).is_true()
	var mode := game.mode
	assert_bool(game.start_tutorial()).is_false()
	assert_object(game.mode).is_same(mode)
	game.leave()
	await _settle()


## Settings under user:// (a path, as a real launch reads), the tutorial flag as given.
func _file_settings(seen: bool) -> UserSettings:
	var settings := UserSettings.new(SETTINGS_PATH)
	settings.tutorial_seen = seen
	return settings


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


func _clock() -> int:
	return _now


func _transport() -> NetTransport:
	_made += 1
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


func _hold() -> void:
	for i in HOLD_FRAMES:
		_now += STEP_USEC
		await get_tree().physics_frame


## The nodes a Leave queued for freeing go before the test ends (orphans fail it).
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
