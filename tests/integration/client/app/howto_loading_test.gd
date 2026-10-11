extends GdUnitTestSuite
## The loading screen's how-to card in the game (#254): a host's Game alone over a LoopbackHub on a
## simulated clock, as map_input_test.gd. Its first loading shows Delivery's card instead of the
## players and the tip and counts it; a player who saw it twice, or who completed Delivery, gets
## the tip; a task finished in the round completes its type, so the next loading shows the tip
## (Game._process follows the model); a banned type shows no card. The completion's rule itself
## (the task's counter at its total) is HowtoProgress.follow's, howto_progress_test.gd.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7425
const STEP_USEC := 250000
const MAX_FRAMES := 900

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000
## The loading screen's state when the loading started, after the game picked its card.
var _loading_states: Array[StringName] = []


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000
	_loading_states.clear()


func test_the_first_loading_shows_deliverys_card_and_counts_it() -> void:
	var game := await _round_game(PORT, HowtoProgress.new())
	assert_array(_loading_states).is_equal([&"load-card"])
	assert_int(game.howto.loading_shown(&"delivery")).is_equal(1)
	game.leave()
	await get_tree().process_frame


func test_after_two_shows_or_a_completion_the_loading_shows_the_tip() -> void:
	var seen := HowtoProgress.new()
	seen.note_loading_shown(&"delivery")
	seen.note_loading_shown(&"delivery")
	var game := await _round_game(PORT + 1, seen)
	assert_array(_loading_states).is_equal([&"load"])
	assert_int(game.howto.loading_shown(&"delivery")).is_equal(2)
	game.leave()
	await get_tree().process_frame
	_loading_states.clear()
	var veteran := HowtoProgress.new()
	var model := ClientModel.new(null)
	model.fold(&"TaskState", {"task": 1, "type": &"delivery", "done": 6, "total": 6})
	veteran.follow(model)
	game = await _round_game(PORT + 2, veteran)
	assert_array(_loading_states).is_equal([&"load"])
	assert_int(game.howto.loading_shown(&"delivery")).is_equal(0)
	game.leave()
	await get_tree().process_frame


func test_a_task_finished_in_the_round_completes_its_type_for_the_next_loading() -> void:
	var game := await _round_game(PORT + 4, HowtoProgress.new())
	assert_array(_loading_states).is_equal([&"load-card"])
	var model := game.client().model
	assert_bool(model.tasks.is_empty()).is_false()
	var id: int = model.tasks.keys()[0]
	var task: ClientModel.Task = model.tasks[id]
	assert_str(String(task.type)).is_equal("delivery")
	assert_bool(game.howto.completed(&"delivery")).is_false()
	# The round's task reaches its total in the model the game reads, as its TaskState would.
	model.fold(
		&"TaskState", {"task": id, "type": task.type, "done": task.total, "total": task.total}
	)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(game.howto.completed(&"delivery")).is_true()
	_loading_states.clear()
	game.ui.show_screen(S.LOADING)
	assert_array(_loading_states).is_equal([&"load"])
	assert_int(game.howto.loading_shown(&"delivery")).is_equal(1)
	game.leave()
	await get_tree().process_frame


func test_a_banned_task_type_shows_no_card() -> void:
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 3)])
	game.howto = HowtoProgress.new()
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.LOBBY)).is_true()
	# With every type banned the lobby cannot start: the card is picked from the dealable types.
	var model := game.client().model
	model.id_sets[&"banned_task_types"] = PackedStringArray(["delivery"])
	assert_array(HowtoCards.dealable(game.mode, model)).is_empty()
	game.ui.show_screen(S.LOADING)
	assert_array(_loading_states).is_equal([&"load"])
	assert_int(game.howto.loading_shown(&"delivery")).is_equal(0)
	game.leave()
	await get_tree().process_frame


## A host's Game alone in the round of a one-minute match, its progress `progress`.
func _round_game(port: int, progress: HowtoProgress) -> Game:
	var game := _game(["--host", "--local", "--no-replay", "--port=%d" % port])
	game.howto = progress
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.LOBBY)).is_true()
	game.set_ready(true)
	assert_bool(await _until(func() -> bool: return game.ui.screen == S.ROUND)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	return game


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = func() -> int: return _now
	game.make_transport = _transport
	add_child(game)
	auto_free(game)
	# After the game's own handler, so the state is the one it left.
	game.ui.loading_started.connect(
		func() -> void: _loading_states.append(game.ui.connecting.state())
	)
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
