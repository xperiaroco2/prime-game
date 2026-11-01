extends GdUnitTestSuite
## The ship's engine end to end (#1498; ARCHITECTURE §9.5.27, §9.7; GDD §3 "The M8 slice", §10):
## the two estate scenarios on the real base mode with the slice's defaults (the real kinds, the
## 5-minute clock, one task), played by the core runner from the console's start to MatchEnded.
## In crew_mends_the_ships_engine three crew bots split the problems by MendEngine (its seed draws
## all three kinds: gills, breakers and the crystal) and fix every problem the three stages open,
## with no blast, so the crew wins by every_task_done before the timer. In
## engine_blast_gives_the_humans_the_clock the one crew bot starts the engine and stays aboard: the
## first problem runs out, its blast knocks the bot down, it respawns on the clearing, and the
## clock gives the humans (dissidents) the win by time_up. Every bot present decodes the same
## engine events (all six are public; the bots test checks them against view_of per peer).

const CREW_MENDS := "res://content/scenarios/crew_mends_the_ships_engine.tres"
const BLAST := "res://content/scenarios/engine_blast_gives_the_humans_the_clock.tres"
const ESTATE := "res://levels/estate/estate.tscn"
const ENGINE_EVENTS: Array[StringName] = [
	&"EngineProblemOpened",
	&"EngineProblemFixed",
	&"EngineBlast",
	&"GillFlipped",
	&"BreakerChain",
	&"CrystalChanged",
]


func test_both_play_the_base_mode_on_the_estate_with_its_defaults() -> void:
	for path: String in [CREW_MENDS, BLAST]:
		var scenario := load(path) as BotScenario
		assert_str(scenario.mode.resource_path).is_equal("res://content/modes/base_mode.tres")
		assert_str(scenario.played_map()).is_equal(ESTATE)
		assert_dict(scenario.settings).is_empty()
		assert_int(scenario.clock_s).is_equal(0)


func test_the_crew_mends_every_problem_kind_and_wins_by_every_task_done() -> void:
	var runner := ScenarioRunner.play(load(CREW_MENDS) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	var crew := runner.bots[1]
	var opened := _problems(crew, &"EngineProblemOpened")
	assert_array(opened).is_not_empty()
	assert_array(_problems(crew, &"EngineProblemFixed")).contains_exactly_in_any_order(opened)
	var names := _names(crew)
	assert_array(names).contains([&"ButtonPressed", &"GillFlipped", &"BreakerChain"])
	assert_array(names).contains([&"CrystalChanged"])
	assert_array(names).not_contains([&"EngineBlast"])
	assert_dict(_ended(crew)).contains_key_value("side", &"crew")
	assert_dict(_ended(crew)).contains_key_value("reason", &"every_task_done")
	_assert_same_engine_events(runner)


func test_a_problem_runs_out_and_the_clock_gives_the_humans_the_win() -> void:
	var runner := ScenarioRunner.play(load(BLAST) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	var crew := runner.bots[1]
	var names := _names(crew)
	var blast := names.find(&"EngineBlast")
	assert_int(blast).is_greater(names.find(&"ButtonPressed"))
	assert_int(names.find(&"KnockedDown", blast)).is_greater(blast)
	assert_int(names.find(&"Respawned", blast)).is_greater(blast)
	assert_array(names).not_contains([&"EngineProblemFixed"])
	assert_dict(_ended(crew)).contains_key_value("side", &"dissidents")
	assert_dict(_ended(crew)).contains_key_value("reason", &"time_up")
	_assert_same_engine_events(runner)


## Every bot decoded the same engine events, in the same order with the same fields.
func _assert_same_engine_events(runner: ScenarioRunner) -> void:
	var first := _engine_events(runner.bots[0])
	assert_array(first).is_not_empty()
	for bot: ScenarioBot in runner.bots:
		(
			assert_array(_engine_events(bot))
			. override_failure_message("bot %d's engine events differ from bot 1's" % bot.number)
			. is_equal(first)
		)


func _engine_events(bot: ScenarioBot) -> Array:
	var found := []
	for event: WireMessage in bot.events:
		if event.name in ENGINE_EVENTS:
			found.append([event.name, event.fields])
	return found


func _problems(bot: ScenarioBot, event_name: StringName) -> Array:
	var found := []
	for event: WireMessage in bot.events:
		if event.name == event_name:
			found.append(event.fields["problem"])
	return found


func _names(bot: ScenarioBot) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: WireMessage in bot.events:
		found.append(event.name)
	return found


func _ended(bot: ScenarioBot) -> Dictionary:
	for event: WireMessage in bot.events:
		if event.name == &"MatchEnded":
			return event.fields
	return {}
