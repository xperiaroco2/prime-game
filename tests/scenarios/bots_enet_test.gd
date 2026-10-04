extends GdUnitTestSuite
## The ENet bots runner's start (BotsEnet, ARCHITECTURE §4.6, #284): its instances are processes
## that a loaded machine starts seconds apart, so bot 1 acts only once every bot that joins at the
## start is in its lobby, and a remote bot whose join went unanswered joins again. Built in code,
## no process started: `tools\run.cmd bots <scenario> --instances N` runs the real thing.

const BASE_MODE := "res://content/modes/base_mode.tres"
const NO_PORT := 9
const OUT := "user://bots_enet_test"


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
	var runner := BotsEnet.new(_scenario([[], []]), 2, NO_PORT, OUT)
	var bot := ScenarioBot.new(2, 0, [], runner.peers)
	runner.bots.append(bot)
	var first := runner.add_client(bot, LoopbackTransport.new(runner.schema.kind_table(), null))
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("still joining").is_same(first)
	first.end_reason = ClientSession.CONNECT_FAILED
	runner._join_again(bot)
	var second: BotClient = runner.clients[2]
	assert_object(second).is_not_same(first)
	second.leave()


func test_a_remote_bot_the_host_refused_or_lost_does_not_join_again() -> void:
	var runner := BotsEnet.new(_scenario([[], []]), 2, NO_PORT, OUT)
	var bot := ScenarioBot.new(2, 0, [], runner.peers)
	runner.bots.append(bot)
	var client := runner.add_client(bot, LoopbackTransport.new(runner.schema.kind_table(), null))
	client.end_reason = ClientSession.HOST_LOST
	runner._join_again(bot)
	assert_object(runner.clients[2]).is_same(client)
	client.end_reason = ClientSession.CONNECT_FAILED
	bot.joined = true
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("it had joined").is_same(client)


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
