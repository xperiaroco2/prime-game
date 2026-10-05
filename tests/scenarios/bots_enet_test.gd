extends GdUnitTestSuite
## The ENet bots runner's start (BotsEnet, ARCHITECTURE §4.6, #284): its instances are processes
## that a loaded machine starts seconds apart, so bot 1 acts only once every bot that joins at the
## start is in its lobby, and a remote bot whose join went unanswered joins again. Built in code,
## no process started: `tools\run.cmd bots <scenario> --instances N` runs the real thing.

const BASE_MODE := "res://content/modes/base_mode.tres"
const NO_PORT := 9
const OUT := "user://bots_enet_test"
const START_USEC := 1_000_000
const FRAME_USEC := 16_667


## Bot 2's instance with its joins on a LoopbackTransport that is never hosted: no ENet client.
class RemoteBot:
	extends BotsEnet

	func _init(bot_scenario: BotScenario) -> void:
		super(bot_scenario, 2, NO_PORT, OUT)

	func add_bot() -> ScenarioBot:
		var bot := ScenarioBot.new(2, 0, scenario.steps_of(2), peers)
		bots.append(bot)
		return bot

	func _joining() -> NetTransport:
		return LoopbackTransport.new(schema.kind_table(), null)


func test_bot_1_acts_once_every_bot_that_joins_at_the_start_is_in_its_lobby() -> void:
	var late := StepJoin.new()
	var runner := BotsEnet.new(_scenario([[], [], [late]]), 1, NO_PORT, OUT)
	var bot := ScenarioBot.new(1, 1, [], runner.peers)
	runner.peers.set_peer(1, 1)
	assert_bool(runner._lobby_full(bot)).is_false()
	runner.peers.set_peer(2, 22)
	assert_bool(runner._lobby_full(bot)).is_false()
	bot.seen[22] = Vector3.ZERO
	# Bot 3 joins later (a Join step): bot 1 does not wait for it.
	assert_bool(runner._lobby_full(bot)).is_true()
	bot.seen.erase(22)
	assert_bool(runner._lobby_full(bot)).override_failure_message("decided once").is_true()


func test_bot_1_waits_for_a_bot_it_knows_the_peer_of_until_that_bot_joined() -> void:
	var runner := BotsEnet.new(_scenario([[], [], []]), 1, NO_PORT, OUT)
	var bot := ScenarioBot.new(1, 1, [], runner.peers)
	runner.peers.set_peer(2, 22)
	runner.peers.set_peer(3, 33)
	bot.seen[22] = Vector3.ZERO
	assert_bool(runner._lobby_full(bot)).is_false()
	bot.seen[33] = Vector3.ZERO
	assert_bool(runner._lobby_full(bot)).is_true()


func test_a_remote_bot_whose_join_went_unanswered_joins_again() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var first: BotClient = runner.clients[2]
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("still joining").is_same(first)
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	first.end_reason = ClientSession.CONNECT_FAILED
	runner._join_again(bot)
	var second: BotClient = runner.clients[2]
	assert_object(second).is_not_same(first)
	assert_array(runner.failures).is_empty()
	second.leave()


func test_a_join_the_host_refused_at_once_does_not_join_again() -> void:
	# EnetTransport refuses before the admission by disconnecting: connect_failed within a poll.
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var client: BotClient = runner.clients[2]
	client.end_reason = ClientSession.CONNECT_FAILED
	runner.now_usec += FRAME_USEC
	runner._join_again(bot)
	assert_object(runner.clients[2]).is_same(client)
	runner.now_usec += 2 * EnetTransport.JOIN_TIMEOUT_MS * 1000
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("judged when first seen").is_same(
		client
	)


func test_a_remote_bot_the_host_refused_or_lost_does_not_join_again() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var client: BotClient = runner.clients[2]
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	# A Rejected Hello: the host admitted the join, then disconnected it.
	client.end_reason = ClientSession.HOST_LOST
	runner._join_again(bot)
	assert_object(runner.clients[2]).is_same(client)
	client.end_reason = ClientSession.CONNECT_FAILED
	bot.joined = true
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("it had joined").is_same(client)


func test_a_bot_that_joins_late_does_not_join_again() -> void:
	var runner := RemoteBot.new(_scenario([[], [StepJoin.new()]]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var client: BotClient = runner.clients[2]
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	client.end_reason = ClientSession.CONNECT_FAILED
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("its Join step reads it").is_same(
		client
	)


func test_over_webrtc_a_join_that_found_no_room_joins_again_after_a_short_wait() -> void:
	# The host's process, or its signalling's room, is not up yet: the service answers at once.
	for reason: StringName in [NetTransport.JOIN_NO_ROOM, NetTransport.JOIN_SERVICE_UNREACHABLE]:
		var runner := RemoteBot.new(_scenario([[], []]))
		var bot := runner.add_bot()
		runner.now_usec = START_USEC
		runner._join_host(bot)
		var first: BotClient = runner.clients[2]
		first.end_reason = reason
		runner.now_usec += FRAME_USEC
		runner._join_again(bot)
		assert_object(runner.clients[2]).override_failure_message("waits first").is_same(first)
		runner.now_usec += NetPlay.ROOM_RETRY_USEC
		runner._join_again(bot)
		var second: BotClient = runner.clients[2]
		assert_object(second).override_failure_message(String(reason)).is_not_same(first)
		second.leave()


func test_over_webrtc_a_join_that_reached_the_room_does_not_join_again() -> void:
	# The match has started, or the room is full: the host's own answer. host_unreachable: the
	# service answered and the connection never opened, a transport fault the run must not ride out.
	for reason: StringName in [
		NetTransport.JOIN_STARTED,
		NetTransport.JOIN_FULL,
		NetTransport.JOIN_UNREACHABLE,
		NetTransport.JOIN_FAILED,
	]:
		var runner := RtcRemoteBot.new(_scenario([[], []]))
		var bot := runner.add_bot()
		runner.now_usec = START_USEC
		runner._join_host(bot)
		var client: BotClient = runner.clients[2]
		runner.now_usec += WebRtcTransport.JOIN_TIMEOUT_MS * 1000
		client.end_reason = reason
		runner._join_again(bot)
		runner.now_usec += 2 * WebRtcTransport.JOIN_TIMEOUT_MS * 1000
		runner._join_again(bot)
		assert_object(runner.clients[2]).override_failure_message(String(reason)).is_same(client)
		client.leave()


## Bot 2's instance over WebRTC, its joins never started (no signalling).
class RtcRemoteBot:
	extends RemoteBot

	func _joining() -> NetTransport:
		return WebRtcTransport.new(schema.kind_table())


## A scenario of one script per bot in the base mode, each a list of steps.
func _scenario(scripts: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = scripts.size()
	scenario.session_seed = 490_000_000_284
	scenario.expected_ends = [BotScenario.NONE]
	var made: Array[BotScript] = []
	for steps: Array in scripts:
		var script := BotScript.new()
		for step: ScenarioStep in steps:
			script.steps.append(step)
		made.append(script)
	scenario.scripts = made
	return scenario
