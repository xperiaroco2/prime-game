extends GdUnitTestSuite
## TakeWheelPose and the WheelPose intent (#1485; GDD §8 "Photo", "The pose wheel"): a living
## player's pick of one leg stance and one arm gesture sets its wheel pose, which every other peer's
## snapshot shows on its avatar (WheelPoseCode's byte); a half or out-of-range pick is refused
## `no_such_pose`; the seated, the crouched and the sneaking are refused `not_allowed`, a two-handed
## hand item `two_handed`; the dead, the downed, the limp and the End are not accepted. Standing
## still and turning keep it, a push keeps it; any own move, a crouch or a sneak, the chair, a
## placement, a knockdown, the limp, a death, a respawn and a reset end it. The rule is
## FixtureMoves.wheeling()'s (the base mode's own is pinned in tests/unit/content/).

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const LEGS := 2
const ARMS := 3


func test_a_pick_sets_the_pose_and_every_other_peer_sees_it() -> void:
	var game := _wheel_round([P1, P2, P3])
	FixtureModes.run_ticks(game, 1)
	assert_int(_shown(game, P2, P1)).is_equal(WheelPoseCode.NONE)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	var player := game.state.player(P1)
	assert_int(player.wheel_legs).is_equal(LEGS)
	assert_int(player.wheel_arms).is_equal(ARMS)
	var code := WheelPoseCode.encode(LEGS, ARMS)
	assert_int(_shown(game, P2, P1)).is_equal(code)
	assert_int(_shown(game, P3, P1)).is_equal(code)
	var recorded: Dictionary = game.view_of(P2).snapshots[game.ticked_through()]["avatars"][P1]
	assert_int(recorded["wheel_pose"]).is_equal(code)
	# The poser gets no avatar of its own (Snapshots), and nobody else is posed.
	assert_dict(game.snapshot_for(P1)["avatars"]).not_contains_keys([P1])
	assert_int(_shown(game, P1, P2)).is_equal(WheelPoseCode.NONE)
	assert_bool(player.posed).is_false()
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_a_new_pick_replaces_the_pose() -> void:
	var game := _wheel_round([P1, P2])
	FixtureMoves.wheel_pose(game, P1, 0, 0)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.wheel_pose(game, P1, FixtureMoves.LEGS - 1, FixtureMoves.ARMS - 1)
	FixtureModes.run_ticks(game, 1)
	var code := WheelPoseCode.encode(FixtureMoves.LEGS - 1, FixtureMoves.ARMS - 1)
	assert_int(_shown(game, P2, P1)).is_equal(code)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_a_half_or_out_of_range_pick_is_refused() -> void:
	var game := _wheel_round([P1, P2])
	var picks: Array[Dictionary] = [
		{"legs": LEGS},
		{"arms": ARMS},
		{"legs": FixtureMoves.LEGS, "arms": ARMS},
		{"legs": LEGS, "arms": FixtureMoves.ARMS},
		{"legs": -1, "arms": ARMS},
		{"legs": LEGS, "arms": 255},
		{"legs": 255, "arms": 255},
	]
	for pick: Dictionary in picks:
		FixtureModes.send(game, Intents.WHEEL_POSE, P1, pick)
		FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	var expected: Array[StringName] = []
	for pick: Dictionary in picks:
		expected.append(WheelPoseInRange.NO_SUCH_POSE)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(expected)


