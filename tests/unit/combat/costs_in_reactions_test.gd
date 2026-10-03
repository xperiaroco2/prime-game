extends GdUnitTestSuite
## Costs in a mode reaction (ARCHITECTURE §9.2, §9.4; #201). A reaction runs for no player: its
## actor is 0, which has no PlayerState, and the mode check allows costs there. A Cooldown and a
## StaminaCost then refuse, as a failing condition of a fact does: the reaction's effect does not
## run, nothing is paid or recorded for peer 0, and no player hears of it. Driven by the clock
## ending in Round (FixtureModes.basic()), whose reaction notes "reacted" to everyone.

const P1 := 1
const P2 := 2
const PEERS: Array[int] = [P1, P2]
const REACTED := "reacted"


func test_without_a_cost_the_reaction_runs_and_everyone_sees_it() -> void:
	var game := _clock_ends([])
	assert_array(FixtureModes.notes(game)).contains([REACTED])
	for peer: int in PEERS:
		assert_array(_reactions_seen(game, peer)).has_size(1)


func test_a_cooldown_refuses_a_reaction_and_records_nothing_for_peer_0() -> void:
	var cooldown := FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S)
	var game := _clock_ends([cooldown])
	_assert_refused(game)
	assert_int(game.state.cooldown_paid_at(0, &"hit")).is_equal(-1)


func test_a_stamina_cost_refuses_a_reaction_and_charges_nobody() -> void:
	var cost := FixtureCombatModes.stamina_cost(FixtureCombatModes.STAMINA_COST)
	var mode := _reacting([cost])
	var game := FixtureModes.in_round(mode, PEERS)
	var stamina_before: Dictionary[int, int] = {}
	for peer: int in PEERS:
		stamina_before[peer] = game.state.player(peer).stamina
	_end_the_clock(game)
	_assert_refused(game)
	for peer: int in PEERS:
		assert_int(game.state.player(peer).stamina).is_equal(stamina_before[peer])


## A round of FixtureModes.basic() with `conditions` on its clock_ended reaction, run until the
## clock ends.
func _clock_ends(conditions: Array[Condition]) -> Match:
	var game := FixtureModes.in_round(_reacting(conditions), PEERS)
	_end_the_clock(game)
	return game


## FixtureModes.basic() whose reaction on clock_ended has `conditions` and notes REACTED to
## everyone. The mode check accepts it.
func _reacting(conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	var note: Array[RuleEffect] = [FixtureNote.of(REACTED)]
	mode.reactions = [FixtureModes.rule(Facts.CLOCK_ENDED, conditions, note)]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	return mode


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
