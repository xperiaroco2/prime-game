extends GdUnitTestSuite
## The nine lessons in the game (client/app/game_tutorial.gd's runner over
## content/tutorial/tutorial.tres, docs/design/tutorial.md §1, §3, §5; #602), headless on a
## simulated clock as game_tutorial_test: the own player walks, picks up, delivers, swaps, opens
## the map and a card by its «?», raises the stand-in the host knocked down after the runner's own
## NextStage, dies after the second, switches the spectate target, respawns, waits 3 s near a
## stand-in with no microphone (D31 (a)), and opens and closes the Esc menu: the session ends at
## the main menu (D32 (b)). And when the lessons begin: by themselves without the invite, on
## begin() with it. No step feeds the runner by hand: the item keys' intents go out through the own
## session, the raise through LifeView, the card through its «?» button, the rest through Game.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7321
## Five host ticks per physics frame while nothing moves, as in game_tutorial_test.
const STEP_USEC := 250000
## One physics frame at 60 Hz while the own player walks: its claims cover what the host settles.
const WALK_USEC := 16667
const MAX_FRAMES := 900
const SETTINGS_PATH := "user://game_tutorial_lessons_test.cfg"
## Metres from an item's or a downed player's feet the own player stops at: inside the reach.
const NEAR_M := 1.0

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func test_the_nine_lessons_run_on_the_real_session_and_end_at_the_main_menu() -> void:
	var game := _game([])
	assert_bool(game.start_tutorial()).is_true()
	var runner := game.tutorial.runner
	assert_object(runner).is_not_null()
	assert_int(runner.lesson()).is_equal(0)
	# Without the invite, lesson 1 begins as the lessons phase comes in.
	var in_room := func() -> bool: return runner.lesson() == 1 and game.ui.screen == S.ROUND
	assert_bool(await _until(in_room)).is_true()
	var model := game.client().model
	var own := model.own_peer
	var package := _item_of(model, &"package")
	var knife := _item_of(model, &"knife")
	# 1: walking 1 s in all, from the own claims: a short walk is not enough.
	assert_bool(await _walk(game, Vector3(2, 0, 4), 0.3)).is_true()
	assert_int(runner.lesson()).is_equal(1)
	assert_bool(await _walk(game, Vector3(6, 0, 7), 0.3)).is_true()
	assert_bool(await _walk(game, model.items[package].position, NEAR_M)).is_true()
	assert_bool(runner.is_done(1)).is_true()
	assert_int(runner.lesson()).is_equal(2)
	# 2 (a): the package picked up (the knife is refused by the runner unit test, ItemKindIs);
	# (b): the package put down, here in its circle.
	game.client().send_intent(Intents.PICK_UP, {"item": package})
	assert_bool(await _until(func() -> bool: return runner.step() == 2)).is_true()
	var circle: ClientModel.Station = model.stations[model.items[package].station]
	assert_bool(await _walk(game, circle.position, 0.2)).is_true()
	game.client().send_intent(Intents.PUT_DOWN, {"facing": Vector3.DOWN})
	assert_bool(await _until(func() -> bool: return runner.lesson() == 3)).is_true()
	assert_bool(await _until(func() -> bool: return model.tasks_done == 1)).is_true()
	# 3: the knife in the hand, then Swap; 4 is done on entry (the task is), so 5 shows.
	assert_bool(await _walk(game, model.items[knife].position, NEAR_M)).is_true()
	game.client().send_intent(Intents.PICK_UP, {"item": knife})
	assert_bool(await _until(func() -> bool: return model.hand_item(own) == knife)).is_true()
	assert_int(runner.lesson()).is_equal(3)
	game.client().send_intent(Intents.SWAP)
	assert_bool(await _until(func() -> bool: return runner.lesson() == 5)).is_true()
	assert_bool(runner.is_done(4)).is_true()
	assert_str(String(model.phase)).is_equal("lessons")
	# 5: the map, then a card from its «?» (the button's own press).
	game.ui.open_map()
	assert_int(runner.step()).is_equal(2)
	await _settle()
	var helps := game.ui.map.find_children("Help", "Button", true, false)
	assert_array(helps).is_not_empty()
	(helps[0] as Button).pressed.emit()
	# 6: the runner's own NextStage: the host knocks the first stand-in down.
	assert_bool(await _until(func() -> bool: return model.phase == &"raise_stage")).is_true()
	assert_int(runner.lesson()).is_equal(6)
	game.ui.close_map()
	var downed := _downed(model)
	assert_int(downed).is_not_equal(0)
	var at: Vector3 = (model.avatars[downed] as Dictionary)["position"]
	assert_bool(await _walk(game, at, NEAR_M + 0.2)).is_true()
	# E held on it under the crosshair, as the player does.
	_aim(game.player(), at)
	assert_bool(await _until(func() -> bool: return game.life().raise_target() == downed)).is_true()
	game.life().press_raise()
	assert_bool(await _until(func() -> bool: return model.is_alive(downed))).is_true()
	game.life().release_raise()
	# 7: its NextStage kills the own player; a switch of the target completes it while dead.
	assert_bool(await _until(func() -> bool: return model.phase == &"death_stage")).is_true()
	assert_int(runner.lesson()).is_equal(7)
	assert_bool(await _until(func() -> bool: return not model.is_alive(own))).is_true()
	assert_bool(await _until(func() -> bool: return game.life().target() != 0)).is_true()
	game.life().cycle_target(1)
	assert_bool(runner.is_done(7)).is_true()
	# 8 waits for the respawn, then 3 s near a stand-in with no microphone open.
	assert_int(runner.lesson()).is_equal(0)
	assert_bool(await _until(func() -> bool: return model.is_alive(own))).is_true()
	assert_int(runner.lesson()).is_equal(8)
	assert_bool(game.sender().live()).is_false()
	assert_bool(await _until(func() -> bool: return runner.lesson() == 9)).is_true()
	# 9: the Esc menu opens; as it closes the tutorial ends at the main menu, with no failure.
	game.open_esc()
	assert_bool(runner.is_done(9)).is_true()
	assert_bool(game.tutorial.running).is_true()
	game.close_esc()
	assert_bool(runner.is_finished()).is_true()
	assert_bool(game.tutorial.running).is_false()
	assert_object(game.tutorial.runner).is_null()
	assert_object(game.client()).is_null()
	assert_int(game.screen()).is_equal(S.MENU)
	assert_str(String(game.failure)).is_empty()
	assert_str(String(game.last_reason)).is_equal(String(EndReasons.CLOSED))
	await _settle()


