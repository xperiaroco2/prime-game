extends GdUnitTestSuite
## BotScenario and its steps and targets (ARCHITECTURE §9.7): data only; problems() says what
## makes a scenario unplayable before a runner starts it. A mode built in code (§9.6).


func test_a_complete_scenario_has_no_problems() -> void:
	var scenario := _scenario()
	assert_array(Array(scenario.problems())).is_empty()
	assert_int(scenario.steps_of(1).size()).is_equal(2)
	assert_array(scenario.steps_of(2)).is_empty()
	assert_array(scenario.steps_of(0)).is_empty()


func test_the_setup_is_checked_against_the_mode() -> void:
	var scenario := _scenario()
	scenario.bots = FixtureBaseMode.MAX_PLAYERS + 1
	scenario.map = "res://nowhere.tscn"
	scenario.forced_roles = {1: &"medic", 99: &"crew"}
	scenario.settings = {&"speed": 3}
	scenario.expected_ends = [&"aliens"]
	scenario.time_limit_s = 0.0
	var problems := "\n".join(scenario.problems())
	for expected: String in [
		"bots is",
		"map res://nowhere.tscn",
		"forced to role medic",
		"bot 99",
		"setting speed",
		"expected end aliens",
		"time_limit_s"
	]:
		assert_str(problems).contains(expected)
	scenario.expected_ends = []
	assert_str("\n".join(scenario.problems())).contains("no expected end")
	scenario.mode = null
	assert_array(Array(scenario.problems())).is_equal(["no mode"])


func test_steps_and_targets_report_their_problems() -> void:
	var scenario := _scenario()
	var walk := StepWalkTo.new()
	walk.stop_m = -1.0
	var pick := StepPickUp.new()
	pick.target = ScenarioTarget.new()
	pick.target.kind = ScenarioTarget.Kind.NEAREST
	var wait := StepWait.new()
	wait.expect_rejected = &"too_soon"
	var ghost_pick := StepPickUp.new()
	ghost_pick.target = ScenarioTarget.new()
	ghost_pick.expect_rejected = &"not_accepted"
	scenario.scripts[0].steps.append_array([walk, pick, wait, ghost_pick])
	var problems := scenario.problems()
	(
		assert_array(Array(problems))
		. is_equal(
			[
				"bot 1, WalkTo: no target",
				"bot 1, WalkTo: stop_m is negative",
				"bot 1, PickUp: nearest names no item kind",
				"bot 1, Wait: expect_rejected on a step that sends no intent",
			]
		)
	)


func test_every_step_names_itself_as_in_section_9_7() -> void:
	var names: Array[StringName] = []
	for step: ScenarioStep in [
		StepJoin.new(),
		StepLoadAck.new(),
		StepReady.new(),
		StepSetting.new(),
		StepReturnToLobby.new(),
		StepWaitFor.new(),
		StepWait.new(),
		StepWalkTo.new(),
		StepPickUp.new(),
		StepPutDown.new(),
		StepUse.new(),
		StepJump.new(),
		StepExpect.new(),
		StepExpectNone.new(),
		StepLeave.new()
	]:
		names.append(step.step_name())
	assert_array(names).is_equal(
		[
			&"Join",
			&"LoadAck",
			&"Ready",
			&"Setting",
			&"ReturnToLobby",
			&"WaitFor",
			&"Wait",
			&"WalkTo",
			&"PickUp",
			&"PutDown",
			&"Use",
			&"Jump",
			&"Expect",
			&"ExpectNone",
			&"Leave"
		]
	)
	# The steps that send an intent, so expect_rejected applies (Join sends Hello).
	assert_bool(StepJoin.new().sends_intent()).is_true()
	assert_bool(StepUse.new().sends_intent()).is_true()
	assert_bool(StepWalkTo.new().sends_intent()).is_false()
	assert_str(StepUse.new().until).is_equal("Swung")


func _scenario() -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = FixtureBaseMode.mode()
	var crew := GameRole.new()
	crew.id = &"crew"
	scenario.mode.roles = [crew]
	scenario.bots = 2
	scenario.forced_roles = {2: &"crew"}
	scenario.expected_ends = [BotScenario.NONE]
	var script := BotScript.new()
	var ready := StepReady.new()
	var walk := StepWalkTo.new()
	walk.target = ScenarioTarget.new()
	walk.target.point = Vector3(1, 0, 1)
	script.steps = [ready, walk]
	scenario.scripts = [script]
	return scenario
