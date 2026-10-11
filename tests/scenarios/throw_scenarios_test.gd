extends GdUnitTestSuite
## A throw end to end (#644, 37d; #646, 37f; ARCHITECTURE §7.1.16, §9.7): a bot picks up a package
## and throws it with the base mode's Throw rule, the other bot sees the flight and its end, on the
## core runner and through the network, where the leak check compares each ItemThrown a client
## decoded with the host's view exactly; a throw with an empty hand is refused as empty_hand.

const BASE_MODE := "res://content/modes/base_mode.tres"
const OUT := "user://throw_scenarios_test"


func after_test() -> void:
	if not DirAccess.dir_exists_absolute(OUT):
		return
	for file: String in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT.path_join(file))
	DirAccess.remove_absolute(OUT)


func test_the_base_mode_round_accepts_throw_from_the_living() -> void:
	var mode := _base_mode()
	var round_spec := mode.find_phase(&"round")
	assert_int(round_spec.senders_of(Intents.THROW)).is_equal(AcceptSpec.From.LIVING)


func test_a_bot_throws_a_package_and_the_other_sees_its_flight_on_the_core_runner() -> void:
	var runner := ScenarioRunner.play(_throw_scenario(_base_mode()))
	assert_array(Array(runner.failures)).is_empty()
	_assert_thrown_then_rested(runner.bots)


func test_a_bot_throws_a_package_through_the_network_and_nothing_leaks() -> void:
	var runner := BotsRunner.play(_throw_scenario(_base_mode()), OUT)
	# The leak check is part of the failures: every ItemThrown a client decoded equals the host's.
	assert_array(Array(runner.failures)).is_empty()
	_assert_thrown_then_rested(runner.bots)
	for bot: ScenarioBot in runner.bots:
		var view := runner.clients[bot.number].view
		assert_array(view.event_names()).contains([&"ItemThrown"])
		_assert_model_rested(runner.clients[bot.number].model, bot, runner.bots[0])


func test_the_base_mode_refuses_a_throw_with_an_empty_hand() -> void:
	var scenario := _throw_scenario(_base_mode())
	var thrower := scenario.scripts[0]
	var throw := thrower.steps[4] as StepThrow
	throw.expect_rejected = HoldsItem.EMPTY_HAND
	# No package held, so no circle of it: a point ahead.
	var ahead := ScenarioTarget.new()
	ahead.point = Vector3(0, 0, 20)
	throw.towards = ahead
	# No pick-up first (and no walk to the package): nothing flies, nothing rests.
	var steps: Array[ScenarioStep] = [thrower.steps[0], thrower.steps[1], throw]
	thrower.steps = steps
	scenario.scripts[1].steps.resize(2)
	var runner := ScenarioRunner.play(scenario)
	assert_array(Array(runner.failures)).is_empty()
	assert_int(runner.bots[0].held).is_equal(-1)


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


## Bot 1 walks to its first package, picks it up and throws it towards the package's circle,
## 30 degrees up; it is done when the flight ends. Bot 2 waits for the throw and its end.
func _throw_scenario(mode: GameMode) -> BotScenario:
	var package := ScenarioTarget.new()
	package.kind = ScenarioTarget.Kind.PACKAGE
	package.index = 1
	var walk := StepWalkTo.new()
	walk.target = package
	walk.sprint = true
	walk.stop_m = 1.0
	var pick := StepPickUp.new()
	pick.target = package
	var circle := ScenarioTarget.new()
	circle.kind = ScenarioTarget.Kind.CIRCLE_OF_HELD
	var throw := StepThrow.new()
	throw.towards = circle
	throw.pitch_deg = 30.0
	var thrower: Array = [StepReady.new(), _round(), walk, pick, throw, _rested()]
	var seen := StepWaitFor.new()
	seen.event = &"ItemThrown"
	seen.fields = {"peer": 1}
	var watcher: Array = [StepReady.new(), _round(), seen, _rested()]
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.bots = 2
	scenario.session_seed = 490_000_000_037
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 40.0
	var made: Array[BotScript] = []
	for steps: Array in [thrower, watcher]:
		var script := BotScript.new()
		for step: ScenarioStep in steps:
			script.steps.append(step)
		made.append(script)
	scenario.scripts = made
	return scenario


## The ClientModel a bot's real session built from the decoded events: the thrown item is no
## longer in flight, nobody holds it, and its launch is what the ItemThrown carried.
func _assert_model_rested(model: ClientModel, bot: ScenarioBot, thrower: ScenarioBot) -> void:
	var thrown := bot.find_since(
		0, func(event: WireMessage) -> bool: return event.name == &"ItemThrown"
	)
	var item := thrown.fields["item"] as int
	var folded: ClientModel.Item = model.items[item]
	assert_bool(folded.flying).is_false()
	assert_int(folded.thrower).is_equal(thrower.peer)
	assert_int(folded.flight_tick).is_equal(thrown.fields["tick"] as int)
	assert_int(model.hand_item(thrower.peer)).is_equal(-1)


## Each bot saw the ItemThrown of bot 1's package and then its ItemPlaced (cause thrown), and
## folded it back onto the ground where that ItemPlaced says.
func _assert_thrown_then_rested(bots: Array[ScenarioBot]) -> void:
	var thrower := bots[0]
	for bot: ScenarioBot in bots:
		var thrown := bot.find_since(
			0, func(event: WireMessage) -> bool: return event.name == &"ItemThrown"
		)
		assert_object(thrown).is_not_null()
		var item := thrown.fields["item"] as int
		assert_int(thrown.fields["peer"] as int).is_equal(thrower.peer)
		var placed := bot.find_since(
			0,
			func(event: WireMessage) -> bool:
				return (
					event.name == &"ItemPlaced"
					and event.fields["item"] == item
					and str(event.fields["cause"]) == String(Items.THROWN)
				)
		)
		assert_object(placed).is_not_null()
		assert_int(bot.items[item]["where"]).is_not_equal(ScenarioBot.Where.FLYING)
	assert_int(thrower.held).is_equal(-1)


func _round() -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"PhaseChanged"
	step.fields = {"phase": "round"}
	return step


func _rested() -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"ItemPlaced"
	step.fields = {"cause": String(Items.THROWN)}
	return step
