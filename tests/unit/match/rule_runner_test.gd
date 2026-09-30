extends GdUnitTestSuite
## The rule runner and what Match does around it (ARCHITECTURE §3.1, §3.4, §9.2): conditions in
## order, costs paid only when all pass, effects in order, the owners' precedence, facts depth
## first with a cap, the win checks after every fact and at the end of a step, and
## `outcome_dropped`.

const P1 := 1
const P2 := 2


func test_conditions_run_in_order_and_the_first_failure_names_the_reason() -> void:
	var mode := _with_use(
		[FixtureCounterAtLeast.of(&"a", &"first"), FixtureCounterAtLeast.of(&"b", &"second")],
		[FixtureNote.of("ran")]
	)
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"first"])
	game.state.set_counter(0, &"a", 1)
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"first", &"second"])
	game.state.set_counter(0, &"b", 1)
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.notes(game)).is_equal(["ran"])


func test_a_negated_condition_rejects_with_not_allowed() -> void:
	var condition := FixtureCounterAtLeast.of(&"a", &"first")
	condition.negate = true
	var game := FixtureModes.in_round(_with_use([condition], [FixtureNote.of("ran")]), [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.notes(game)).is_equal(["ran"])
	game.state.set_counter(0, &"a", 1)
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_allowed"])


func test_a_refused_intent_pays_nothing() -> void:
	var mode := _with_use(
		[FixtureCost.of(&"uses", 5), FixtureCounterAtLeast.of(&"open")], [FixtureNote.of("ran")]
	)
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.counter(P1, &"uses")).is_equal(0)
	assert_array(FixtureModes.notes(game)).is_empty()


func test_costs_are_paid_before_the_effects_and_run_out() -> void:
	var game := FixtureModes.in_round(
		_with_use([FixtureCost.of(&"uses", 2)], [FixtureNote.of("ran")]), [P1, P2]
	)
	for i in 3:
		FixtureModes.send(game, Intents.USE, P1)
	FixtureModes.send(game, Intents.USE, P2)
	assert_int(game.state.counter(P1, &"uses")).is_equal(2)
	assert_int(game.state.counter(P2, &"uses")).is_equal(1)
	assert_array(FixtureModes.notes(game)).is_equal(["ran", "ran", "ran"])
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"used_up"])
	assert_array(FixtureModes.rejections(game, P2)).is_empty()


func test_the_held_item_then_the_role_then_the_mode_decides() -> void:
	var mode := FixtureModes.basic()
	var knife := ItemKind.new()
	knife.id = &"knife"
	knife.spawn_tag = &"knife"
	knife.actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("item")])]
	mode.item_kinds = [knife]
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("role")])]
	mode.actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("mode")])]
	var game := FixtureModes.in_round(mode, [P1])
	var player := game.state.player(P1)
	FixtureModes.send(game, Intents.USE, P1)
	player.role = &"dissident"
	FixtureModes.send(game, Intents.USE, P1)
	var item := game.state.add_item(knife, Vector3.ZERO)
	item.where = ItemState.Where.HAND
	item.holder = P1
	player.held_item = item.id
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.notes(game)).is_equal(["mode", "role", "item"])


func test_an_intent_no_rule_handles_gets_nothing_to_do() -> void:
	var mode := FixtureModes.basic()
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("role")])]
	mode.actions = []
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])


func test_a_fact_is_handled_depth_first() -> void:
	var mode := _with_use(
		[], [FixtureNote.of("before"), FixtureRaise.of(Facts.ITEM_RESTED), FixtureNote.of("after")]
	)
	mode.reactions = [FixtureModes.rule(Facts.ITEM_RESTED, [], [FixtureNote.of("reaction")])]
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.notes(game)).is_equal(
		["before", "reaction", "task item_rested", "after"]
	)


