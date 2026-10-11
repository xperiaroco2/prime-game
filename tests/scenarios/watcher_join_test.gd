extends GdUnitTestSuite
## The watchers' joins (BotWatcher, ARCHITECTURE §4.6.4, #509): a lurker or refused bot whose join
## was lost the way a bot's is joined again (JoinRetry: no answer, or the signalling's 5 s cap)
## joins again on a new transport, MAX_JOINS joins at most, and the leak test then runs on it
## unchanged; a join that fails every try, or for another reason, fails the leak test naming its
## reason and those of its earlier joins. Played by the one-process runner, its watcher joins lost
## on a transport that fails as the test says.

const BASE_MODE := "res://content/modes/base_mode.tres"


## A join that ends for `reason` at its `polls`-th poll, never reaching a host.
class LostJoin:
	extends LoopbackTransport

	var reason: StringName
	var polls_left := 1

	func _init(kinds: NetKindTable, why: StringName, polls: int) -> void:
		super(kinds, LoopbackHub.new())
		reason = why
		polls_left = polls

	func _backend_join(_address: String, _port: int) -> Error:
		return OK

	func _backend_poll() -> void:
		polls_left -= 1
		if polls_left <= 0:
			_end_client(reason)


## The one-process runner whose `_joining()` calls (bot 2 is the 1st, the lurker the 2nd, the
## refused bot the 3rd, each join again the next) may be lost: the call numbers in lost_reason, or
## every call from lose_from on (at its first poll, for lose_from_reason).
class LosingRunner:
	extends BotsRunner

	var lost_reason: Dictionary[int, StringName] = {}
	var lost_after: Dictionary[int, int] = {}
	var lose_from := 0
	var lose_from_reason := NetTransport.JOIN_SERVICE_UNREACHABLE
	var joinings := 0

	func _joining() -> NetTransport:
		joinings += 1
		var transport: NetTransport = null
		if lost_reason.has(joinings):
			transport = LostJoin.new(
				schema.kind_table(), lost_reason[joinings], lost_after.get(joinings, 1) as int
			)
		elif lose_from > 0 and joinings >= lose_from:
			transport = LostJoin.new(schema.kind_table(), lose_from_reason, 1)
		else:
			return super()
		transport.join("loopback", port)
		return transport


func test_a_watcher_join_lost_to_the_signalling_cap_or_unanswered_joins_again() -> void:
	var runner := LosingRunner.new(_scenario())
	# The lurker's first join ends at the signalling's cap; the refused bot's goes unanswered for
	# 160 frames (2.7 s, past JoinRetry.UNANSWERED_USEC), as an ENet join the host never admitted.
	runner.lost_reason = {2: NetTransport.JOIN_SERVICE_UNREACHABLE, 3: ClientSession.CONNECT_FAILED}
	runner.lost_after = {2: 1, 3: 160}
	runner.run()
	runner.close()
	assert_array(Array(runner.failures)).is_empty()
	assert_int(runner.joinings).override_failure_message("one join again each").is_equal(5)
	assert_int(runner.lurker.peer).is_not_zero()
	assert_int(runner.refused.peer).is_not_zero()
	assert_array(Array(runner.lurker.joins.ends)).contains_exactly(["service_unreachable"])
	assert_array(Array(runner.refused.joins.ends)).contains_exactly(["connect_failed"])


func test_a_watcher_joins_max_joins_times_and_then_names_every_reason() -> void:
	var runner := LosingRunner.new(_scenario())
	runner.lose_from = 2
	runner.run()
	runner.close()
	assert_int(runner.joinings).is_equal(1 + 2 * BotWatcher.MAX_JOINS)
	var reason := (
		"it never connected (connect_failed, reason service_unreachable; earlier joins ended"
		+ " service_unreachable, service_unreachable)"
	)
	for label: String in ["lurker", "refused"]:
		var lines := Array(runner.failures).filter(
			func(line: String) -> bool: return line.contains("%s (peer 0): " % label)
		)
		assert_array(lines).override_failure_message(label).has_size(1)
		assert_str(lines[0] if not lines.is_empty() else "").contains(reason)


func test_a_watcher_join_refused_or_unreachable_does_not_join_again() -> void:
	# The connection never opened, the match started, the host refused it at once (ENet answers a
	# refusal within a poll): each stays the failure it was. The refused bot connects and is
	# refused, and is not joined again either.
	var reasons: Dictionary[StringName, String] = {
		NetTransport.JOIN_UNREACHABLE: "reason host_unreachable",
		NetTransport.JOIN_STARTED: "reason joins_closed",
		NetTransport.JOIN_FAILED: "the backend gave no precise reason",
	}
	for why: StringName in reasons:
		var runner := LosingRunner.new(_scenario())
		runner.lost_reason = {2: why}
		runner.run()
		runner.close()
		assert_int(runner.joinings).override_failure_message(String(why)).is_equal(3)
		var text := "\n".join(runner.failures)
		assert_str(text).contains("lurker (peer 0): it never connected (connect_failed, ")
		assert_str(text).contains(reasons[why]).not_contains("earlier joins")
		assert_int(runner.refused.peer).is_not_zero()


## Two bots that wait 4 s in the lobby, so a watcher joined again is in time, then play to the
## round.
func _scenario() -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = 2
	scenario.session_seed = 490_000_000_509
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 30.0
	var made: Array[BotScript] = []
	for _bot in scenario.bots:
		var script := BotScript.new()
		var wait := StepWait.new()
		wait.seconds = 4.0
		var round_started := StepWaitFor.new()
		round_started.event = &"PhaseChanged"
		round_started.fields = {"phase": "round"}
		script.steps.append(wait)
		script.steps.append(StepReady.new())
		script.steps.append(round_started)
		made.append(script)
	scenario.scripts = made
	return scenario