func test_the_lobby_takes_a_pick_and_the_end_does_not() -> void:
	var game := FixtureModes.started(FixtureMoves.wheeling(FixtureModes.basic()), [P1, P2])
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(_shown(game, P2, P1)).is_equal(WheelPoseCode.encode(LEGS, ARMS))
	var ended := _wheel_round([P1, P2])
	ended.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(ended, 1)
	assert_str(ended.phase_id()).is_equal("end")
	FixtureMoves.wheel_pose(ended, P1, LEGS, ARMS)
	FixtureModes.run_ticks(ended, 1)
	assert_int(ended.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	assert_array(FixtureModes.rejections(ended, P1)).is_equal([&"not_accepted"])


func test_the_dead_and_the_limp_are_not_accepted() -> void:
	var game := _wheel_round([P1, P2, P3])
	LifeRules.kill(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	LifeRules.go_limp(FixtureMoves.context(game), P2, 5.0)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P2).is_limp()).is_true()
	for peer: int in [P1, P2]:
		FixtureMoves.wheel_pose(game, peer, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	for peer: int in [P1, P2]:
		assert_int(game.state.player(peer).wheel_pose_code()).is_equal(WheelPoseCode.NONE)
		assert_array(FixtureModes.rejections(game, peer)).is_equal([&"not_accepted"])


func test_the_downed_are_not_accepted_and_the_knockdown_ends_the_pose() -> void:
	var game := _wheel_round([P1, P2, P3])
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	LifeRules.knock_down(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	var downed := game.state.player(P1)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_int(downed.wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	assert_int(_shown(game, P2, P1)).is_equal(WheelPoseCode.NONE)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])


func test_the_seated_crouched_and_sneaking_are_not_allowed() -> void:
	var game := _wheel_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	FixtureMoves.step(game, P2, Vector3.ZERO, {"crouched": true})
	FixtureMoves.wheel_pose(game, P2, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P2, Vector3.ZERO, {"sneaking": true})
	assert_bool(game.state.player(P2).sneaking).is_true()
	FixtureMoves.wheel_pose(game, P2, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P2).wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_allowed"])
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_allowed", &"not_allowed"])


func test_a_two_handed_hand_item_refuses_and_a_one_handed_does_not() -> void:
	var game := _wheel_round([P1, P2])
	var package := FixtureItemModes.lay(game, &"package", game.state.player(P1).position + NORTH)
	var tool := FixtureItemModes.lay(game, &"tool", game.state.player(P2).position + NORTH)
	FixtureItemModes.pick_up(game, P1, package)
	FixtureItemModes.pick_up(game, P2, tool)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).held_item).is_equal(package.id)
	assert_int(game.state.player(P2).held_item).is_equal(tool.id)
	for peer: int in [P1, P2]:
		FixtureMoves.wheel_pose(game, peer, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([HandNotTwoHanded.TWO_HANDED])
	assert_int(game.state.player(P2).wheel_pose_code()).is_equal(WheelPoseCode.encode(LEGS, ARMS))


func test_picking_up_a_two_handed_item_later_keeps_the_pose() -> void:
	# The carry layer and the arms layer meet on the client (the issue's recommendation).
	var game := _wheel_round([P1, P2])
	var package := FixtureItemModes.lay(game, &"package", game.state.player(P1).position + NORTH)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.pick_up(game, P1, package)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).held_item).is_equal(package.id)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.encode(LEGS, ARMS))


func test_a_still_claim_that_turns_keeps_the_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": EAST})
	assert_vector(game.state.player(P1).facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	assert_int(_shown(game, P2, P1)).is_equal(WheelPoseCode.encode(LEGS, ARMS))


func test_a_displacement_without_input_keeps_the_pose() -> void:
	# A push by another player: only the poser's own move ends the pose.
	var game := _wheel_round([P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, EAST)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, NORTH * 0.1)
	assert_vector(game.state.player(P1).position).is_equal_approx(NORTH * 0.1, Vector3.ONE * 1e-4)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.encode(LEGS, ARMS))


func test_a_moving_claim_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, EAST * 0.1, {"moving": true})
	_assert_ended(game)


func test_a_refused_moving_claim_ends_the_pose_too() -> void:
	var game := _posed_round([P1, P2])
	var epoch := game.state.player(P1).epoch
	FixtureMoves.step(game, P1, EAST * 5.0, {"moving": true})
	assert_int(game.state.player(P1).epoch).is_equal(epoch + 1)
	_assert_ended(game)


func test_a_new_jump_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3(0, 0.1, 0), FixtureMoves.jumped(game, P1))
	_assert_ended(game)


func test_a_moved_tick_of_a_merged_claim_ends_the_pose() -> void:
	var game := _wheel_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 2)
	var player := game.state.player(P1)
	FixtureMoves.claim(
		game, P1, player.position, {"client_tick": player.claim_tick + 2, "moved_ticks": 0b10}
	)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	_assert_ended(game)


func test_travel_without_input_and_without_a_pusher_ends_the_pose() -> void:
	var game := _wheel_round([P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(10, 0, 10))
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, NORTH * 0.1, {"moved_ticks": 0})
	assert_vector(game.state.player(P1).position).is_equal_approx(NORTH * 0.1, Vector3.ONE * 1e-4)
	_assert_ended(game)


