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
	scenario.clock_s = -1
	scenario.session_seed = 1
	var problems := "\n".join(scenario.problems())
	for expected: String in [
		"bots is",
		"map res://nowhere.tscn",
		"forced to role medic",
		"bot 99",
		"setting speed",
		"expected end aliens",
		"time_limit_s",
		"session_seed 1 is below",
		"clock_s -1 is outside 0 to 65535",
	]:
		assert_str(problems).contains(expected)
	scenario.scripts[0].steps.push_front(StepJoin.new())
	assert_str("\n".join(scenario.problems())).contains("bot 1 sends the setup's settings")
	scenario.expected_ends = []
	assert_str("\n".join(scenario.problems())).contains("no expected end")
	scenario.mode = null
	assert_array(Array(scenario.problems())).is_equal(["no mode"])


func test_the_bots_talk_in_spurts_by_default_or_continuously() -> void:
	# M5-1: the bots' synthetic voice (ARCHITECTURE §4.6).
	var scenario := _scenario()
	assert_int(scenario.voice).is_equal(BotScenario.Voice.SPURTS)
	scenario.voice = BotScenario.Voice.CONTINUOUS
	assert_array(Array(scenario.problems())).is_empty()
	# A value no member has, as a hand-edited .tres can hold.
	scenario.set("voice", 2)
	assert_str("\n".join(scenario.problems())).contains("voice 2 is neither SPURTS nor CONTINUOUS")
	scenario.set("voice", -1)
	assert_str("\n".join(scenario.problems())).contains("voice -1 is neither SPURTS nor CONTINUOUS")


func test_steps_and_targets_report_their_problems() -> void:
	var scenario := _scenario()
	var walk := StepWalkTo.new()
	walk.stop_m = -1.0
	var pick := StepPickUp.new()
	pick.target = ScenarioTarget.new()
	pick.target.kind = ScenarioTarget.Kind.NEAREST
	var wait := StepWait.new()
	wait.expect_rejected = &"too_soon"
	var downed_pick := StepPickUp.new()
	downed_pick.target = ScenarioTarget.new()
	downed_pick.expect_rejected = &"not_accepted"
	scenario.scripts[0].steps.append_array([walk, pick, wait, downed_pick])
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


func test_a_join_is_the_first_step_and_only_once() -> void:
	# Before its Welcome a bot runs only a Join: a Join later in the script would never run.
	var scenario := _scenario()
	scenario.settings = {}
	scenario.scripts[0].steps.append(StepJoin.new())
	assert_array(Array(scenario.problems())).is_equal(["bot 1: Join must be its first step"])
	scenario.scripts[0].steps.push_front(StepJoin.new())
	assert_array(Array(scenario.problems())).is_equal(["bot 1 has 2 Join steps; at most one"])
	scenario.scripts[0].steps.pop_back()
	assert_array(Array(scenario.problems())).is_empty()


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
		StepLeave.new(),
		StepRaise.new(),
		StepStopRaise.new(),
		StepGiveUp.new(),
		StepSwap.new(),
		StepNextStage.new(),
		StepTalk.new()
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
			&"Leave",
			&"Raise",
			&"StopRaise",
			&"GiveUp",
			&"Swap",
			&"NextStage",
			&"Talk"
		]
	)
	# The steps that send an intent, so expect_rejected applies (Join sends Hello).
	assert_bool(StepJoin.new().sends_intent()).is_true()
	assert_bool(StepUse.new().sends_intent()).is_true()
	assert_bool(StepWalkTo.new().sends_intent()).is_false()
	assert_str(StepUse.new().until).is_equal("Swung")
	for raising: ScenarioStep in [
		StepRaise.new(), StepStopRaise.new(), StepGiveUp.new(), StepSwap.new(), StepNextStage.new()
	]:
		assert_bool(raising.sends_intent()).is_true()


func test_a_raise_step_targets_a_bot() -> void:
	var raise := StepRaise.new()
	assert_array(Array(raise.problems())).is_equal(["no target"])
	raise.target = ScenarioTarget.new()
	assert_array(Array(raise.problems())).is_equal(["a Raise targets a player: bot(i)"])
	raise.target.kind = ScenarioTarget.Kind.BOT
	raise.target.bot = 3
	raise.hold_s = -1.0
	assert_array(Array(raise.problems())).is_equal(["hold_s -1.0 is outside 0 to 600"])
	raise.hold_s = 2.0
	assert_array(Array(raise.problems())).is_empty()


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
