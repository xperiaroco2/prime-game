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
	# A claim within walking reach of the join position (2d checks the speed).
	var claim := {
		"epoch": 0,
		"position": Vector3(0.1, 0, 0.2),
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"client_tick": 4,
		"jumps": 0,
	}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim)
	assert_vector(game.state.player(P1).position).is_equal(Vector3(0.1, 0, 0.2))
	claim["position"] = Vector3(0.2, 0, 0.2)
	claim["client_tick"] = 5
	claim["epoch"] = 3
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim)
	assert_vector(game.state.player(P1).position).is_equal(Vector3(0.1, 0, 0.2))


func test_only_the_host_may_send_a_host_intent() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	for peer: int in [P1, P2]:
		game.state.player(peer).ready = false
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P2, {}, 4)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_a_ghost_may_move_but_not_use() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	var ghost := game.state.player(P2)
	ghost.life = PlayerState.Life.GHOST
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD}, 5)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_array(FixtureModes.notes(game)).not_contains(["used"])
	var to := ghost.position + Vector3(0.2, 0, 0)
	var claim := {
		"epoch": ghost.epoch,
		"position": to,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"client_tick": 1,
		"jumps": 0,
	}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P2, claim)
	assert_vector(ghost.position).is_equal(to)
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD})
	assert_array(FixtureModes.notes(game)).contains(["used"])


func test_a_hello_the_phase_refuses_from_a_newcomer_is_told_joins_closed_and_disconnected() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1])
	FixtureModes.send(game, Intents.PEER_CONNECTED, P3)
	# A newcomer still waiting in a phase that takes no Hello (a mode whose phases do not drop
	# newcomers the way the base mode's Loading does).
	game.state.newcomers[P3] = true
	var hello := {"version": JoinRules.PROTOCOL_VERSION, "content": 0}
	FixtureModes.send(game, Intents.HELLO, P3, hello, 1)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"joins_closed"])
	var last := game.emitted()[game.emitted().size() - 1]
	assert_str(last.event.event_name()).is_equal("DisconnectPeer")
	assert_bool(last.is_directive).is_true()
	assert_bool(game.state.newcomers.has(P3)).is_false()
	assert_array(game.view_of(P3).event_names()).is_equal([&"Rejected"])


func test_a_hello_the_phase_refuses_from_a_player_is_not_accepted_and_nobody_leaves() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	var emitted_before := game.emitted().size()
	var hello := {"version": JoinRules.PROTOCOL_VERSION, "content": 0}
	FixtureModes.send(game, Intents.HELLO, P2, hello, 6)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(game.emitted().size()).is_equal(emitted_before + 1)
	assert_array(game.state.present_peers()).is_equal([P1, P2])


func test_a_move_claim_the_phase_refuses_is_dropped_without_a_rejected() -> void:
	var game := FixtureBaseMode.in_loading([P1, P2])
	var player := game.state.player(P2)
	var was_at := player.position
	var emitted_before := game.emitted().size()
	var claim := {
		"epoch": player.epoch,
		"client_tick": 200,
		"position": was_at + Vector3(0.1, 0, 0),
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"jumps": 0,
	}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P2, claim)
	assert_int(game.emitted().size()).is_equal(emitted_before)
	assert_vector(player.position).is_equal(was_at)
	# It is still in the command log, like every command.
	assert_str(game.command_log.commands.back().kind).is_equal(Intents.MOVE_CLAIM)


