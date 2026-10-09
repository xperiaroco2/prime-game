extends GdUnitTestSuite
## The bot scenarios' NextStage step (ARCHITECTURE §9.7; #599) in the core scenario runner, on the
## base mode and its real levels: refused there (`not_accepted`, which expect_rejected expects),
## and done on the PhaseChanged it causes in a copy of the base mode whose round accepts it from
## the host with the tutorial's rule (ReportOutcome(next)) and a `round, next -> end` row.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_base_mode_refuses_next_stage() -> void:
	var step := StepNextStage.new()
	step.expect_rejected = &"not_accepted"
	var runner := ScenarioRunner.play(
		_scenario(_base(), [StepReady.new(), _wait_for("round"), step])
	)
	assert_array(Array(runner.failures)).is_empty()
	var unexpected := StepNextStage.new()
	runner = ScenarioRunner.play(
		_scenario(_base(), [StepReady.new(), _wait_for("round"), unexpected])
	)
	assert_str("\n".join(runner.failures)).contains("step 3 (NextStage)").contains(
		"Rejected (not_accepted)"
	)


func test_a_staged_mode_moves_on_and_the_step_is_done() -> void:
	# The step is done on the PhaseChanged its NextStage causes; an Expect after it names the phase.
	var ended := StepExpect.new()
	ended.event = &"PhaseChanged"
	ended.fields = {"phase": "end"}
	var steps: Array = [StepReady.new(), _wait_for("round"), StepNextStage.new(), ended]
	var runner := ScenarioRunner.play(_scenario(_staged(), steps))
	assert_array(Array(runner.failures)).is_empty()
	assert_str(runner.game.phase_id()).is_equal("end")


func _base() -> GameMode:
	return load(BASE_MODE) as GameMode


## A shallow copy of the base mode whose round also accepts NextStage from the host: the shared,
## loaded resources stay as they are (new arrays, a copy of the round's spec).
func _staged() -> GameMode:
	var mode := _base().duplicate() as GameMode
	var phases: Array[PhaseSpec] = []
	for spec: PhaseSpec in mode.phases:
		if spec.id != &"round":
			phases.append(spec)
			continue
		var round_spec := spec.duplicate() as PhaseSpec
		var accepts: Array[AcceptSpec] = []
		accepts.assign(spec.accepts)
		accepts.append(AcceptSpec.of(Intents.NEXT_STAGE, AcceptSpec.From.HOST))
		round_spec.accepts = accepts
		phases.append(round_spec)
	mode.phases = phases
	var report := ReportOutcome.new()
	report.outcome = &"next"
	var rule := Rule.new()
	rule.trigger = Intents.NEXT_STAGE
	rule.effects = [report]
	var actions: Array[Rule] = []
	actions.assign(mode.actions)
	actions.append(rule)
	mode.actions = actions
	var row := Transition.new()
	row.from = &"round"
	row.outcome = &"next"
	row.to = &"end"
	var rows: Array[Transition] = []
	rows.assign(mode.transitions)
	rows.append(row)
	mode.transitions = rows
	return mode


func _wait_for(phase: String) -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"PhaseChanged"
	step.fields = {"phase": phase}
	return step


func _scenario(mode: GameMode, steps: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.bots = 1
	scenario.session_seed = 599_000_000_001
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 20.0
	var script := BotScript.new()
	for step: ScenarioStep in steps:
		script.steps.append(step)
	var scripts: Array[BotScript] = [script]
	scenario.scripts = scripts
	return scenario
