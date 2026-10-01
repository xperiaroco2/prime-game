extends GdUnitTestSuite
## The core scenario runner itself (tests/harness/, ARCHITECTURE §9.7): each way a scenario fails
## is seen failing here once, on the base mode and its real levels, so a green scenario suite means
## something. Scenarios built in code.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_a_target_the_bot_cannot_know_fails() -> void:
	# In the lobby nobody has been told of any package.
	var walk := StepWalkTo.new()
	walk.target = _target(ScenarioTarget.Kind.PACKAGE)
	var runner := ScenarioRunner.play(_scenario([[walk]]))
	assert_str(_text(runner)).contains("bot 1 (peer 1), step 1 (WalkTo)").contains("cannot know")


func test_an_unexpected_rejection_fails_with_its_reason() -> void:
	var put := StepPutDown.new()
	put.towards = _target(ScenarioTarget.Kind.POINT)
	var runner := ScenarioRunner.play(_scenario([[StepReady.new(), _round(), put]]))
	assert_str(_text(runner)).contains("step 3 (PutDown)").contains("Rejected (empty_hand)")


func test_an_expected_rejection_that_does_not_come_fails() -> void:
	var ready := StepReady.new()
	ready.expect_rejected = &"unchanged"
	var runner := ScenarioRunner.play(_scenario([[ready]]))
	assert_str(_text(runner)).contains("succeeded, but expected Rejected (unchanged)")
	# The same refusal, expected, passes: with bot 2 not ready the lobby stays, and a second
	# SetReady(true) changes nothing.
	var again := StepReady.new()
	again.expect_rejected = &"unchanged"
	var scenario := _scenario([[StepReady.new(), again]])
	scenario.bots = 2
	assert_array(Array(ScenarioRunner.play(scenario).failures)).is_empty()


func test_a_step_not_done_within_the_time_limit_fails() -> void:
	var never := StepWaitFor.new()
	never.event = &"MatchEnded"
	var scenario := _scenario([[never]])
	scenario.time_limit_s = 1.0
	var runner := ScenarioRunner.play(scenario)
	assert_str(_text(runner)).contains("step 1 (WaitFor)").contains("time limit")
	assert_int(runner.ticks_run).is_equal(21)


func test_a_load_ack_after_its_load_match_fails_by_name() -> void:
	# The LoadMatch arrives while the bot waits for the loading phase, so it is acknowledged at
	# once; the LoadAck step after it names that instead of running into the time limit.
	var loading := StepWaitFor.new()
	loading.event = &"PhaseChanged"
	loading.fields = {"phase": "loading"}
	var skip := StepLoadAck.new()
	skip.skip = true
	var runner := ScenarioRunner.play(_scenario([[StepReady.new(), loading, skip]]))
	assert_str(_text(runner)).contains("step 3 (LoadAck)").contains("acknowledged at once")


func test_expected_ends_that_do_not_arrive_fail() -> void:
	var scenario := _scenario([[StepReady.new()]])
	scenario.expected_ends = [&"crew"]
	scenario.time_limit_s = 2.0
	assert_str(_text(ScenarioRunner.play(scenario))).contains("crew")


func test_a_never_event_fails_when_it_arrives() -> void:
	var never := NeverEvent.new()
	never.event = &"ReadyChanged"
	never.fields = {"peer": 1}
	never.bot = 1
	var scenario := _scenario([[StepReady.new()]])
	scenario.never = [never]
	assert_str(_text(ScenarioRunner.play(scenario))).contains("which the scenario says never")