func test_with_the_invite_the_lessons_wait_for_begin() -> void:
	var first := _game([], _file_settings(false))
	assert_bool(first.tutorial.invite_open).is_true()
	var runner := first.tutorial.runner
	assert_bool(await _until(func() -> bool: return first.ui.screen == S.ROUND)).is_true()
	await _hold()
	assert_int(runner.lesson()).is_equal(0)
	assert_bool(runner.is_running()).is_false()
	# #492's Start.
	first.tutorial.begin(first)
	assert_int(runner.lesson()).is_equal(1)
	first.tutorial.begin(first)
	assert_int(runner.lesson()).is_equal(1)
	# Leave drops it; the menu's Tutorial starts a fresh one at lesson 1, the old one hears nothing.
	first.leave()
	assert_object(first.tutorial.runner).is_null()
	await _settle()
	first.ui.menu.tutorial_requested.emit()
	var again := first.tutorial.runner
	assert_object(again).is_not_same(runner)
	assert_bool(await _until(func() -> bool: return again.lesson() == 1)).is_true()
	first.ui.open_map()
	first.open_esc()
	first.close_esc()
	assert_int(again.lesson()).is_equal(1)
	assert_int(runner.lesson()).is_equal(1)
	assert_bool(runner.is_done(1)).is_false()
	first.leave()
	await _settle()


func _item_of(model: ClientModel, kind: StringName) -> int:
	for id: int in model.items:
		if model.items[id].kind == kind:
			return id
	return -1


func _downed(model: ClientModel) -> int:
	for peer: int in model.roster:
		if model.life_of(peer) == ClientModel.Life.DOWNED:
			return peer
	return 0


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
	game.clock = func() -> int: return _now
	game.make_transport = func() -> NetTransport: return null
	game.device_input = false
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	return game


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


## Walks the own player towards `to` (its feet, across the floor) until within `near` metres.
func _walk(game: Game, to: Vector3, near: float) -> bool:
	var player := game.player()
	for i in MAX_FRAMES:
		var gap := to - player.global_position
		gap.y = 0.0
		if gap.length() <= near:
			player.move_input = Vector2.ZERO
			await _hold()
			return true
		var way := gap.normalized()
		player.move_input = Vector2(way.dot(player.global_basis.x), way.dot(-player.global_basis.z))
		_now += WALK_USEC
		await get_tree().physics_frame
	player.move_input = Vector2.ZERO
	return false


## Turns `player` to face a body lying at `feet` and tilts its head down onto it.
func _aim(player: PlayerController, feet: Vector3) -> void:
	var gap := feet - player.global_position
	gap.y = 0.0
	player.look(atan2(-gap.x, -gap.z) - player.rotation.y, 0.0)
	player.look_level()
	var eye := player.get_camera().global_position.y - feet.y
	player.look(0.0, -atan2(eye - 0.3, gap.length()))


func _hold() -> void:
	for i in 30:
		_now += WALK_USEC
		await get_tree().physics_frame


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
