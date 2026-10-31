extends GdUnitTestSuite
## The crouch invariant (ScenarioInvariants.crouch_problem, the crouch ADR, KE1, #790; KE10 as #991
## amended it) over snapshots of a fixture match whose state is set by hand: a crouched living
## player passes in the round and in the lobby (the crouch plays everywhere, the engineer's change
## on #989); a crouched downed player is caught. The sneak, the seated pose (#1296) and the wheel
## pose (#1485) alike.

const P1 := 1
const P2 := 2


func _avatar(game: Match, of: int) -> Dictionary:
	var avatars: Dictionary = game.snapshot_for(P1).get("avatars", {})
	return avatars.get(of, {})


func test_a_crouched_living_player_in_the_round_passes() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).crouched = true
	assert_bool(_avatar(game, P2)["crouched"] as bool).is_true()
	assert_str(ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))).is_empty()


func test_a_crouched_living_player_in_the_lobby_passes() -> void:
	# The engineer's change (#989, #991): this was caught as "a phase off the match's map" before.
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	assert_str(game.phase_id()).is_equal("lobby")
	game.state.player(P2).crouched = true
	assert_bool(_avatar(game, P2)["crouched"] as bool).is_true()
	assert_str(ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))).is_empty()


func test_a_standing_avatar_passes_anywhere() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	assert_str(ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))).is_empty()


func test_a_crouched_downed_player_is_caught() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P2).crouched = true
	var problem := ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))
	assert_str(problem).contains("not alive")


func test_a_sneaking_living_player_passes_and_a_downed_or_crouched_one_is_caught() -> void:
	# The sneak (#990): ScenarioInvariants.sneak_problem, beside the crouch's.
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).sneaking = true
	assert_bool(_avatar(game, P2)["sneaking"] as bool).is_true()
	assert_str(ScenarioInvariants.sneak_problem(game, P2, _avatar(game, P2))).is_empty()
	game.state.player(P2).crouched = true
	assert_str(ScenarioInvariants.sneak_problem(game, P2, _avatar(game, P2))).contains("crouched")
	game.state.player(P2).crouched = false
	game.state.player(P2).life = PlayerState.Life.DOWNED
	assert_str(ScenarioInvariants.sneak_problem(game, P2, _avatar(game, P2))).contains("not alive")


func test_a_posed_living_player_passes_and_a_downed_one_is_caught() -> void:
	# The seated pose (#1296): ScenarioInvariants.pose_problem, beside the sneak's.
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).posed = true
	assert_bool(_avatar(game, P2)["posed"] as bool).is_true()
	assert_str(ScenarioInvariants.pose_problem(game, P2, _avatar(game, P2))).is_empty()
	# Sitting down out of a walk: the claim twin (still moving) is accepted, then the Pose.
	game.state.player(P2).moving = true
	assert_str(ScenarioInvariants.pose_problem(game, P2, _avatar(game, P2))).is_empty()
	game.state.player(P2).life = PlayerState.Life.DOWNED
	assert_str(ScenarioInvariants.pose_problem(game, P2, _avatar(game, P2))).contains("not alive")


func test_a_wheel_pose_on_a_free_living_player_passes_and_any_other_is_caught() -> void:
	# The pose wheel (#1485): ScenarioInvariants.pose_problem, beside the seated pose's.
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	var player := game.state.player(P2)
	player.wheel_legs = 1
	player.wheel_arms = 2
	var shown := _avatar(game, P2)
	assert_int(shown["wheel_pose"] as int).is_equal(WheelPoseCode.encode(1, 2))
	assert_str(ScenarioInvariants.pose_problem(game, P2, shown)).is_empty()
	var half := shown.duplicate()
	half["wheel_pose"] = 0x02
	assert_str(ScenarioInvariants.pose_problem(game, P2, half)).contains("half wheel pose")
	var other := shown.duplicate()
	other["wheel_pose"] = WheelPoseCode.encode(0, 0)
	assert_str(ScenarioInvariants.pose_problem(game, P2, other)).contains("does not hold")
	for field: String in ["posed", "crouched", "sneaking"]:
		player.set(field, true)
		assert_str(ScenarioInvariants.pose_problem(game, P2, _avatar(game, P2))).contains(
			"standing free"
		)
		player.set(field, false)
	player.life = PlayerState.Life.DOWNED
	assert_str(ScenarioInvariants.pose_problem(game, P2, _avatar(game, P2))).contains(
		"standing free"
	)
