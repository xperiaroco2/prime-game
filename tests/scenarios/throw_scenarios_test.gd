extends GdUnitTestSuite
## A throw end to end (#644, 37d; ARCHITECTURE §7.1.16, §9.7): a bot picks up a package and throws
## it, the other bot sees the flight and its end, on the core runner and through the network, where
## the leak check compares each ItemThrown a client decoded with the host's view exactly. The base
## mode accepts Throw in no phase until 37f (#646), so the throw runs on a copy of it with the
## fixture's Throw rule (FixtureThrowModes: a test's numbers, not a decision); the unchanged base
## mode refuses it as not_accepted.

const BASE_MODE := "res://content/modes/base_mode.tres"
const OUT := "user://throw_scenarios_test"

## Held for the whole suite, so load() hands every test this cached object, as it does to a run's
## other suites while anything holds it: a change to it would outlive the test.
var _base: GameMode


func before() -> void:
	_base = load(BASE_MODE) as GameMode


func after_test() -> void:
	# The copy never reaches the cached base mode.
	assert_object(load(BASE_MODE)).is_same(_base)
	var round_spec := _base.find_phase(&"round")
	for accepted: AcceptSpec in round_spec.accepts:
		assert_str(String(accepted.intent)).is_not_equal(String(Intents.THROW))
	for system: TickSystem in round_spec.tick_systems:
		assert_bool(system is FlightTicks).is_false()
	for rule: Rule in _base.actions:
		assert_str(String(rule.trigger)).is_not_equal(String(Intents.THROW))
	if not DirAccess.dir_exists_absolute(OUT):
		return
	for file: String in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT.path_join(file))
	DirAccess.remove_absolute(OUT)


func test_the_mode_copy_with_a_throw_rule_passes_the_mode_check() -> void:
	var mode := _throwing_mode()
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	assert_bool(mode.find_phase(&"round").accepts.any(_is_throw)).is_true()


func test_a_bot_throws_a_package_and_the_other_sees_its_flight_on_the_core_runner() -> void:
	var runner := ScenarioRunner.play(_throw_scenario(_throwing_mode()))
	assert_array(Array(runner.failures)).is_empty()
	_assert_thrown_then_rested(runner.bots)


func test_a_bot_throws_a_package_through_the_network_and_nothing_leaks() -> void:
	var runner := BotsRunner.play(_throw_scenario(_throwing_mode()), OUT)
	# The leak check is part of the failures: every ItemThrown a client decoded equals the host's.
	assert_array(Array(runner.failures)).is_empty()
	_assert_thrown_then_rested(runner.bots)
	for bot: ScenarioBot in runner.bots:
		var view := runner.clients[bot.number].view
		assert_array(view.event_names()).contains([&"ItemThrown"])
		_assert_model_rested(runner.clients[bot.number].model, bot, runner.bots[0])


func test_the_base_mode_refuses_a_throw_as_not_accepted() -> void:
	var scenario := _throw_scenario(load(BASE_MODE) as GameMode)
	var thrower := scenario.scripts[0]
	var throw := thrower.steps[4] as StepThrow
	throw.expect_rejected = RejectReasons.NOT_ACCEPTED
	# It still holds the package: nothing flies, nothing rests.
	thrower.steps.resize(5)
	scenario.scripts[1].steps.resize(2)
	var runner := ScenarioRunner.play(scenario)
	assert_array(Array(runner.failures)).is_empty()
	assert_int(runner.bots[0].held).is_greater_equal(0)


## The base mode deep-copied (its phases are internal subresources, so the copy has its own
## PhaseSpecs and arrays) with the fixture's Throw rule, Round accepting Throw and FlightTicks.
func _throwing_mode() -> GameMode:
	var base := load(BASE_MODE) as GameMode
	var copy := base.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL) as GameMode
	return FixtureThrowModes.with_throw(copy)


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


func _is_throw(accepted: AcceptSpec) -> bool:
	return accepted.intent == Intents.THROW
