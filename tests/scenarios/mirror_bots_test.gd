extends GdUnitTestSuite
## The mirror in the bots (#1394; ARCHITECTURE §7.1.24, §9.7): the fixture scenario
## mirror_two_colours through the host (BotsRunner, with its leak check) and
## the core runner: a colour asked away from the mirror is refused, two bots at two places change
## their colours in turn and each sees the other's.

const SCENARIO := "res://tests/fixtures/scenarios/mirror_two_colours.tres"


func test_two_bots_change_colours_at_the_mirror_through_the_host() -> void:
	var runner := BotsRunner.play(load(SCENARIO) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	_assert_colours(runner.game)


func test_the_core_runner_plays_the_same() -> void:
	var runner := ScenarioRunner.play(load(SCENARIO) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	_assert_colours(runner.game)


func _assert_colours(game: Match) -> void:
	var colours: Array[int] = []
	for peer: int in game.state.present_peers():
		colours.append(game.state.players[peer].colour)
	colours.sort()
	assert_array(colours).is_equal([7, 8])