func test_a_failing_reaction_condition_does_nothing() -> void:
	var mode := _with_use([], [FixtureRaise.of(Facts.ITEM_RESTED)])
	mode.reactions = [
		FixtureModes.rule(
			Facts.ITEM_RESTED, [FixtureCounterAtLeast.of(&"never")], [FixtureNote.of("x")]
		)
	]
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(FixtureModes.notes(game)).is_equal(["task item_rested"])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_a_chain_of_facts_is_stopped_at_the_cap() -> void:
	var mode := _with_use([], [FixtureRaise.of(Facts.ITEM_RESTED)])
	mode.task_types = []
	mode.reactions = [
		FixtureModes.rule(
			Facts.ITEM_RESTED, [], [FixtureNote.of("again"), FixtureRaise.of(Facts.ITEM_RESTED)]
		)
	]
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(FixtureModes.notes(game).size()).is_equal(Match.MAX_FACT_DEPTH)
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("a chain of more than 16 facts")
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(FixtureModes.notes(game).size()).is_equal(2 * Match.MAX_FACT_DEPTH)


func test_the_win_check_after_a_fact_orders_the_effects() -> void:
	# The dissidents' condition holds after the fact; the crew's only after the next effect. The
	# mode's order (crew first) would pick the crew at the end of the step (§3.4).
	var mode := _with_use(
		[],
		[
			FixtureBump.of(&"dissidents_win"),
			FixtureRaise.of(Facts.PLAYER_DIED),
			FixtureBump.of(&"crew_win")
		]
	)
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won dissidents"])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_without_a_fact_the_mode_order_decides_at_the_end_of_the_step() -> void:
	var mode := _with_use([], [FixtureBump.of(&"dissidents_win"), FixtureBump.of(&"crew_win")])
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won crew"])


func test_a_tick_ends_with_a_win_check() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1])
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("round")
	game.state.set_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")


func test_phases_that_do_not_check_wins_never_report_won() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	game.state.set_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("lobby")


func test_a_dropped_outcome_of_the_intent_tells_its_sender() -> void:
	var mode := _with_use(
		[FixtureCost.of(&"uses", 5)],
		[
			FixtureBump.of(&"dissidents_win"),
			FixtureRaise.of(Facts.PLAYER_DIED),
			FixtureReport.of(&"go"),
			FixtureNote.of("after")
		]
	)
	mode.transitions.append(FixtureModes.row(&"round", &"go", &"end", []))
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1, {}, 42)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won dissidents", "after"])
	var rejected := game.view_of(P1).events_named(&"Rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_int((rejected[0] as RejectedEvent).seq).is_equal(42)
	assert_str((rejected[0] as RejectedEvent).reason).is_equal("outcome_dropped")
	assert_int(game.state.counter(P1, &"uses")).is_equal(1)
	assert_str(game.diagnostics[0]).contains("dropped: outcome go")


func test_the_first_outcome_of_a_step_wins_and_no_win_check_follows() -> void:
	var mode := _with_use(
		[],
		[FixtureReport.of(&"go"), FixtureBump.of(&"crew_win"), FixtureRaise.of(Facts.PLAYER_DIED)]
	)
	mode.transitions.append(FixtureModes.row(&"round", &"go", &"end", [FixtureNote.of("went")]))
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).is_equal(["task player_died", "went"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_role_owned_rule_with_a_public_event_is_warned_about() -> void:
	var mode := FixtureModes.basic()
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("seen")])]
	var game := FixtureModes.create(mode)
	assert_array(Array(game.refusals)).is_empty()
	assert_int(game.warnings.size()).is_equal(1)
	assert_str(game.warnings[0]).contains("reveals the actor's role")


## The fixture mode with one Use rule on the mode.
func _with_use(conditions: Array[Condition], effects: Array[RuleEffect]) -> GameMode:
	var mode := FixtureModes.basic()
	mode.actions = [FixtureModes.rule(Intents.USE, conditions, effects)]
	return mode
