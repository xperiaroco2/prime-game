extends GdUnitTestSuite
## StaminaCost (ARCHITECTURE §9.4, §7.1): settles the actor's stamina first, rejects with `tired`
## below the amount and pays nothing, pays the amount and sends the actor its SelfStatus. Driven
## through the fixture mode's Use rule.

const P1 := 1
const P2 := 2


func test_a_use_with_enough_stamina_pays_and_tells_only_the_actor() -> void:
	var game := FixtureModes.in_round(_mode([_cost(25)]), [P1, P2])
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD}, 3)
	assert_array(FixtureModes.notes(game)).contains(["used"])
	assert_int(game.state.player(P1).stamina).is_equal(75000)
	FixtureModes.run_ticks(game, 1)
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(1)
	assert_int(statuses[0].stamina).is_equal(75000)
	assert_int(statuses[0].health).is_equal(100000)
	assert_bool(statuses[0].sprint_available).is_true()
	assert_array(FixtureMoves.statuses(game, P2)).is_empty()


func test_below_the_amount_it_rejects_as_tired_and_pays_nothing() -> void:
	var game := FixtureModes.in_round(_mode([_cost(25)]), [P1])
	var player := game.state.player(P1)
	FixtureMoves.claim(game, P1, player.position)
	player.stamina = 24000
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD}, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([StaminaCost.TIRED])
	assert_array(FixtureModes.notes(game)).not_contains(["used"])
	assert_int(player.stamina).is_equal(24000)


func test_it_settles_the_idle_ticks_first() -> void:
	var game := FixtureModes.in_round(_mode([_cost(25)]), [P1])
	var player := game.state.player(P1)
	FixtureMoves.claim(game, P1, player.position)
	player.stamina = 20000
	FixtureModes.run_ticks(game, 10)
	# Ten idle ticks regenerate 7500: 27500 covers the 25000.
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(player.stamina).is_equal(2500)


func test_a_refused_use_still_sends_the_actor_the_stamina_it_settled() -> void:
	var game := FixtureModes.in_round(_mode([_cost(25)]), [P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.claim(game, P1, player.position)
	player.stamina = 0
	FixtureModes.run_ticks(game, 10)
	var seen := FixtureMoves.statuses(game, P1).size()
	var settled_before := player.stamina
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([StaminaCost.TIRED])
	# The check settled the idle ticks: the stamina changed, so the actor hears of it at the end
	# of the tick, though nothing was paid.
	assert_int(player.stamina).is_not_equal(settled_before)
	FixtureModes.run_ticks(game, 1)
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(seen + 1)
	assert_int(statuses.back().stamina).is_equal(player.stamina)
	assert_array(FixtureMoves.statuses(game, P2)).is_empty()


func test_a_rule_refused_by_a_later_condition_pays_no_stamina() -> void:
	var conditions: Array[Condition] = [_cost(25), FixtureCost.of(&"uses", 0)]
	var game := FixtureModes.in_round(_mode(conditions), [P1])
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"used_up"])
	assert_int(game.state.player(P1).stamina).is_equal(100000)


func test_the_mode_check_bounds_the_amount_by_the_stamina_maximum() -> void:
	var too_much := ModeCheck.run(_mode([_cost(101)]))
	assert_str("\n".join(too_much.errors)).contains("amount is 101, outside 0 to 100")
	var negative := ModeCheck.run(_mode([_cost(-1)]))
	assert_str("\n".join(negative.errors)).contains("amount is -1, outside 0 to 100")
	assert_array(Array(ModeCheck.run(_mode([_cost(100)])).errors)).is_empty()


func _mode(conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	mode.actions[0].conditions = conditions
	return mode


func _cost(points: int) -> StaminaCost:
	var cost := StaminaCost.new()
	cost.amount = points
	return cost
