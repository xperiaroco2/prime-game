extends GdUnitTestSuite
## The pinball in the bots (#1510; ARCHITECTURE §4.6, §7.1.22, §9.7): the cross-bot ball check
## (LeakCheck.check_ball) on hand-built views, each planted difference failing it; the fixture
## scenario pinball_plays_a_ball through the host (BotsRunner) and the core runner, a scripted
## table (ScriptedPinballTable) under each.

const SCENARIO := "res://tests/fixtures/scenarios/pinball_plays_a_ball.tres"
const AT := Vector3(0.25, 0.0, -0.5)


func test_the_same_ball_or_none_in_every_view_passes() -> void:
	var views := _views({10: AT, 11: null}, {10: AT, 11: null, 12: AT})
	assert_array(Array(LeakCheck.check_ball(views))).is_empty()
	# Tick 10 alone holds a ball both views decoded; tick 12 is one view's.
	assert_int(LeakCheck.shared_ball_ticks(views)).is_equal(1)


func test_another_ball_on_a_shared_tick_fails() -> void:
	var views := _views({10: AT, 11: AT}, {10: AT, 11: AT + Vector3(1, 0, 0)})
	var found := LeakCheck.check_ball(views)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("leak: bot 1 and bot 2 decoded another ball at tick 11")


func test_a_ball_one_view_has_and_another_lacks_on_a_shared_tick_fails() -> void:
	var found := LeakCheck.check_ball(_views({10: AT}, {10: null}))
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("decoded another ball at tick 10")
	found = LeakCheck.check_ball(_views({10: null}, {10: AT}))
	assert_int(found.size()).is_equal(1)


func test_a_tick_only_one_view_holds_compares_nothing() -> void:
	var views := _views({10: AT}, {11: AT + Vector3(1, 0, 0)})
	assert_array(Array(LeakCheck.check_ball(views))).is_empty()
	assert_int(LeakCheck.shared_ball_ticks(views)).is_equal(0)


func test_many_ticks_with_another_ball_are_listed_up_to_the_cap() -> void:
	var mine: Dictionary[int, Variant] = {}
	var theirs: Dictionary[int, Variant] = {}
	for at_tick in 20:
		mine[at_tick] = AT
		theirs[at_tick] = AT + Vector3(0, 0, 1)
	var found := LeakCheck.check_ball(_views(mine, theirs))
	assert_int(found.size()).is_equal(LeakCheck.MAX_LISTED + 1)
	assert_str(found[found.size() - 1]).contains("and %d more" % (20 - LeakCheck.MAX_LISTED))


## Two views, bot 1's and bot 2's: tick -> the ball decoded (null: a snapshot with no ball).
static func _views(first: Dictionary, second: Dictionary) -> Dictionary[String, DecodedView]:
	var views: Dictionary[String, DecodedView] = {}
	views["bot 1"] = _view(first)
	views["bot 2"] = _view(second)
	return views


static func _view(balls: Dictionary) -> DecodedView:
	var view := DecodedView.new()
	for at_tick: int in balls:
		var snapshot := {"tick": at_tick, "avatars": {}}
		if balls[at_tick] != null:
			snapshot["ball"] = balls[at_tick]
		view.snapshots[at_tick] = snapshot
	return view


func test_a_bot_plays_a_ball_through_the_host_and_every_bot_decodes_the_same_one() -> void:
	var runner := BotsRunner.play(load(SCENARIO) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	assert_bool(runner.session.table is ScriptedPinballTable).is_true()
	var table := runner.session.table as ScriptedPinballTable
	# One left press hit the game's first target, and standing up counted the score as the best.
	var first := _first_target(runner.game)
	assert_array(table.hits).is_equal([first])
	var points := Pinball.game(runner.game.state).points
	assert_int(Pinball.session(runner.game.state).best).is_equal(points[first])
	assert_array(runner.session.table_errors).is_empty()
	# Both bots decoded the ball at shared ticks, so check_ball compared something.
	assert_int(runner.ball_ticks_compared).is_greater(0)
	for bot: ScenarioBot in runner.bots:
		var balls := 0
		var view := runner.clients[bot.number].view
		for at_tick: int in view.snapshots:
			if view.snapshots[at_tick].has("ball"):
				balls += 1
		assert_int(balls).is_greater(0)


func test_the_core_runner_plays_the_same_ball() -> void:
	var runner := ScenarioRunner.play(load(SCENARIO) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	var first := _first_target(runner.game)
	var points := Pinball.game(runner.game.state).points
	assert_int(Pinball.session(runner.game.state).best).is_equal(points[first])


## The game's first target by id: the one ScriptedPinballTable hits.
static func _first_target(game: Match) -> StringName:
	var ids: Array[StringName] = []
	ids.assign(Pinball.game(game.state).points.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids[0]
