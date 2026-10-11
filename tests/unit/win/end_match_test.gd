extends GdUnitTestSuite
## EndMatch and MatchEnded (ARCHITECTURE §3.2, §4.2, §5, §9.4): `Round, won -> End` records the
## winning side and tells everyone the side, the winning condition's id and the round's time
## (#548), no name and no role. End widens nothing: written here independently of the audience
## declarations, over the whole session (lobby, round, end and back to the lobby), a crew member
## learns one role, its own, and nobody learns a role at the end.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const PEERS: Array[int] = [P1, P2, P3, P4]


func test_match_ended_names_the_side_the_condition_and_the_time_to_every_player() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), PEERS)
	assert_int(game.state.clock_ticks_total).is_equal(FixtureWinModes.CLOCK_TICKS)
	var crew := FixtureDealModes.players_of(game, &"crew")
	# 7.25 s of the round: the time is in whole seconds, toward zero.
	FixtureModes.run_ticks(game, 7 * Ticks.RATE + 5)
	FixtureWinModes.deliver(game, crew[0], 0)
	assert_str(game.state.winner).is_equal("crew")
	var sent := game.emitted().filter(
		func(e: EmittedEvent) -> bool: return e.event is MatchEndedEvent
	)
	assert_int(sent.size()).is_equal(1)
	var ended := sent[0] as EmittedEvent
	assert_array(Array(ended.recipients)).is_equal(PEERS)
	assert_bool(ended.is_directive).is_false()
	assert_dict(ended.event.to_dict()).is_equal(
		{"side": &"crew", "reason": &"every_task_done", "numbers": {&"time": 7}}
	)
	assert_int(MatchEndedEvent.AUDIENCE_KIND).is_equal(ended.event.audience().kind)
	assert_int(MatchEndedEvent.AUDIENCE_KIND).is_equal(Audience.Kind.EVERYONE)


func test_the_win_ends_the_round_with_match_ended_then_the_end_phase() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), PEERS)
	var from: Dictionary[int, int] = {}
	for peer: int in PEERS:
		from[peer] = game.view_of(peer).events.size()
	FixtureWinModes.run_through(game, FixtureWinModes.announced_end(game, P1))
	for peer: int in PEERS:
		var view := game.view_of(peer)
		var names := view.event_names().slice(from[peer])
		# Only SelfStatus (own numbers) can come before: the round saw no other change.
		names = names.filter(func(n: StringName) -> bool: return n != &"SelfStatus")
		assert_array(names).is_equal([&"MatchEnded", &"PhaseChanged"])
		var changed := view.events_named(&"PhaseChanged").back() as PhaseChangedEvent
		assert_str(changed.phase).is_equal("end")
		assert_int(changed.end_tick).is_equal(-1)


func test_end_widens_nothing_and_no_role_reaches_anyone_over_the_session() -> void:
	# Four players, one dissident: the dissidents win on the clock, the host returns to the lobby.
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), PEERS)
	var dissident := FixtureDealModes.players_of(game, &"dissident")[0]
	FixtureWinModes.run_through(game, FixtureWinModes.announced_end(game, P1))
	var at_end: Dictionary[int, int] = {}
	for peer: int in PEERS:
		at_end[peer] = game.view_of(peer).events.size()
	assert_str(game.state.winner).is_equal("dissidents")
	FixtureModes.run_ticks(game, 5)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	FixtureModes.run_ticks(game, 5)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(game.state.clock_ticks_total).is_equal(-1)
	for peer: int in PEERS:
		var view := game.view_of(peer)
		# Whole session: its own RoleAssigned only; a crew member no Teammates, and no payload
		# anywhere holds the dissident role's id.
		var told := view.events_named(&"RoleAssigned")
		assert_int(told.size()).is_equal(1)
		assert_int((told[0] as RoleAssignedEvent).peer).is_equal(peer)
		if peer != dissident:
			assert_array(view.events_named(&"Teammates")).is_empty()
			for event: MatchEvent in view.events:
				(
					assert_bool(_names_role(event, &"dissident"))
					. override_failure_message("%s reveals a role" % event.event_name())
					. is_false()
				)
		# From the end on, nobody learns a role: MatchEnded holds the side, the condition and
		# the time alone (#548: all three public).
		var from := view.event_names().find(&"MatchEnded")
		assert_int(from).is_less(at_end[peer])
		for event: MatchEvent in view.events.slice(from):
			assert_bool(event is RoleAssignedEvent or event is TeammatesEvent).is_false()
			assert_bool(_names_role(event, &"dissident")).is_false()
			if not (event is MatchEndedEvent):
				assert_bool(_names_role(event, &"crew")).is_false()
		var ended := view.events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		assert_array(ended[0].to_dict().keys()).is_equal(["side", "reason", "numbers"])
		assert_dict(ended[0].to_dict()).is_equal(
			{"side": &"dissidents", "reason": &"time_up", "numbers": {&"time": 60}}
		)


func test_an_argument_that_is_no_side_is_a_rule_error_and_ends_nothing() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2])
	var seen := game.emitted().size()
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.outcome = Match.WON
	for argument: Variant in [&"pirates", null, 3]:
		ctx.outcome_argument = argument
		EndMatch.new().run(ctx)
	assert_int(game.emitted().size()).is_equal(seen)
	assert_str(game.state.winner).is_empty()
	assert_int(game.diagnostics.size()).is_equal(3)
	assert_str(game.diagnostics[0]).contains("pirates is not a side of the mode")
	assert_str(game.diagnostics[1]).contains("carries no side")


## A `won` that no win condition reported (a rule's) has no reason; a reason without a clock that
## ran has no time (#548).
func test_a_won_without_a_condition_names_no_reason_and_no_clock_no_time() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2])
	var seen := game.emitted().size()
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.outcome = Match.WON
	ctx.outcome_argument = &"crew"
	EndMatch.new().run(ctx)
	game.state.clock_ticks_total = -1
	ctx.outcome_reason = &"every_task_done"
	EndMatch.new().run(ctx)
	var sent := game.emitted().slice(seen).map(
		func(e: EmittedEvent) -> Dictionary: return e.event.to_dict()
	)
	assert_array(sent).is_equal(
		[{"side": &"crew"}, {"side": &"crew", "reason": &"every_task_done", "numbers": {}}]
	)


## Whether `event`'s payload holds the role id `role_id` as a value (a StringName or String),
## written against the payload itself, not the event's audience.
static func _names_role(event: MatchEvent, role_id: StringName) -> bool:
	return _holds(event.to_dict(), String(role_id))


static func _holds(value: Variant, text: String) -> bool:
	if value is StringName or value is String:
		return str(value) == text
	if value is Dictionary:
		var fields: Dictionary = value
		for key: Variant in fields:
			if _holds(key, text) or _holds(fields[key], text):
				return true
	if value is Array:
		for item: Variant in value:
			if _holds(item, text):
				return true
	return false
