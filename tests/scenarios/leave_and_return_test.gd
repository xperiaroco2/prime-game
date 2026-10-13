extends GdUnitTestSuite
## A leave and a return in the bots (#639, 73-B of the returning-players ADR; ARCHITECTURE §9.7,
## §4.6.4): each bot's return key is fixed from its number, a Join may follow the bot's own Leave
## and joins it again on a new peer with its old number, and the leak test checks each connection.
## Scenarios built in code, on the base mode, in the core runner and over the loopback.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_each_bot_sends_one_key_fixed_from_its_number() -> void:
	var keys := {}
	for number in range(1, 5):
		var key := ScenarioBot.key_of(number)
		assert_bool(ReturnKey.is_valid(key)).is_true()
		assert_str(key).is_equal(ScenarioBot.key_of(number))
		keys[key] = number
	assert_int(keys.size()).is_equal(4)
	var scripts := [[StepReady.new(), _round()], [StepReady.new(), _round()]]
	var core := ScenarioRunner.play(_scenario(scripts))
	assert_array(Array(core.failures)).is_empty()
	var net := BotsRunner.play(_scenario(scripts))
	assert_array(Array(net.failures)).is_empty()
	for game: Match in [core.game, net.game]:
		assert_dict(game.state.numbers).is_equal(
			{ScenarioBot.key_of(1): 1, ScenarioBot.key_of(2): 2}
		)
	# Both runners' bots ask for no name: the host names each Player<its number>.
	assert_str(core.game.state.players[core.peers.peer_of(2)].name).is_equal("Player2")
	assert_str(net.game.state.players[net.peers.peer_of(2)].name).is_equal("Player2")
	assert_str(net.clients[2].return_key).is_equal(ScenarioBot.key_of(2))


func _scenario(scripts: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = maxi(1, scripts.size())
	scenario.session_seed = 490_000_000_013
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 30.0
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
