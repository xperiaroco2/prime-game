extends GdUnitTestSuite
## AllSubtasksDone and the crew's "every task done" (ARCHITECTURE §3.4, §9.4, §9.5): the crew wins
## on the delivery that finishes the last subtask, not before; a task with no subtasks is done,
## and with no tasks at all the condition holds (the engineer's rule of 2026-09-30, #79). Driven
## through seeded matches of FixtureWinModes, asserted on the events and on view_of.

const P1 := 1
const P2 := 2
const P3 := 3


func test_the_crew_wins_on_the_last_delivery_and_not_before() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2, P3])
	var crew := FixtureDealModes.players_of(game, &"crew")
	FixtureWinModes.deliver(game, crew[0], 0)
	assert_str(game.phase_id()).is_equal("round")
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureWinModes.ended(game, peer)).is_empty()
	FixtureWinModes.deliver(game, crew[1], 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"crew"])
		var progress := game.view_of(peer).events_named(&"TaskProgress")
		assert_dict(progress[progress.size() - 1].to_dict()).is_equal({"done": 2, "total": 2})
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_dissident_delivering_the_last_package_still_wins_for_the_crew() -> void:
	# Tasks are shared (#79): whoever finishes the last subtask, the crew's condition holds.
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var dissident := FixtureDealModes.players_of(game, &"dissident")[0]
	FixtureWinModes.deliver(game, dissident, 0)
	assert_str(game.phase_id()).is_equal("end")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"crew"])


func test_a_task_with_no_subtasks_is_done_so_the_crew_wins_on_entering_the_round() -> void:
	# Delivery with 0 packages deals one task of no subtasks (#79).
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(0), [P1, P2])
	assert_int(game.state.tasks.size()).is_equal(1)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"crew"])


func test_with_no_tasks_at_all_every_task_is_done() -> void:
	var mode := FixtureWinModes.basic(2)
	var deal := mode.find_transition(&"lobby", &"all_ready")
	for action: RuleEffect in deal.actions.duplicate():
		if action is DealTasks:
			deal.actions.erase(action)
	var game := FixtureWinModes.in_round(mode, [P1, P2])
	assert_dict(game.state.tasks).is_empty()
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")


func test_the_condition_passes_on_every_task_done_and_negated_on_any_not_done() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var done := AllSubtasksDone.new()
	var not_done := AllSubtasksDone.new()
	not_done.negate = true
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	assert_bool(done.passes(ctx)).is_false()
	assert_bool(not_done.passes(ctx)).is_true()
	var task := FixtureDeliveryModes.task_of(game)
	(task.state as Delivery.State).done[0] = true
	assert_bool(done.passes(ctx)).is_true()
	assert_bool(not_done.passes(ctx)).is_false()