func test_a_correction_outside_a_placement_fails() -> void:
	# An honest bot is never corrected (§9.7): only a placement or its own death explains one.
	var bot := ScenarioBot.new(2, ScenarioPeers.core(2).peer_of(2), [])
	var problem := _receive(bot, CorrectionEvent.new(bot.peer, 3, Vector3(1, 0, 1), Vector3.ZERO))
	assert_str(problem).contains("Correction outside a placement")
	# The placement's Correction is expected even when a network poll splits it from PlayersPlaced.
	var spots: Dictionary[int, Vector3] = {bot.peer: Vector3(2, 0, 2)}
	assert_str(_receive(bot, PlayersPlacedEvent.new(spots))).is_empty()
	(
		assert_str(_receive(bot, CorrectionEvent.new(bot.peer, 4, Vector3(2, 0, 2), Vector3.ZERO)))
		. is_empty()
	)
	assert_int(bot.epoch).is_equal(4)
	assert_vector(bot.position).is_equal(Vector3(2, 0, 2))
	# One Correction per placement: a second one is not explained.
	var again := _receive(bot, CorrectionEvent.new(bot.peer, 5, Vector3(3, 0, 3), Vector3.ZERO))
	assert_str(again).contains("Correction outside a placement")
	# A placement of another player explains none.
	var others: Dictionary[int, Vector3] = {bot.peer + 1: Vector3(4, 0, 4)}
	assert_str(_receive(bot, PlayersPlacedEvent.new(others))).is_empty()
	var theirs := _receive(bot, CorrectionEvent.new(bot.peer, 6, Vector3(4, 0, 4), Vector3.ZERO))
	assert_str(theirs).contains("Correction outside a placement")


func test_the_invariants_catch_a_leak() -> void:
	# A wrong audience (§5): Teammates to a crew member, another player's SelfStatus.
	var runner := ScenarioRunner.play(_scenario([[StepReady.new(), _round()]]))
	assert_array(Array(runner.failures)).is_empty()
	var invariants := ScenarioInvariants.new(runner.game, runner.scenario)
	runner.game.state.players[1].role = &"crew"
	var leak := EmittedEvent.new(
		0, TeammatesEvent.new(&"dissident", PackedInt32Array([1])), PackedInt32Array([1]), false
	)
	assert_str("\n".join(invariants.check_event(leak))).contains("learned")
	var status := EmittedEvent.new(
		0, SelfStatusEvent.new(7, 100, 100, true), PackedInt32Array([1]), false
	)
	assert_str("\n".join(invariants.check_event(status))).contains("received SelfStatus of peer 7")
	var seed_leak := EmittedEvent.new(
		0, RoundStartedEvent.new(runner.scenario.session_seed), PackedInt32Array([1]), false
	)
	assert_str("\n".join(invariants.check_event(seed_leak))).contains("holds a seed")


func test_the_invariants_catch_a_misrouted_task_event_or_rejection() -> void:
	var runner := ScenarioRunner.play(_scenario([[StepReady.new()], []]))
	assert_array(Array(runner.failures)).is_empty()
	var invariants := ScenarioInvariants.new(runner.game, runner.scenario)
	var partial := EmittedEvent.new(0, TaskProgressEvent.new(0, 6), PackedInt32Array([1]), false)
	assert_str("\n".join(invariants.check_event(partial))).contains("not every present player")
	# Every bot numbers its intents alike, so only the sender's peer id tells a misrouted Rejected.
	invariants.sender = 1
	var misrouted := EmittedEvent.new(
		0, RejectedEvent.new(1, 2, &"too_soon"), PackedInt32Array([1002]), false
	)
	assert_str("\n".join(invariants.check_event(misrouted))).contains("not the sender 1")


func test_the_invariants_catch_a_leak_in_snapshots_and_voice() -> void:
	var runner := ScenarioRunner.play(_scenario([[StepReady.new()], []]))
	assert_array(Array(runner.failures)).is_empty()
	var leaky := LeakyMatch.new(runner.game)
	leaky.state.players[1002].life = PlayerState.Life.GHOST
	leaky.avatars = {
		1002: {"position": Vector3.ZERO, "health": 100, "held_item": runner.scenario.session_seed}
	}
	leaky.speakers = PackedInt32Array([1002])
	var found := "\n".join(ScenarioInvariants.new(leaky, runner.scenario).check_tick())
	assert_str(found).contains("living peer 1 sees ghost 1002")
	assert_str(found).contains("living peer 1 hears ghost 1002")
	assert_str(found).contains("shows health of peer 1002")
	assert_str(found).contains("peer 1's snapshot holds a seed")


func test_a_match_error_or_a_view_that_differs_fails() -> void:
	var runner := ScenarioRunner.play(_scenario([[StepReady.new()]]))
	assert_array(Array(runner.failures)).is_empty()
	runner.game.diagnostics.append("error: a planted match error")
	runner._check_after()
	assert_str(_text(runner)).contains("match error: a planted match error")
	runner.failures.clear()
	runner.game.diagnostics.clear()
	runner.bots[0].events.append(WireMessage.new(&"ReadyChanged", {"peer": 1, "ready": false}))
	runner._check_after()
	assert_str(_text(runner)).contains("but view_of(1) holds")