func test_the_world_is_told_the_level_on_start_and_before_each_rows_actions() -> void:
	var mode := FixtureModes.basic()
	mode.transitions[0].actions.push_front(FixtureAskFloor.new())
	var world := FixtureLevelWorld.new()
	var game := Match.new(mode, 7, world, FixtureModes.layouts())
	game.start(0)
	assert_array(Array(world.calls)).is_equal(["use_level %s" % FixtureModes.LOBBY])
	FixtureModes.send(game, Intents.HELLO, P1, {"version": JoinRules.PROTOCOL_VERSION})
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	var into_round: Array[String] = [
		"use_level %s" % FixtureModes.LOBBY, "use_level %s" % FixtureModes.MAP, "floor_below"
	]
	assert_array(Array(world.calls)).is_equal(into_round)
	# Not an answer: the command log holds only the floor, and a replay asks the same.
	assert_int(game.command_log.world_answers.size()).is_equal(1)
	var replayed := Match.replay(game.command_log, mode)
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))
	# The crew wins: the round's row enters End (the map); the host goes back to the lobby, where
	# the ready player goes on to a new round.
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	var after: Array[String] = [
		"use_level %s" % FixtureModes.MAP,
		"use_level %s" % FixtureModes.LOBBY,
		"use_level %s" % FixtureModes.MAP,
		"floor_below",
	]
	assert_array(Array(world.calls).slice(into_round.size())).is_equal(after)


func test_a_player_who_left_is_heard_by_no_rule_and_told_nothing() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	var left := game.state.player(P2)
	var was_at := left.position
	left.life = PlayerState.Life.LEFT
	var emitted_before := game.emitted().size()
	FixtureModes.send(game, Intents.MOVE_CLAIM, P2, {"epoch": left.epoch, "position": Vector3.ONE})
	assert_vector(left.position).is_equal(was_at)
	# A refused MoveClaim is dropped without a Rejected (E15).
	assert_int(game.emitted().size()).is_equal(emitted_before)
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD}, 4)
	var last := game.emitted()[game.emitted().size() - 1]
	assert_str(last.event.event_name()).is_equal("Rejected")
	assert_array(Array(last.recipients)).is_empty()


func test_a_newcomer_intent_that_only_a_rule_handles_is_rejected() -> void:
	var mode := FixtureModes.basic()
	var game := FixtureModes.started(mode, [P1])
	# A mode ModeCheck refuses (see mode_check_test); changed after the check to reach the guard.
	mode.phases[0].accepts.append(AcceptSpec.of(Intents.USE, AcceptSpec.From.NEWCOMER))
	FixtureModes.send(game, Intents.USE, 9, {}, 3)
	assert_array(FixtureModes.rejections(game, 9)).is_equal([&"not_accepted"])
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_row_whose_action_raises_a_fact_ends_in_its_target() -> void:
	var mode := FixtureModes.basic()
	mode.transitions[1].actions.append(FixtureRaise.of(Facts.ITEM_RESTED))
	var game := FixtureModes.in_round(mode, [P1])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(Array(game.diagnostics)).is_empty()
	assert_array(FixtureModes.notes(game)).contains(["won crew", "task item_rested"])


func test_a_dropped_outcome_of_a_server_command_rejects_nothing() -> void:
	var mode := FixtureModes.basic()
	mode.phases[2].settings = {&"reports_back": 1.0, &"reports_twice_on_connect": 1.0}
	var game := FixtureModes.in_round(mode, [P1])
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	game.state.player(P1).ready = false
	FixtureModes.send(game, Intents.PEER_CONNECTED, 5)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.diagnostics[0]).contains("dropped: outcome back")
	assert_array(game.view_of(5).events).is_empty()
	assert_array(FixtureModes.names(game)).not_contains([&"Rejected"])


func test_a_cycle_of_rows_on_entry_stops_after_the_limit() -> void:
	var mode := FixtureModes.basic()
	mode.transitions[0].to = &"lobby"
	mode.transitions[0].actions.clear()
	var game := FixtureModes.started(mode, [P1])
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.diagnostics[0]).contains(
		"more than %d transitions in one step" % Match.MAX_TRANSITIONS_PER_STEP
	)
	assert_bool(game.tick(game.ticked_through() + 1)).is_true()


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
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(original))
	assert_dict(replayed.command_log.to_dict()).is_equal(original.command_log.to_dict())


func test_a_replay_that_diverges_says_so() -> void:
	var original := _scripted_match(_scripted_mode(), 1234)
	original.command_log.world_answers.append(true)
	var replayed := Match.replay(original.command_log, _scripted_mode())
	assert_str("; ".join(replayed.diagnostics)).contains("replay: diverged")


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
