extends GdUnitTestSuite
## Honest bots through a stall of the whole process (#284): the bots runner on a simulated clock
## that jumps once, as a loaded machine stalls the `bots-enet` processes (ARCHITECTURE §4.6).
## ScenarioBot fails a scenario on any Correction outside a placement, so an empty failure list
## says the host refused none of the bots' claims.

const BASE_MODE := "res://content/modes/base_mode.tres"
## Where bot 2 walks from its lobby spot (about 7 m away): bot 1 stays out of its path's push
## reach, so no push allowance hides a claim's excess travel.
const FAR_POINT := Vector3(0.0, 0.0, 12.0)
## The frame of the simulated clock (60 per second) a second into bot 2's walk.
const MID_WALK_FRAME := 90
const MSEC := 1000


func test_a_stall_in_the_middle_of_a_walk_corrects_no_honest_bot() -> void:
	# Before #284 the bot moved by every client tick the stall skipped, after its client had
	# claimed: the next claim covered one client tick and carried the stall's travel, and the host
	# corrected it (this test failed for 120 ms, 400 ms and 1.5 s, passed for 60 ms).
	for stall_ms: int in [60, 120, 400, 1500]:
		var runner := _walk_through(stall_ms * MSEC, false)
		(
			assert_array(Array(runner.failures))
			. override_failure_message("a stall of %d ms: %s" % [stall_ms, runner.failures])
			. is_empty()
		)
		assert_int(runner.clients[2].corrections).is_equal(0)


func test_a_stall_within_the_tick_lead_after_the_first_claim_corrects_no_honest_bot() -> void:
	# The first claim of an epoch waits out the stall in the host's socket, and the credit starts
	# when it is applied (MovementRule.TICK_LEAD): a stall up to the lead (0.5 s) costs nothing.
	var runner := _walk_through(400 * MSEC, true)
	assert_array(Array(runner.failures)).is_empty()
	assert_int(runner.clients[2].corrections).is_equal(0)


func test_a_stall_past_the_tick_lead_after_the_first_claim_corrects_once() -> void:
	# The accepted limit (ARCHITECTURE §7.1: a client whose ticks ran ahead of a stalled host's is
	# corrected once): past the lead the claims that follow cover more client ticks than the credit
	# counted since the first one was applied, and each bot's next claim is corrected (the run
	# stops there: ScenarioBot fails it). A rule change that forgives this changes this test.
	var runner := _walk_through(600 * MSEC, true)
	assert_str("\n".join(runner.failures)).contains("a Correction outside a placement")
	for number: int in [1, 2]:
		assert_int(runner.clients[number].corrections).is_equal(1)


## Bot 2 walks to FAR_POINT, a few seconds, while bot 1 stands; the simulated clock stalls once for
## `stall_usec`: a second into the walk, or `after_first_claim`, in the frame after bot 2's first
## claim (its Welcome's epoch).
func _walk_through(stall_usec: int, after_first_claim: bool) -> StalledRunner:
	var walk := StepWalkTo.new()
	walk.target = ScenarioTarget.new()
	walk.target.kind = ScenarioTarget.Kind.POINT
	walk.target.point = FAR_POINT
	var silent := StepTalk.new()
	silent.talking = false
	var scenario := _scenario([[silent, _wait(1.0)], [silent, _wait(0.5), walk]])
	var runner := StalledRunner.new(scenario)
	runner.stall_frame = -1 if after_first_claim else MID_WALK_FRAME
	runner.stall_usec = stall_usec
	runner.run()
	runner.close()
	return runner


## Two silent bots (a stall makes a voice backlog the relay thins out, which the one-process voice
## check would fail on) in the base mode's lobby.
func _scenario(scripts: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = scripts.size()
	scenario.session_seed = 490_000_000_284
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 15.0
	var made: Array[BotScript] = []
	for steps: Array in scripts:
		var script := BotScript.new()
		for step: ScenarioStep in steps:
			script.steps.append(step)
		made.append(script)
	scenario.scripts = made
	return scenario


func _wait(seconds: float) -> StepWait:
	var step := StepWait.new()
	step.seconds = seconds
	return step


## A bots runner whose clock stalls once for `stall_usec`: before frame `stall_frame`, or, when it
## is -1, in the frame after bot 2's first claim.
class StalledRunner:
	extends BotsRunner
	var stall_frame := -1
	var stall_usec := 0
	var _stalled := false

	func _frame_usec(frame: int) -> int:
		if _stalled:
			return FRAME_USEC
		var due := frame == stall_frame
		if stall_frame < 0:
			var client: BotClient = clients.get(2)
			due = client != null and client.last_claim_tick() >= 0
		_stalled = due
		return stall_usec if due else FRAME_USEC
