extends GdUnitTestSuite
## The chaos run's start over ENet (ChaosRun, ARCHITECTURE §4.6 "Chaos bots", #318): as BotsEnet
## after #284, the bots play once every bot that joins at the start is in bot 1's lobby, and a bot
## whose join went unanswered joins again, judged on the real clock. Built in code, no ENet socket:
## `tools\run.cmd bots --chaos --enet` runs the real thing.

const NO_PORT := 9
const FRAME_USEC := 16_667
const START_USEC := 1_000_000


## The chaos run over ENet with its bots' joins on a LoopbackTransport of an empty hub (no host:
## connect_failed at the first poll), on a join clock the test sets.
class UnhostedChaos:
	extends ChaosRun

	var clock_usec := START_USEC

	func _init() -> void:
		super(false, ChaosRun.Mode.CHAOS, 1, NO_PORT)

	func add_bots() -> void:
		for number in range(1, scenario.bots + 1):
			bots.append(ScenarioBot.new(number, 0, scenario.steps_of(number), peers))

	func _joining() -> NetTransport:
		var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
		transport.join("loopback", NO_PORT)
		return transport

	func _join_clock_usec() -> int:
		return clock_usec


func test_over_enet_the_bots_play_once_every_bot_is_in_bot_1s_lobby() -> void:
	var run := UnhostedChaos.new()
	run.add_bots()
	var host := run.bots[0]
	for number in range(1, run.scenario.bots + 1):
		run.peers.set_peer(number, 10 * number)
	# Every peer id is known (each bot `connected`), but no Hello was admitted yet.
	assert_bool(run._may_play()).override_failure_message("peer ids alone").is_false()
	host.seen[20] = Vector3.ZERO
	host.seen[30] = Vector3.ZERO
	assert_bool(run._may_play()).override_failure_message("the hostile not joined").is_false()
	host.seen[40] = Vector3.ZERO
	assert_bool(run._may_play()).is_true()
	host.seen.clear()
	assert_bool(run._may_play()).override_failure_message("decided once").is_true()


func test_over_the_loopback_the_bots_play_at_once() -> void:
	var run := ChaosRun.new()
	for number in range(1, run.scenario.bots + 1):
		run.bots.append(ScenarioBot.new(number, 0, run.scenario.steps_of(number), run.peers))
	assert_bool(run._may_play()).is_true()


func test_a_bot_whose_join_went_unanswered_joins_again() -> void:
	var run := UnhostedChaos.new()
	run.add_bots()
	var bot := run.bots[1]
	run._connect(bot)
	var first: BotClient = run.clients[2]
	first.step(START_USEC)
	assert_str(first.end_reason).is_equal(ClientSession.CONNECT_FAILED)
	run.clock_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	run._join_again(bot)
	var second: BotClient = run.clients[2]
	assert_object(second).is_not_same(first)
	assert_bool(second.is_ended()).is_false()
	assert_bool(run._may_play()).override_failure_message("it is joining again").is_false()
	assert_array(run.failures).is_empty()
	second.leave()


func test_a_join_refused_at_once_does_not_join_again_and_ends_the_wait() -> void:
	var run := UnhostedChaos.new()
	run.add_bots()
	var bot := run.bots[1]
	run._connect(bot)
	var client: BotClient = run.clients[2]
	client.step(START_USEC)
	run.clock_usec += FRAME_USEC
	run._join_again(bot)
	assert_object(run.clients[2]).is_same(client)
	run.clock_usec += 2 * EnetTransport.JOIN_TIMEOUT_MS * 1000
	run._join_again(bot)
	assert_object(run.clients[2]).override_failure_message("judged when first seen").is_same(client)
	# The bots play, so that its lost join fails the run at once (_lost), not at the time limit.
	assert_bool(run._may_play()).is_true()


func test_over_enet_a_join_is_judged_on_the_real_clock() -> void:
	var run := ChaosRun.new(false, ChaosRun.Mode.CHAOS, 1, NO_PORT)
	# Behind any real clock: the simulated one starts at BotsRunner.START_USEC.
	run.now_usec = -1
	var before := Time.get_ticks_usec()
	assert_int(run._join_clock_usec()).is_greater_equal(before)
	var loopback := ChaosRun.new()
	loopback.now_usec = START_USEC
	assert_int(loopback._join_clock_usec()).is_equal(START_USEC)
