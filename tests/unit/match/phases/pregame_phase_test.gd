extends GdUnitTestSuite
## Pregame (ARCHITECTURE §3.2, §3.5, §3.6, §9.4, #213): between Loading and Round, `pregame_done`
## on its end tick, `seconds` (the fixture's 3 s) after the entry. FixtureBaseMode's phases, with a
## DealRoles on the Loading row and a StartClock on the Pregame row as in the base mode: the roles
## are dealt before it and each peer learns only its own; the clock and RoundStarted wait for the
## round; it accepts nothing (a MoveClaim is dropped, every other intent `not_accepted`); no win
## check runs in it; joins are refused and a leave is the life rule's, as in Round.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const PREGAME_TICKS := FixtureBaseMode.PREGAME_TICKS
const MINUTES := 10
## MatchState.clock_ticks_left before StartClock: no clock.
const NO_CLOCK := -1


func test_the_last_ack_enters_the_pregame_with_the_roles_dealt_and_the_clock_stopped() -> void:
	var game := _in_pregame()
	assert_str(game.phase_id()).is_equal("pregame")
	var entered := game.current_phase().entered_tick
	for peer: int in PEERS:
		var changed := game.view_of(peer).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
		assert_dict(changed.to_dict()).is_equal(
			{"phase": &"pregame", "end_tick": entered + PREGAME_TICKS}
		)
		assert_str(game.state.player(peer).role).is_not_empty()
		assert_array(game.view_of(peer).events_named(&"RoundStarted")).is_empty()
	assert_int(game.state.clock_ticks_left).is_equal(NO_CLOCK)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_round_and_its_clock_begin_on_the_pregame_s_end_tick() -> void:
	var game := _in_pregame()
	var end := game.current_phase().entered_tick + PREGAME_TICKS
	while game.ticked_through() < end - 1:
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("pregame")
	assert_int(game.state.clock_ticks_left).is_equal(NO_CLOCK)
	assert_array(game.view_of(P1).events_named(&"RoundStarted")).is_empty()
	var from := game.view_of(P1).events.size()
	FixtureModes.run_ticks(game, 1)
	assert_int(game.ticked_through()).is_equal(end)
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.clock_ticks_left).is_equal(Ticks.from_minutes(MINUTES))
	assert_array(FixtureBaseMode.names_since(game, P1, from)).is_equal(
		[&"RoundStarted", &"PhaseChanged"]
	)
	for peer: int in PEERS:
		var started := game.view_of(peer).events_named(&"RoundStarted")
		assert_int(started.size()).is_equal(1)
		assert_dict(started[0].to_dict()).is_equal({"start_tick": end})
		var changed := game.view_of(peer).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
		assert_str(changed.phase).is_equal("round")
		assert_int(changed.end_tick).is_equal(end + Ticks.from_minutes(MINUTES))


func test_each_peer_learns_only_its_own_role() -> void:
	var game := _in_pregame()
	for peer: int in PEERS:
		var view := game.view_of(peer)
		var assigned := view.events_named(&"RoleAssigned")
		assert_int(assigned.size()).is_equal(1)
		var own := assigned[0] as RoleAssignedEvent
		assert_int(own.peer).is_equal(peer)
		assert_str(own.role).is_equal(game.state.player(peer).role)
		# Teammates reaches only the players of a role that knows its own (the dissidents).
		for event: MatchEvent in view.events_named(&"Teammates"):
			assert_str((event as TeammatesEvent).role).is_equal(game.state.player(peer).role)
			assert_str(game.state.player(peer).role).is_equal("dissident")


func test_a_move_claim_is_dropped_and_every_other_intent_is_not_accepted() -> void:
	var game := _in_pregame()
	var at := game.state.player(P1).position
	var claim := {"position": at + Vector3(1, 0, 0), "facing": Vector2.ZERO}
	FixtureModes.send(game, Intents.MOVE_CLAIM, P1, claim, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_vector(game.state.player(P1).position).is_equal(at)
	var intents: Array[StringName] = [
		Intents.PICK_UP,
		Intents.PUT_DOWN,
		Intents.USE,
		Intents.RAISE,
		Intents.STOP_RAISE,
		Intents.GIVE_UP,
		Intents.SWAP,
		Intents.LOAD_ACK,
		Intents.SET_READY,
		Intents.RETURN_TO_LOBBY,
	]
	var seq := 2
	for intent: StringName in intents:
		FixtureModes.send(game, intent, P1, {}, seq)
		seq += 1
	var want: Array[StringName] = []
	for intent: StringName in intents:
		want.append(RejectReasons.NOT_ACCEPTED)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(want)
	assert_str(game.phase_id()).is_equal("pregame")


func test_no_win_is_checked_in_the_pregame_and_the_round_s_entry_checks_at_once() -> void:
	# The fixture's crew wins once peer 0's counter crew_win is 1: it holds from the entry on.
	var game := _in_pregame()
	var end := game.current_phase().entered_tick + PREGAME_TICKS
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, PREGAME_TICKS)
	assert_str(game.phase_id()).is_equal("pregame")
	FixtureModes.run_ticks(game, 1)
	# The round's entry is a step of its own: its win check ends the match in the same tick.
	assert_int(game.ticked_through()).is_equal(end)
	assert_str(game.phase_id()).is_equal("end")
	var phases: Array[StringName] = []
	for event: MatchEvent in game.view_of(P1).events_named(&"PhaseChanged").slice(-2):
		phases.append((event as PhaseChangedEvent).phase)
	assert_array(phases).is_equal([&"round", &"end"])


