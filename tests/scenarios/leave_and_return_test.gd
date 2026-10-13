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


func test_a_bot_that_left_the_lobby_returns_on_a_new_peer_with_its_number() -> void:
	var runner := ScenarioRunner.play(_scenario(_lobby_scripts()))
	assert_array(Array(runner.failures)).is_empty()
	var state := runner.game.state
	var had := runner.peers.peers_of(2)
	assert_int(had.size()).is_equal(2)
	var old := had[0]
	var now := had[1]
	# A peer id no bot had before in the session.
	for bot: int in [1, 3, 4]:
		assert_array(Array(runner.peers.peers_of(bot))).not_contains([now])
	assert_int(runner.peers.bot_of(old)).is_equal(2)
	assert_int(state.players[now].number).is_equal(2)
	assert_str(state.players[now].name).is_equal("Player2")
	assert_int(state.players[runner.peers.peer_of(4)].number).is_equal(4)
	assert_str(state.players[runner.peers.peer_of(4)].name).is_equal("Player4")
	assert_int(state.numbers[ScenarioBot.key_of(2)]).is_equal(2)
	assert_int(state.numbers[ScenarioBot.key_of(4)]).is_equal(4)
	# Bot 2 left, bot 4 joined while it was away, then bot 2 returned (bot 1's view, in order).
	var order := []
	for event: MatchEvent in runner.game.view_of(1).events:
		var fields := event.to_dict()
		if event.event_name() == &"PlayerLeft" or event.event_name() == &"PlayerJoined":
			order.append([event.event_name(), fields["peer"]])
	var left_at := order.find([&"PlayerLeft", old])
	assert_int(left_at).is_greater_equal(0)
	assert_int(order.find([&"PlayerJoined", runner.peers.peer_of(4)])).is_greater(left_at)
	assert_int(order.find([&"PlayerJoined", now])).is_greater(
		order.find([&"PlayerJoined", runner.peers.peer_of(4)])
	)
	# Each connection was checked as its own view; the earlier one is kept.
	var bot_2 := runner.bots[1]
	assert_int(bot_2.lives.size()).is_equal(1)
	assert_int(bot_2.lives[0]["peer"]).is_equal(old)
	assert_str(bot_2.events[0].name).is_equal(&"Welcome")


func test_a_returning_join_tries_again_until_the_lobby_takes_it() -> void:
	var runner := ScenarioRunner.play(_round_return_scenario())
	assert_array(Array(runner.failures)).is_empty()
	var bot_2 := runner.bots[1]
	assert_str(bot_2.last_refusal).contains("refuses new connections")
	assert_int(bot_2.retry_tick).is_greater(Ticks.from_seconds(5))
	assert_int(runner.game.state.players[runner.peers.peer_of(2)].number).is_equal(2)


func test_a_returning_join_refused_past_its_deadline_fails_naming_the_refusal() -> void:
	var scripts := [
		[StepReady.new(), _round(), _phase("end")],
		[StepReady.new(), _round(), StepLeave.new(), _join(0.0, 10.0)],
	]
	var scenario := _scenario(scripts)
	scenario.clock_s = 30
	scenario.forced_roles = {1: &"dissident"}
	scenario.expected_ends = [&"dissidents"]
	scenario.time_limit_s = 60.0
	var runner := ScenarioRunner.play(scenario)
	var text := "\n".join(runner.failures)
	assert_str(text).contains("bot 2")
	assert_str(text).contains("did not join by its deadline (10.0 s)")
	assert_str(text).contains("last refused: the host refuses new connections")


func test_the_loopback_bots_leave_the_lobby_and_return_with_their_number() -> void:
	var net := BotsRunner.play(_scenario(_lobby_scripts()))
	assert_array(Array(net.failures)).is_empty()
	var had := net.peers.peers_of(2)
	assert_int(had.size()).is_equal(2)
	var state := net.game.state
	assert_int(state.players[had[1]].number).is_equal(2)
	assert_str(state.players[had[1]].name).is_equal("Player2")
	assert_str(state.players[net.peers.peer_of(4)].name).is_equal("Player4")
	assert_bool(state.players.has(had[0])).is_false()
	# The earlier connection's client is kept and was checked as its own view.
	var earlier: Array = net.earlier_clients[2]
	assert_int(earlier.size()).is_equal(1)
	assert_int((earlier[0] as BotClient).view.peer).is_equal(had[0])
	assert_str(net.clients[2].return_key).is_equal(ScenarioBot.key_of(2))
	# A leak planted in the earlier connection's view is named with it.
	var view := (earlier[0] as BotClient).view
	view.events.append(WireMessage.new(&"PhaseChanged", {"phase": "round"}))
	net.failures.clear()
	net._check_after()
	assert_str("\n".join(net.failures)).contains("bot 2 (connection 1) (peer %d)" % had[0])


