extends GdUnitTestSuite
## Every bot scenario in content/scenarios/ and tests/fixtures/scenarios/ (those on a fixture mode,
## #1497; ScenarioLevels.SCENARIOS_DIRS; ARCHITECTURE §9.7), played by the core runner
## (tests/harness/, stage 2j) on the mode's real levels: each reaches its expected ends with every
## step done, no bot corrected outside a placement, no match error, the §5 invariants on every
## bot's stream, and each bot holding exactly its peer's view_of. Then the match is replayed from
## its command log (§3.3), which must give the same events to the same recipients. One of the two
## places that load content/ (§9.6), so a change there can break a scenario.

const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")


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


## Every event a `never`, Expect, ExpectNone or WaitFor names is one a bot receives, with fields it
## has (#1235: a misspelled one never matches and would pass forever). ScenarioRunner checks it
## too; this names the scenario without playing it.
func test_every_scenario_names_events_and_fields_a_bot_receives() -> void:
	var events := ScenarioBot.receivable_events()
	for path: String in _scenario_paths():
		var scenario := load(path) as BotScenario
		if scenario == null:
			continue
		(
			assert_array(Array(scenario.problems(events)))
			. override_failure_message("%s:\n%s" % [path, "\n".join(scenario.problems(events))])
			. is_empty()
		)


## A scenario is named by its file name alone (`bots <name>`, ScenarioLevels.scenario_path), so no
## name is in both folders (#1497), and the fixture folder's scenarios play a fixture mode, never a
## shipped one (those belong in content/scenarios/).
func test_each_scenario_name_is_in_one_folder_and_the_fixture_ones_play_a_fixture_mode() -> void:
	var names: Array[String] = []
	var fixtures := 0
	for path: String in _scenario_paths():
		var file := path.get_file()
		assert_bool(names.has(file)).override_failure_message(file).is_false()
		names.append(file)
		if not path.begins_with(ScenarioLevels.SCENARIOS_DIRS[1]):
			continue
		fixtures += 1
		var scenario := load(path) as BotScenario
		assert_object(scenario).override_failure_message(path).is_not_null()
		assert_str(scenario.mode.resource_path).override_failure_message(path).starts_with(
			"res://tests/fixtures/"
		)
	assert_int(fixtures).is_greater(0)


## The catalogue is the wire schema's event rows with their payload's fields, plus `peer` on the
## events for one peer that name none (field_of).
func test_the_receivable_events_are_the_wire_events_and_their_fields() -> void:
	var events := ScenarioBot.receivable_events()
	assert_array(Array(events[&"Died"])).contains_exactly_in_any_order(["peer", "position"])
	assert_array(Array(events[&"SelfStatus"])).contains(["peer", "sprint_available"])
	assert_array(Array(events[&"PhaseChanged"])).contains(["phase"])
	assert_bool(events.has(&"Disconnecting")).is_true()
	assert_bool(Array(events[&"Disconnecting"]).has("peer")).is_false()
	assert_bool(events.has(&"MoveClaim")).is_false()
	assert_bool(events.has(&"Hello")).is_false()


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
	for path: String in ScenarioLevels.scenario_paths():
		found.append(path)
	return found
