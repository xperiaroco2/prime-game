extends GdUnitTestSuite
## The poser's own wheel pose (#1485; ARCHITECTURE §4.2, §7.1.23): the client gets no avatar of
## itself, so its SelfStatus carries `wheel_pose`. A taken pose sends the poser one SelfStatus with
## the pose's byte at the end of the tick, also with no claim in that tick (TakeWheelPose touches
## the feed); a new pick sends one, the same pick again and a push send nothing; every end sends
## one with 0: an own move, a crouch, the chair, a knockdown, a kill, a placement. Nobody else gets
## the poser's status.

const P1 := 1
const P2 := 2
const EAST := Vector3(1, 0, 0)
const NORTH := Vector3(0, 0, 1)
const LEGS := 1
const ARMS := 2

var _sent := 0


func test_a_pick_sends_the_poser_alone_one_status_with_the_pose() -> void:
	var game := _wheel_round([P1, P2])
	FixtureModes.run_ticks(game, 1)
	var before := FixtureMoves.statuses(game, P1).size()
	var others := FixtureMoves.statuses(game, P2).size()
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1)
	var code := WheelPoseCode.encode(LEGS, ARMS)
	assert_int(sent.size()).is_equal(before + 1)
	assert_int(sent.back().wheel_pose).is_equal(code)
	assert_int((sent.back() as SelfStatusEvent).to_dict()["wheel_pose"]).is_equal(code)
	assert_int(FixtureMoves.statuses(game, P2).size()).is_equal(others)
	for event: MatchEvent in game.view_of(P2).events_named(&"SelfStatus"):
		assert_int((event as SelfStatusEvent).wheel_pose).is_equal(WheelPoseCode.NONE)


func test_the_same_pick_again_sends_nothing_and_a_new_one_sends_one() -> void:
	var game := _posed_round([P1, P2])
	var sent := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(sent)
	FixtureMoves.wheel_pose(game, P1, 0, 0)
	FixtureModes.run_ticks(game, 1)
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(sent + 1)
	assert_int(statuses.back().wheel_pose).is_equal(WheelPoseCode.encode(0, 0))


func test_a_push_and_a_turn_send_no_status() -> void:
	var game := _wheel_round([P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, EAST)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.step(game, P1, NORTH * 0.1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": EAST})
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(sent)


func test_an_own_move_sends_no_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, EAST * 0.1, {"moving": true})
	_assert_one_end(game)


func test_a_crouch_sends_no_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO, {"crouched": true})
	_assert_one_end(game)


func test_the_chair_sends_posed_and_no_wheel_pose() -> void:
	var game := _posed_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	_assert_one_end(game)
	assert_bool(FixtureMoves.statuses(game, P1).back().posed).is_true()


func test_a_knockdown_sends_no_pose() -> void:
	var game := _posed_round([P1, P2])
	LifeRules.knock_down(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	_assert_one_end(game)


func test_a_kill_at_zero_health_sends_no_pose() -> void:
	# The health is 0 already, so only _to_dead's touch tells the client the pose ended.
	var game := _posed_round([P1, P2])
	game.state.player(P1).health = 0
	LifeRules.kill(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	_assert_one_end(game)


func test_a_placement_sends_no_pose() -> void:
	var game := _posed_round([P1, P2])
	var place := PlacePlayers.new()
	place.tag = &"round_player"
	var ctx := FixtureMoves.context(game)
	ctx.layout = game.layout(game.state.map)
	place.run(ctx)
	FixtureModes.run_ticks(game, 1)
	_assert_one_end(game)


## The wheeling and posing fixture's round, a seat beside every player's placement spot.
func _wheel_round(peers: Array[int]) -> Match:
	var mode := FixtureMoves.wheeling(FixtureMoves.posing(FixtureModes.basic()))
	var game := FixtureItemModes.in_round(mode, peers, FixtureTerrainWorld.new())
	for peer: int in peers:
		FixtureMoves.seat(game, peer)
	return game


## _wheel_round with P1 in the pose (LEGS, ARMS); its status sent and remembered in `_sent`.
func _posed_round(peers: Array[int]) -> Match:
	var game := _wheel_round(peers)
	FixtureMoves.wheel_pose(game, P1, LEGS, ARMS)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.statuses(game, P1).back().wheel_pose).is_equal(
		WheelPoseCode.encode(LEGS, ARMS)
	)
	_sent = FixtureMoves.statuses(game, P1).size()
	return game


## P1 got exactly one more SelfStatus since _posed_round, and it says no wheel pose.
func _assert_one_end(game: Match) -> void:
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(_sent + 1)
	assert_int(statuses.back().wheel_pose).is_equal(WheelPoseCode.NONE)
