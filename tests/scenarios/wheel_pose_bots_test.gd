extends GdUnitTestSuite
## The wheel pose in the bots (#1509; ARCHITECTURE §7.1.22): the fixture scenario
## wheel_pose_in_the_lobby has bot 1 take a wheel pose (legs 1, arms 3), so the leak check reads
## a non-zero public `wheel_pose` instead of a constant 0. It runs through the host (BotsRunner),
## where the watching bot 2 must decode the pose on bot 1's avatar (nobody gets their own avatar,
## so bot 1's view holds none), and through the core runner.

const SCENARIO := "res://tests/fixtures/scenarios/wheel_pose_in_the_lobby.tres"


func test_the_watching_bot_decodes_the_pose_on_the_posers_avatar() -> void:
	var runner := BotsRunner.play(load(SCENARIO) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
	var expected := WheelPoseCode.encode(1, 3)
	assert_int(expected).is_not_equal(WheelPoseCode.NONE)
	var poser_peer := runner.bots[0].peer
	var view := runner.clients[runner.bots[1].number].view
	var posed := 0
	for at_tick: int in view.snapshots:
		var avatars: Dictionary = view.snapshots[at_tick].get("avatars", {})
		var avatar: Dictionary = avatars.get(poser_peer, {})
		if avatar.get("wheel_pose", 0) == expected:
			posed += 1
	(
		assert_int(posed)
		. override_failure_message("bot 2 never decoded bot 1's wheel pose %d" % expected)
		. is_greater(0)
	)


func test_the_core_runner_plays_the_scenario() -> void:
	var runner := ScenarioRunner.play(load(SCENARIO) as BotScenario)
	assert_array(Array(runner.failures)).is_empty()