func test_a_crouched_claim_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO, {"crouched": true})
	assert_bool(game.state.player(P1).crouched).is_true()
	_assert_ended(game)


func test_a_sneaking_claim_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO, {"sneaking": true})
	assert_bool(game.state.player(P1).sneaking).is_true()
	_assert_ended(game)


func test_the_chair_ends_the_pose() -> void:
	# The chair and the wheel exclude each other: sitting down clears the wheel pose.
	var game := _posed_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	assert_bool(game.snapshot_for(P2)["avatars"][P1]["posed"]).is_true()
	_assert_ended(game)


func test_the_limp_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	LifeRules.go_limp(FixtureMoves.context(game), P1, 5.0)
	FixtureModes.run_ticks(game, 1)
	_assert_ended(game)


func test_a_death_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	LifeRules.kill(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DEAD)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.NONE)


func test_a_respawn_ends_the_pose() -> void:
	var game := _wheel_round([P1, P2])
	LifeRules.kill(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	# Set by hand on the dead, so only the respawn can be seen clearing it.
	game.state.player(P1).wheel_legs = LEGS
	game.state.player(P1).wheel_arms = ARMS
	LifeRules.respawn(FixtureMoves.context(game), P1, Vector3.ZERO)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.ALIVE)
	_assert_ended(game)


func test_the_rounds_placement_ends_the_pose() -> void:
	var game := FixtureModes.started(FixtureMoves.wheeling(FixtureModes.basic()), [P1, P2])
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.encode(LEGS, ARMS))
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.NONE)


func test_a_reset_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	var player := game.state.player(P1)
	MatchState.reset_player(player, game.state.player_rules)
	assert_int(player.wheel_legs).is_equal(-1)
	assert_int(player.wheel_arms).is_equal(-1)


func test_the_return_to_the_lobby_ends_the_pose() -> void:
	var game := _posed_round([P1, P2])
	game.state.reset_match()
	var player := game.state.player(P1)
	assert_int(player.wheel_legs).is_equal(-1)
	assert_int(player.wheel_arms).is_equal(-1)
	assert_int(player.wheel_pose_code()).is_equal(WheelPoseCode.NONE)
	assert_int(_shown(game, P2, P1)).is_equal(WheelPoseCode.NONE)


func test_take_wheel_pose_emits_nothing_and_requires_the_range() -> void:
	assert_array(TakeWheelPose.new().emits()).is_empty()
	assert_array(TakeWheelPose.new().required_conditions()).is_equal([WheelPoseInRange])
	assert_bool(Intents.PLAYER_ACTIONS.has(Intents.WHEEL_POSE)).is_true()


## A round of the wheeling and posing fixture (FixtureItemModes.basic(): a package and a tool) with
## a seat beside every player's placement spot.
func _wheel_round(peers: Array[int]) -> Match:
	var mode := FixtureMoves.wheeling(FixtureMoves.posing(FixtureItemModes.basic()))
	var game := FixtureItemModes.in_round(mode, peers, FixtureTerrainWorld.new())
	for peer: int in peers:
		FixtureMoves.seat(game, peer)
	return game


## _wheel_round with P1 in the pose (LEGS, ARMS).
func _posed_round(peers: Array[int]) -> Match:
	var game := _wheel_round(peers)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).wheel_pose_code()).is_equal(WheelPoseCode.encode(LEGS, ARMS))
	return game


## P1's wheel pose ended: its state and P2's view.
func _assert_ended(game: Match) -> void:
	assert_int(game.state.player(P1).wheel_legs).is_equal(-1)
	assert_int(game.state.player(P1).wheel_arms).is_equal(-1)
	var avatars: Dictionary = game.snapshot_for(P2).get("avatars", {})
	assert_bool(avatars.has(P1)).is_true()
	assert_int((avatars[P1] as Dictionary)["wheel_pose"]).is_equal(WheelPoseCode.NONE)


## `peer`'s wheel pose byte in `viewer`'s newest snapshot.
func _shown(game: Match, viewer: int, peer: int) -> int:
	var avatars: Dictionary = game.snapshot_for(viewer).get("avatars", {})
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("wheel_pose", WheelPoseCode.NONE)
