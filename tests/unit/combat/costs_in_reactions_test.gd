extends GdUnitTestSuite
## Costs in a mode reaction (ARCHITECTURE §9.2, §9.4; #201). A reaction runs for no player: its
## actor is 0, which has no PlayerState. A Cooldown and a StaminaCost then refuse, as a failing
## condition of a fact does: the reaction's effect does not run, nothing is paid or recorded for
## peer 0, and no player hears of it. Driven by the clock ending in Round (FixtureModes.basic()),
## whose reaction notes "reacted" to everyone.
##
## The mode check refuses such a reaction at load (#283; tests/unit/content/mode_check_test.gd),
## so Match.start would never run one: these tests start the match with a reaction the check
## accepts and put the cost in its rule afterwards, which keeps the runtime refusal covered.

const P1 := 1
const P2 := 2
const PEERS: Array[int] = [P1, P2]
const REACTED := "reacted"


func test_without_a_cost_the_reaction_runs_and_everyone_sees_it() -> void:
	var game := FixtureModes.in_round(_reacting(), PEERS)
	_end_the_clock(game)
	assert_array(FixtureModes.notes(game)).contains([REACTED])
	for peer: int in PEERS:
		assert_array(_reactions_seen(game, peer)).has_size(1)


func test_a_cooldown_refuses_a_reaction_and_records_nothing_for_peer_0() -> void:
	var cooldown := FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S)
	var mode := _reacting()
	var game := FixtureModes.in_round(mode, PEERS)
	_slip_in(mode, cooldown)
	_end_the_clock(game)
	_assert_refused(game)
	assert_int(game.state.cooldown_paid_at(0, &"hit")).is_equal(-1)


func test_a_stamina_cost_refuses_a_reaction_and_charges_nobody() -> void:
	var cost := FixtureCombatModes.stamina_cost(FixtureCombatModes.STAMINA_COST)
	var mode := _reacting()
	var game := FixtureModes.in_round(mode, PEERS)
	_slip_in(mode, cost)
	var stamina_before: Dictionary[int, int] = {}
	for peer: int in PEERS:
		stamina_before[peer] = game.state.player(peer).stamina
	_end_the_clock(game)
	_assert_refused(game)
	for peer: int in PEERS:
		assert_int(game.state.player(peer).stamina).is_equal(stamina_before[peer])


func test_a_cost_that_reads_no_player_state_runs_the_reaction_and_pays_for_peer_0() -> void:
	# The case the mode check allows (Condition.reads_actor_state false): FixtureCost reads and counts
	# in MatchState's counters, which have a row for peer 0, so the reaction passes and pays.
	var mode := _reacting()
	var conditions: Array[Condition] = [FixtureCost.of(&"uses", 1)]
	mode.reactions[0].conditions = conditions
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	var game := FixtureModes.in_round(mode, PEERS)
	_end_the_clock(game)
	assert_array(FixtureModes.notes(game)).contains([REACTED])
	for peer: int in PEERS:
		assert_array(_reactions_seen(game, peer)).has_size(1)
		assert_int(game.state.counter(peer, &"uses")).is_equal(0)
	assert_int(game.state.counter(0, &"uses")).is_equal(1)
	assert_array(Array(game.diagnostics)).is_empty()


## FixtureModes.basic() whose reaction on clock_ended holds no condition and notes REACTED to
## everyone. The mode check accepts it.
func _reacting() -> GameMode:
	var mode := FixtureModes.basic()
	var note: Array[RuleEffect] = [FixtureNote.of(REACTED)]
	mode.reactions = [FixtureModes.rule(Facts.CLOCK_ENDED, [], note)]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	return mode


## Puts `cost` in the clock_ended reaction of `mode`, whose match has started: a mode written so
## from the start is refused at load, which the check is asked to prove first.
func _slip_in(mode: GameMode, cost: Cost) -> void:
	var conditions: Array[Condition] = [cost]
	mode.reactions[0].conditions = conditions
	var errors := Array(ModeCheck.run(mode).errors)
	assert_array(errors).has_size(1)
	assert_str(str(errors[0])).contains("mode.reactions[0]: the reaction on clock_ended")


func _end_the_clock(game: Match) -> void:
	game.state.clock_ticks_left = 2
	FixtureModes.run_ticks(game, 2)
	assert_bool(game.state.clock_ended).is_true()
	assert_str(String(game.phase_id())).is_equal("round")


func _assert_refused(game: Match) -> void:
	assert_array(FixtureModes.notes(game)).not_contains([REACTED])
	for peer: int in PEERS:
		assert_array(_reactions_seen(game, peer)).is_empty()
		# A fact's refusal tells nobody: there is no sender.
		assert_array(FixtureModes.rejections(game, peer)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


## The REACTED notes `peer` received.
func _reactions_seen(game: Match, peer: int) -> Array[MatchEvent]:
	var found: Array[MatchEvent] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"FixtureNote"):
		if (event as FixtureNoteEvent).text == REACTED:
			found.append(event)
	return found