func test_an_expect_that_times_out_or_an_expect_none_that_sees_its_event_fails() -> void:
	var expect := StepExpect.new()
	expect.event = &"MatchEnded"
	expect.within_s = 0.5
	var runner := ScenarioRunner.play(_scenario([[StepReady.new(), expect]]))
	assert_str(_text(runner)).contains("step 2 (Expect)")
	var none := StepExpectNone.new()
	none.event = &"ReadyChanged"
	none.for_s = 2.0
	var later := StepWait.new()
	later.seconds = 0.5
	runner = ScenarioRunner.play(_scenario([[none], [later, StepReady.new()]]))
	assert_str(_text(runner)).contains("step 1 (ExpectNone)")


func test_fields_name_players_by_bot_number() -> void:
	var peers := ScenarioPeers.core(3)
	var event := ReadyChangedEvent.new(peers.peer_of(3), true)
	assert_bool(ScenarioPlay.event_matches(event, &"ReadyChanged", {"peer": 3}, peers)).is_true()
	(
		assert_bool(ScenarioPlay.event_matches(event, &"ReadyChanged", {"peer": 1003}, peers))
		. is_false()
	)
	(
		assert_bool(ScenarioPlay.event_matches(event, &"ReadyChanged", {"ready": false}, peers))
		. is_false()
	)
	assert_bool(ScenarioPlay.event_matches(event, &"PhaseChanged", {}, peers)).is_false()
	var phase := PhaseChangedEvent.new(&"round", -1)
	(
		assert_bool(ScenarioPlay.event_matches(phase, &"PhaseChanged", {"phase": "round"}, peers))
		. is_true()
	)
	# What a bot received, as (name, fields): the same rules, through the runner's own map.
	var bot := ScenarioBot.new(3, peers.peer_of(3), [], peers)
	var got := WireMessage.new(&"ReadyChanged", event.to_dict())
	(
		assert_bool(ScenarioPlay.matches_fields(got, bot, &"ReadyChanged", {"peer": 3}, peers))
		. is_true()
	)
	var other := ScenarioPeers.new()
	other.set_peer(3, 7)
	(
		assert_bool(ScenarioPlay.matches_fields(got, bot, &"ReadyChanged", {"peer": 3}, other))
		. is_false()
	)
	# An event for one peer names none in its payload: its receiver is its subject.
	var status := WireMessage.new(&"SelfStatus", SelfStatusEvent.new(1003, 90, 50, true).to_dict())
	(
		assert_bool(ScenarioPlay.matches_fields(status, bot, &"SelfStatus", {"peer": 3}, peers))
		. is_true()
	)
	(
		assert_bool(ScenarioPlay.matches_fields(status, bot, &"SelfStatus", {"peer": 2}, peers))
		. is_false()
	)


## A match whose snapshots and voice routing show what a test plants, over another match's state.
class LeakyMatch:
	extends Match
	var avatars: Dictionary = {}
	var speakers := PackedInt32Array()

	func _init(played: Match) -> void:
		super(played.mode, 1, FlatWorldQuery.new(), {})
		state = played.state

	func snapshot_for(_peer: int) -> Dictionary:
		return {"avatars": avatars}

	func speakers_for(_listener: int) -> PackedInt32Array:
		return speakers


func _scenario(scripts: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = maxi(1, scripts.size())
	scenario.session_seed = 490_000_000_009
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 20.0
	var made: Array[BotScript] = []
	for steps: Array in scripts:
		var script := BotScript.new()
		for step: ScenarioStep in steps:
			script.steps.append(step)
		made.append(script)
	scenario.scripts = made
	return scenario


func _round() -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"PhaseChanged"
	step.fields = {"phase": "round"}
	return step


func _target(kind: ScenarioTarget.Kind) -> ScenarioTarget:
	var target := ScenarioTarget.new()
	target.kind = kind
	return target


func _text(runner: ScenarioRunner) -> String:
	return "\n".join(runner.failures)


func _receive(bot: ScenarioBot, event: MatchEvent) -> String:
	return bot.receive(event.event_name(), event.to_dict())
