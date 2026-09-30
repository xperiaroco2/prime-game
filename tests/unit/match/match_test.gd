extends GdUnitTestSuite
## Match: the loop of ARCHITECTURE §3.1 and §3.3 (phases, the allowlist, transitions, the clock,
## ticks) and the command log with replay, driven by the fixture mode.

const P1 := 1
const P2 := 2
const P3 := 3


func test_a_mode_with_errors_is_refused() -> void:
	var mode := FixtureModes.basic()
	mode.first_phase = &"nowhere"
	var game := FixtureModes.create(mode)
	assert_array(Array(game.refusals)).is_not_empty()
	assert_str(game.refusals[0]).contains("first_phase nowhere")
	assert_bool(game.start(0)).is_false()
	assert_array(game.emitted()).is_empty()


func test_start_enters_the_first_phase() -> void:
	var game := FixtureModes.create(FixtureModes.basic())
	assert_bool(game.start(0)).is_true()
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(FixtureModes.names(game)).is_equal([&"PhaseChanged"])
	assert_bool(game.start(0)).is_false()


func test_the_allowlist_rejects_other_intents_and_senders() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	FixtureModes.send(game, Intents.USE, P1, {}, 7)
	FixtureModes.send(game, Intents.SET_READY, P2, {"ready": true}, 8)
	FixtureModes.send(game, Intents.HELLO, P1, {"name": "again"}, 9)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted", &"not_accepted"])
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	var rejected := game.view_of(P1).events_named(&"Rejected")[0] as RejectedEvent
	assert_int(rejected.seq).is_equal(7)
	assert_str(game.state.player(P1).name).is_equal("p1")


func test_an_outcome_moves_through_its_row_actions_first() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	assert_str(game.phase_id()).is_equal("round")
	var names := FixtureModes.names(game)
	var placed := names.find(&"PlayersPlaced")
	assert_int(placed).is_greater(0)
	assert_array(names.slice(placed)).is_equal(
		[&"PlayersPlaced", &"Correction", &"Correction", &"PhaseChanged"]
	)


func test_every_entry_gets_a_fresh_phase_object() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1])
	FixtureModes.send(game, Intents.USE, P1)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	var first_end := game.current_phase() as FixturePhase
	game.state.set_counter(0, &"crew_win", 0)
	game.state.player(P1).ready = false
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(first_end.exits).is_equal(1)
	var lobby := game.current_phase() as FixturePhase
	assert_int(lobby.entries).is_equal(1)
	assert_int(lobby.ticks_seen).is_equal(0)
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	var second_end := game.current_phase() as FixturePhase
	assert_object(second_end).is_not_same(first_end)
	assert_int(second_end.entries).is_equal(1)


func test_a_condition_that_holds_on_entry_moves_on_at_once() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	# The player is still ready: re-entering the lobby reports all_ready on entry.
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("round")
	var phases: Array[StringName] = []
	for event: MatchEvent in game.view_of(P1).events_named(&"PhaseChanged"):
		phases.append((event as PhaseChangedEvent).phase)
	# P1 joined after the first PhaseChanged, so its view starts in the round.
	assert_array(phases).is_equal([&"round", &"end", &"lobby", &"round"])


func test_an_outcome_without_a_row_fails_loudly() -> void:
	var mode := FixtureModes.basic()
	var game := FixtureModes.started(mode, [P1])
	mode.transitions = [mode.transitions[1], mode.transitions[2]]
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.diagnostics[0]).contains(
		"lobby reported all_ready, which has no transition row"
	)


func test_a_phase_timer_reports_on_its_tick() -> void:
	var mode := FixtureModes.basic()
	mode.phases[2].settings = {&"reports_back": 1.0, &"go_after_ticks": 3.0}
	mode.transitions.append(FixtureModes.row(&"end", &"go", &"lobby", []))
	var game := FixtureModes.in_round(mode, [P1])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	game.state.player(P1).ready = false
	var entered := game.ticked_through()
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(game.ticked_through()).is_equal(entered + 3)


func test_phase_changed_announces_a_countdown() -> void:
	var mode := FixtureModes.basic()
	mode.phases[2].settings = {&"reports_back": 1.0, &"countdown_ticks": 100.0}
	var game := FixtureModes.in_round(mode, [P1])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	var changed := game.view_of(P1).events_named(&"PhaseChanged")
	var to_end := changed[changed.size() - 1] as PhaseChangedEvent
	assert_str(to_end.phase).is_equal("end")
	assert_int(to_end.end_tick).is_equal(game.ticked_through() + 100)


func test_the_match_clock_ends_on_the_announced_tick() -> void:
	var mode := FixtureModes.basic()
	var clock_note := FixtureNote.of("clock ended")
	mode.reactions = [FixtureModes.rule(Facts.CLOCK_ENDED, [], [clock_note])]
	var game := FixtureModes.started(mode, [P1])
	game.state.clock_ticks_left = 5
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
	var changed := game.view_of(P1).events_named(&"PhaseChanged")
	var announced := (changed[changed.size() - 1] as PhaseChangedEvent).end_tick
	assert_int(announced).is_equal(game.ticked_through() + 5)
	FixtureModes.run_ticks(game, 4)
	assert_bool(game.state.clock_ended).is_false()
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.clock_ended).is_true()
	assert_int(game.ticked_through()).is_equal(announced)
	var notes := game.emitted().filter(
		func(e: EmittedEvent) -> bool: return e.event is FixtureNoteEvent
	)
	assert_int((notes[notes.size() - 1] as EmittedEvent).tick).is_equal(announced)
	FixtureModes.run_ticks(game, 3)
	(
		assert_array(
			FixtureModes.notes(game).filter(func(n: String) -> bool: return n == "clock ended")
		)
		. has_size(1)
	)