func test_the_loopback_bot_that_left_the_round_tries_again_until_the_lobby() -> void:
	var net := BotsRunner.play(_round_return_scenario())
	assert_array(Array(net.failures)).is_empty()
	var bot_2 := net.bots[1]
	assert_str(bot_2.last_refusal).is_not_empty()
	assert_int(net.peers.peers_of(2).size()).is_greater_equal(2)
	assert_int(net.game.state.players[net.peers.peer_of(2)].number).is_equal(2)
	assert_int(net.earlier_clients[2].size()).is_equal(1)


func test_a_decoded_return_key_is_a_leak() -> void:
	var net := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(net.failures)).is_empty()
	var keys := net._invariants.keys()
	assert_array(Array(keys)).contains([ScenarioBot.key_of(1), ScenarioBot.key_of(2)])
	var key := ScenarioBot.key_of(1)
	assert_bool(ScenarioInvariants.holds_text({"a": [{"name": "x%sy" % key}]}, keys)).is_true()
	assert_bool(ScenarioInvariants.holds_text({key: 1}, keys)).is_true()
	assert_bool(ScenarioInvariants.holds_text(PackedStringArray([key]), keys)).is_true()
	assert_bool(ScenarioInvariants.holds_text({"a": ["Player1", 7]}, keys)).is_false()
	var own := net.clients[2].view
	var peer := net.peers.peer_of(2)
	assert_array(Array(net.leaks.check_bot("bot 2", peer, own, false))).is_empty()
	var fields := own.events[0].fields.duplicate()
	fields["planted"] = key
	own.events[0] = WireMessage.new(own.events[0].name, fields)
	var at_tick: int = own.snapshots.keys().back()
	var snapshot: Dictionary = own.snapshots[at_tick].duplicate()
	snapshot["planted"] = {"name": key}
	own.snapshots[at_tick] = snapshot
	var found := "\n".join(net.leaks.check_bot("bot 2", peer, own, false))
	assert_str(found).contains("decoded Welcome holding a return key")
	assert_str(found).contains("the snapshot of tick %d holds a return key" % at_tick)


## Bot 2 leaves in the round: the host refuses connections until bot 1's ReturnToLobby, and its
## Join tries again every 0.5 s until then (P12 (t2)).
func _round_return_scenario() -> BotScenario:
	var scripts := [
		[StepReady.new(), _round(), _phase("end"), StepReturnToLobby.new(), _wait_for_joined(2)],
		[
			StepReady.new(),
			_round(),
			StepLeave.new(),
			_join(0.0, 50.0),
			_expect_joined(2, "Player2")
		],
	]
	var scenario := _scenario(scripts)
	scenario.clock_s = 5
	scenario.forced_roles = {1: &"dissident"}
	scenario.expected_ends = [&"dissidents"]
	scenario.time_limit_s = 60.0
	return scenario


## Three bots join; bot 2 leaves; bot 4 joins; bot 2 returns: the lobby part of the content
## scenario, with the same waits.
static func _lobby_scripts() -> Array:
	return [
		[_wait_for_joined(4), _expect_left(2), _wait_for_joined(2)],
		[StepLeave.new(), _join(4.0, 30.0), _expect_joined(2, "Player2")],
		[_wait_for_joined(4), _expect_left(2), _wait_for_joined(2)],
		[_join(2.0, 0.0), _expect_joined(4, "Player4")],
	]


static func _join(at_s: float, deadline_s: float) -> StepJoin:
	var step := StepJoin.new()
	step.at_s = at_s
	step.deadline_s = deadline_s
	return step


static func _wait_for_joined(bot: int) -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"PlayerJoined"
	step.fields = {"peer": bot}
	return step


static func _expect_left(bot: int) -> StepExpect:
	var step := StepExpect.new()
	step.event = &"PlayerLeft"
	step.fields = {"peer": bot}
	step.within_s = 10.0
	return step


static func _expect_joined(bot: int, player_name: String) -> StepExpect:
	var step := StepExpect.new()
	step.event = &"PlayerJoined"
	step.fields = {"peer": bot, "name": player_name}
	step.within_s = 5.0
	return step


static func _phase(phase: String) -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"PhaseChanged"
	step.fields = {"phase": phase}
	return step


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