func test_a_leave_in_the_pregame_is_the_life_rule_s() -> void:
	var game := _in_pregame()
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.LEFT)
	for peer: int in [P1, P2]:
		var left := game.view_of(peer).events_named(&"PlayerLeft")
		assert_int(left.size()).is_equal(1)
		assert_int((left[0] as PlayerLeftEvent).peer).is_equal(P3)
	# Dealt players stay on the roster, `left`, for the round's win checks to count.
	assert_array(game.state.peers()).contains([P3])
	FixtureModes.run_ticks(game, PREGAME_TICKS + 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_connection_in_the_pregame_is_disconnected() -> void:
	var game := _in_pregame()
	FixtureModes.send(game, Intents.PEER_CONNECTED, 4)
	assert_array(FixtureBaseMode.directives(game).slice(-1)).is_equal(["DisconnectPeer 4"])
	assert_bool(game.state.newcomers.is_empty()).is_true()
	assert_str(game.phase_id()).is_equal("pregame")


func test_the_pregame_s_seconds_are_0_to_60() -> void:
	var phase := PregamePhase.new()
	for good: float in [0.0, 3.0, 60.0]:
		assert_array(Array(phase.check_settings({&"seconds": good}))).is_empty()
	assert_array(Array(phase.check_settings({}))).is_empty()
	assert_array(Array(phase.check_settings({&"seconds": 61.0}))).is_equal(
		["seconds is 61, outside 0 to 60"]
	)
	assert_array(Array(phase.check_settings({&"secs": 3.0}))).is_equal(["unknown setting secs"])
	assert_array(phase.outcomes()).is_equal([PregamePhase.PREGAME_DONE])


func test_a_mode_without_the_pregame_done_row_is_refused() -> void:
	var mode := FixtureBaseMode.mode()
	var rows: Array[Transition] = []
	for row: Transition in mode.transitions:
		if row.from != &"pregame":
			rows.append(row)
	mode.transitions = rows
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	assert_array(Array(game.refusals)).is_not_empty()


## FixtureBaseMode.mode() with roles dealt on the Loading row (one dissident among the crew) and
## the clock started on the Pregame row, as in the base mode (§9.5.1); the round's clock runs.
func _mode() -> GameMode:
	var mode := FixtureBaseMode.mode()
	var crew := FixtureModes.role(&"crew", &"crew", false)
	var dissident := FixtureModes.role(&"dissident", &"dissidents", true)
	mode.roles = [crew, dissident]
	mode.settings.append(FixtureModes.setting(&"dissidents", 1, 0, 3))
	mode.settings.append(FixtureModes.setting(&"match_duration", MINUTES, 1, 60))
	var loaded := mode.find_transition(&"loading", LoadingPhase.ALL_LOADED)
	loaded.actions.insert(0, FixtureDealModes.deal_roles(dissident, crew))
	var clock := StartClock.new()
	clock.minutes_setting = &"match_duration"
	mode.find_transition(&"pregame", PregamePhase.PREGAME_DONE).actions.append(clock)
	mode.find_phase(&"round").clock_runs = true
	return mode


## `PEERS` loaded: the match has just entered the pregame.
func _in_pregame() -> Match:
	var game := Match.new(_mode(), 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	assert_array(Array(game.refusals)).is_empty()
	game.start(0)
	for peer: int in PEERS:
		FixtureBaseMode.join(game, peer)
	for peer: int in PEERS:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	assert_str(game.phase_id()).is_equal("loading")
	for peer: int in PEERS:
		FixtureBaseMode.load_ack(game, peer)
	return game
