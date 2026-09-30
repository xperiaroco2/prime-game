extends GdUnitTestSuite
## Every bot scenario in content/scenarios/ (ARCHITECTURE §9.7), played by the core runner
## (tests/harness/, stage 2j) on the mode's real levels: each reaches its expected ends with every
## step done, no bot corrected outside a placement, no match error, the §5 invariants on every
## bot's stream, and each bot holding exactly its peer's view_of. Then the match is replayed from
## its command log (§3.3), which must give the same events to the same recipients. One of the two
## places that load content/ (§9.6), so a change there can break a scenario.

const SCENARIOS_DIR := "res://content/scenarios/"


func test_every_scenario_plays_to_its_expected_ends_and_replays() -> void:
	var paths := _scenario_paths()
	assert_array(paths).is_not_empty()
	for path: String in paths:
		var scenario := load(path) as BotScenario
		(
			assert_object(scenario)
			. override_failure_message("%s is not a BotScenario" % path)
			. is_not_null()
		)
		if scenario == null:
			continue
		var runner := ScenarioRunner.play(scenario)
		(
			assert_array(Array(runner.failures))
			. override_failure_message("%s:\n%s" % [path, "\n".join(runner.failures)])
			. is_empty()
		)
		if runner.game == null or not runner.failures.is_empty():
			continue
		_assert_replays(path, runner.game)


## The match replayed from its command log gives the same events, in order, to the same peers.
func _assert_replays(path: String, game: Match) -> void:
	var replayed := Match.replay(game.command_log, game.mode)
	assert_array(Array(replayed.refusals)).override_failure_message(path).is_empty()
	var errors: Array[String] = []
	for line: String in replayed.diagnostics:
		if line.begins_with("error:"):
			errors.append(line)
	assert_array(errors).override_failure_message(path).is_empty()
	var recorded := game.emitted()
	var again := replayed.emitted()
	assert_int(again.size()).override_failure_message(path).is_equal(recorded.size())
	for i in mini(recorded.size(), again.size()):
		var want := recorded[i]
		var got := again[i]
		var same := (
			got.event.describe() == want.event.describe()
			and got.recipients == want.recipients
			and got.tick == want.tick
		)
		if not same:
			fail(
				(
					"%s: event %d differs in the replay: %s to %s, recorded %s to %s"
					% [
						path,
						i,
						got.event.describe(),
						got.recipients,
						want.event.describe(),
						want.recipients
					]
				)
			)
			return


func _scenario_paths() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(SCENARIOS_DIR)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			found.append(SCENARIOS_DIR.path_join(file))
	found.sort()
	return found
