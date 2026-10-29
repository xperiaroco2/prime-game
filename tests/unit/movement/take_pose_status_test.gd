extends GdUnitTestSuite
## The poser's own state (#1383; ARCHITECTURE §4.2, §7.1.19): the client gets no avatar of
## itself, so its SelfStatus carries `posed`. A taken pose sends the poser one SelfStatus with
## `posed` true at the end of the tick, also with no claim in that tick (TakePose touches the
## feed); every end of the pose sends one with `posed` false: an own move, a knockdown, a kill, a
## placement; a push and a second Pose send nothing. Nobody else gets the poser's status.

const P1 := 1
const P2 := 2
const EAST := Vector3(1, 0, 0)
const NORTH := Vector3(0, 0, 1)


func test_a_pose_sends_the_poser_alone_one_status_posed() -> void:
	var game := _posing_round([P1, P2])
	FixtureModes.run_ticks(game, 1)
	var before := FixtureMoves.statuses(game, P1).size()
	var others := FixtureMoves.statuses(game, P2).size()
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1)
	assert_int(sent.size()).is_equal(before + 1)
	assert_bool(sent.back().posed).is_true()
	assert_bool((sent.back() as SelfStatusEvent).to_dict()["posed"]).is_true()
	assert_int(FixtureMoves.statuses(game, P2).size()).is_equal(others)
	for event: MatchEvent in game.view_of(P2).events_named(&"SelfStatus"):
		assert_bool((event as SelfStatusEvent).posed).is_false()


func test_a_second_pose_sends_nothing() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.pose(game, P1, 1)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(sent)


func test_a_refused_pose_sends_nothing() -> void:
	var game := FixtureItemModes.in_round(
		FixtureMoves.posing(FixtureModes.basic()), [P1, P2], FixtureTerrainWorld.new()
	)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([AtMarker.OUT_OF_REACH])
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(sent)


func test_an_own_move_sends_posed_false() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, NORTH * 0.1, {"moving": true})
	assert_bool(game.state.player(P1).posed).is_false()
	assert_bool(FixtureMoves.statuses(game, P1).back().posed).is_false()


func test_a_push_sends_no_status() -> void:
	# Answer 3a on PR #1382: a push keeps the watcher seated, so its client is told nothing.
	var game := _posing_round([P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureMoves.seat(game, P1)
	FixtureItemModes.stand(game, P2, EAST)
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.step(game, P1, NORTH * 0.1)
	assert_bool(game.state.player(P1).posed).is_true()
	assert_int(FixtureMoves.statuses(game, P1).size()).is_equal(sent)


func test_a_pose_and_a_move_in_one_tick_send_nothing() -> void:
	# The feed sends the tick's final status: seated and up again in one tick is no change.
	var game := _posing_round([P1, P2])
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1).size()
	FixtureMoves.pose(game, P1)
	FixtureMoves.claim(game, P1, game.state.player(P1).position, {"moving": true})
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_false()
	for event: SelfStatusEvent in FixtureMoves.statuses(game, P1).slice(sent):
		assert_bool(event.posed).is_false()


func test_a_knockdown_sends_posed_false() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	LifeRules.knock_down(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DOWNED)
	assert_bool(FixtureMoves.statuses(game, P1).back().posed).is_false()


func test_a_kill_sends_posed_false() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	LifeRules.kill(FixtureMoves.context(game), P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(FixtureMoves.statuses(game, P1).back().posed).is_false()


func test_a_placement_sends_posed_false() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	var sent := FixtureMoves.statuses(game, P1).size()
	var place := PlacePlayers.new()
	place.tag = &"round_player"
	var ctx := FixtureMoves.context(game)
	ctx.layout = game.layout(game.state.map)
	place.run(ctx)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_false()
	var statuses := FixtureMoves.statuses(game, P1)
	assert_int(statuses.size()).is_equal(sent + 1)
	assert_bool(statuses.back().posed).is_false()


## A round of the posing fixture with a seat beside every player's placement spot.
func _posing_round(peers: Array[int]) -> Match:
	var game := FixtureItemModes.in_round(
		FixtureMoves.posing(FixtureModes.basic()), peers, FixtureTerrainWorld.new()
	)
	for peer: int in peers:
		FixtureMoves.seat(game, peer)
	return game