func test_the_clock_does_not_run_in_a_phase_whose_clock_is_stopped() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	game.state.clock_ticks_left = 5
	FixtureModes.run_ticks(game, 10)
	assert_int(game.state.clock_ticks_left).is_equal(5)


func test_commands_and_ticks_must_come_in_order() -> void:
	var game := FixtureModes.create(FixtureModes.basic())
	assert_bool(game.tick(0)).is_false()
	game.start(10)
	assert_bool(game.tick(12)).is_false()
	assert_bool(game.apply(MatchCommand.new(Intents.HELLO, P1, 9))).is_false()
	assert_bool(game.apply(MatchCommand.new(Intents.HELLO, P1, 10))).is_true()
	assert_bool(game.tick(10)).is_true()
	assert_bool(game.apply(MatchCommand.new(Intents.HELLO, P2, 10))).is_false()
	assert_int(game.diagnostics.size()).is_equal(4)


func test_move_claims_of_the_current_epoch_move_the_player() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	var claim := {"epoch": 0, "position": Vector3(1, 0, 2), "client_tick": 4}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim)
	assert_vector(game.state.player(P1).position).is_equal(Vector3(1, 0, 2))
	claim["position"] = Vector3(9, 0, 9)
	claim["epoch"] = 3
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim)
	assert_vector(game.state.player(P1).position).is_equal(Vector3(1, 0, 2))


func test_the_command_log_holds_what_the_match_was_given() -> void:
	var mode := FixtureModes.basic()
	var game := FixtureModes.in_round(mode, [P1, P2])
	FixtureModes.run_ticks(game, 2)
	var recorded := game.command_log
	assert_int(recorded.session_seed).is_equal(7)
	assert_int(recorded.mode_hash).is_equal(ContentHash.of(mode))
	assert_int(recorded.start_tick).is_equal(0)
	assert_int(recorded.ticked_through).is_equal(game.ticked_through())
	assert_array(recorded.layouts.keys()).contains_exactly_in_any_order(
		[FixtureModes.LOBBY, FixtureModes.MAP]
	)
	var kinds: Array[StringName] = []
	for command: MatchCommand in recorded.commands:
		kinds.append(command.kind)
	assert_array(kinds).is_equal(
		[Intents.HELLO, Intents.HELLO, Intents.SET_READY, Intents.SET_READY]
	)


func test_the_same_seed_and_commands_give_the_same_events_and_log() -> void:
	var a := _scripted_match(_scripted_mode(), 1234)
	var b := _scripted_match(_scripted_mode(), 1234)
	assert_array(FixtureModes.describe(a)).is_equal(FixtureModes.describe(b))
	assert_dict(a.command_log.to_dict()).is_equal(b.command_log.to_dict())
	var other := _scripted_match(_scripted_mode(), 99)
	assert_array(FixtureModes.describe(other)).is_not_equal(FixtureModes.describe(a))


func test_a_replay_gives_the_same_events() -> void:
	var original := _scripted_match(_scripted_mode(), 1234)
	assert_array(FixtureModes.notes(original)).contains(["won dissidents"])
	var replayed := Match.replay(original.command_log, _scripted_mode())
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(original))
	assert_dict(replayed.command_log.to_dict()).is_equal(original.command_log.to_dict())


func test_a_replay_refuses_a_changed_mode() -> void:
	var original := _scripted_match(_scripted_mode(), 1234)
	var changed := _scripted_mode()
	changed.settings[0].default_value = 3
	var replayed := Match.replay(original.command_log, changed)
	assert_str(replayed.refusals[0]).contains("differs from the recorded")
	assert_array(replayed.emitted()).is_empty()


## Two matches of the session, driven by commands only: join, a Use that wins for the
## dissidents, back to the lobby (whose row takes the win back), and a second round.
func _scripted_match(mode: GameMode, seed_value: int) -> Match:
	var game := FixtureModes.in_round(mode, [P1, P2, P3], seed_value)
	FixtureModes.send(game, Intents.MOVE_CLAIM, P3, {"epoch": 1, "position": Vector3(3, 0, 3)})
	FixtureModes.run_ticks(game, 3)
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD}, 1)
	FixtureModes.run_ticks(game, 2)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	FixtureModes.run_ticks(game, 2)
	return game


## The fixture mode whose Use wins for the dissidents.
func _scripted_mode() -> GameMode:
	var mode := FixtureModes.basic()
	mode.actions[0].effects.append(FixtureBump.of(&"dissidents_win"))
	mode.transitions[2].actions.append(FixtureBump.of(&"dissidents_win", -1))
	return mode
